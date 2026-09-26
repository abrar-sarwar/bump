// bump-api: a tiny HTTP server between the BUMP iOS app and xAI.
// The HTTP contract lives in ../CONTRACT.md.
//
// Run directly (`npm start`) it reads config from the environment (and an
// optional local .env). Tests import `start(config)` and pass config directly.

import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

import { ApiError, badRequest, notConfigured, storageNotConfigured, tooLarge } from './errors.js';
import { createRateLimiter } from './ratelimit.js';
import { DRAFT, FOLLOWUP, REVISE, TALKING_POINTS } from './prompts.js';
import { insertTranscript } from './supabase.js';
import { createVoiceSecret, generateJson, transcribe } from './xai.js';
import {
  LIMITS,
  checkDraftOutput,
  checkFollowupOutput,
  checkReviseOutput,
  checkTalkingPointsOutput,
  parseDraftRequest,
  parseReviseRequest,
  parseFollowupRequest,
  parseTalkingPointsRequest,
  parseTranscriptRequest,
} from './validate.js';

// Body size limits per endpoint (bytes).
const BODY_LIMITS = {
  transcribe: 3 * 1024 * 1024,
  draft: 16 * 1024,
  followup: 16 * 1024,
  talkingPoints: 8 * 1024,
  revise: 16 * 1024,
  voiceSession: 1024,
  onboardingTranscript: 16 * 1024,
};

export const DEFAULTS = {
  apiKey: null,
  model: 'grok-4.3',
  sttModel: 'grok-voice-transcribe-2.0',
  // grok-4.3 defaults to "low"; "none" measured ~3x faster for these short
  // structured tasks. Empty string = don't send the field (for models without it).
  reasoningEffort: 'none',
  baseUrl: 'https://api.x.ai',
  port: 8787,
  host: '0.0.0.0',
  llmTimeoutMs: 12_000,
  sttTimeoutMs: 20_000,
  // Realtime voice (spoken onboarding). The phone gets a short-lived token.
  voiceModel: 'grok-voice-latest',
  voice: 'eve',
  voiceTokenSeconds: 300,
  voiceRateLimitPerMinute: 6,
  // Onboarding transcripts are saved to Supabase (secret key, server only).
  supabaseUrl: null,
  supabaseSecretKey: null,
  storageTimeoutMs: 8_000,
  rateLimitPerMinute: 30,
  transcribeRateLimitPerMinute: 6,
  log: (line) => console.log(line),
};

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

/**
 * Minimal .env loader: KEY=VALUE lines, # comments and blank lines ignored,
 * optional surrounding quotes stripped. Never overrides variables that are
 * already set in the environment.
 */
export function loadDotEnv(file, env = process.env) {
  let text;
  try {
    text = fs.readFileSync(file, 'utf8');
  } catch {
    return; // no .env is fine
  }
  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;
    const eq = line.indexOf('=');
    if (eq <= 0) continue;
    const key = line.slice(0, eq).replace(/^export\s+/, '').trim();
    let value = line.slice(eq + 1).trim();
    if (value.length >= 2 && (value[0] === '"' || value[0] === "'") && value.at(-1) === value[0]) {
      value = value.slice(1, -1);
    }
    if (env[key] === undefined) env[key] = value;
  }
}

/** Build a config object from environment variables. */
export function configFromEnv(env = process.env) {
  const port = Number.parseInt(env.PORT ?? '', 10);
  return {
    apiKey: env.XAI_API_KEY?.trim() || null,
    model: env.XAI_MODEL?.trim() || DEFAULTS.model,
    sttModel: env.XAI_STT_MODEL?.trim() || DEFAULTS.sttModel,
    voiceModel: env.XAI_VOICE_MODEL?.trim() || DEFAULTS.voiceModel,
    voice: env.XAI_VOICE?.trim() || DEFAULTS.voice,
    reasoningEffort: env.XAI_REASONING_EFFORT !== undefined ? env.XAI_REASONING_EFFORT.trim() : DEFAULTS.reasoningEffort,
    baseUrl: env.XAI_BASE_URL?.trim() || DEFAULTS.baseUrl,
    port: Number.isInteger(port) ? port : DEFAULTS.port,
    host: env.HOST?.trim() || DEFAULTS.host,
    supabaseUrl: env.SUPABASE_URL?.trim() || null,
    supabaseSecretKey: env.SUPABASE_SECRET_KEY?.trim() || null,
  };
}

// ---------------------------------------------------------------------------
// HTTP helpers
// ---------------------------------------------------------------------------

function sendJson(res, status, body, headers = {}) {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(payload),
    'cache-control': 'no-store',
    ...headers,
  });
  res.end(payload);
}

/**
 * Read the request body into memory, refusing (413) as soon as it crosses
 * `limit` bytes. A declared Content-Length over the limit is refused before
 * reading anything.
 */
function readBody(req, limit) {
  const declared = Number(req.headers['content-length']);
  if (Number.isFinite(declared) && declared > limit) return Promise.reject(tooLarge());

  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    let settled = false;
    const onData = (chunk) => {
      size += chunk.length;
      if (size > limit) {
        settled = true;
        chunks.length = 0;
        req.off('data', onData);
        reject(tooLarge());
        return;
      }
      chunks.push(chunk);
    };
    req.on('data', onData);
    req.on('end', () => {
      if (!settled) {
        settled = true;
        resolve(Buffer.concat(chunks, size));
      }
    });
    req.on('error', (err) => {
      if (!settled) {
        settled = true;
        reject(err);
      }
    });
  });
}

async function readJson(req, limit) {
  const buf = await readBody(req, limit);
  try {
    return JSON.parse(buf.toString('utf8'));
  } catch {
    throw badRequest('Body must be valid JSON.');
  }
}

// ---------------------------------------------------------------------------
// Server
// ---------------------------------------------------------------------------

export function createServer(options = {}) {
  const config = { ...DEFAULTS, ...options };
  config.apiKey = typeof config.apiKey === 'string' && config.apiKey.trim() ? config.apiKey.trim() : null;

  const limiter = createRateLimiter({ limit: config.rateLimitPerMinute });
  const sttLimiter = createRateLimiter({ limit: config.transcribeRateLimitPerMinute });
  const voiceLimiter = createRateLimiter({ limit: config.voiceRateLimitPerMinute });

  const generator = (model) => ({ provider: 'xai', model });

  function requireKey() {
    if (!config.apiKey) throw notConfigured();
  }

  // --- Route handlers -----------------------------------------------------

  async function healthz() {
    return {
      ok: true,
      grokConfigured: Boolean(config.apiKey),
      storageConfigured: Boolean(config.supabaseUrl && config.supabaseSecretKey),
      model: config.model,
      sttModel: config.sttModel,
      voiceModel: config.voiceModel,
    };
  }

  /**
   * Issue a short-lived realtime voice token. The response carries only the
   * temporary token, never the API key, and the token is never logged.
   */
  async function voiceSessionRoute(req) {
    requireKey();
    await readBody(req, BODY_LIMITS.voiceSession); // body is ignored; bounded anyway
    const secret = await createVoiceSecret(config);
    const wsBase = config.baseUrl.replace(/^http/, 'ws');
    return {
      token: secret.value,
      expiresAt: secret.expiresAt,
      url: `${wsBase}/v1/realtime`,
      model: config.voiceModel,
      voice: config.voice,
    };
  }

  async function reviseRoute(req) {
    requireKey();
    const input = parseReviseRequest(await readJson(req, BODY_LIMITS.revise));
    const { data, model } = await generateJson(config, {
      name: REVISE.name,
      instructions: REVISE.instructions,
      schema: REVISE.schema,
      input: REVISE.input(input),
    });
    return { ...checkReviseOutput(data, input), generator: generator(model) };
  }

  async function transcribeRoute(req) {
    requireKey();
    const contentType = String(req.headers['content-type'] ?? '').toLowerCase();
    if (!contentType.startsWith('audio/')) {
      throw new ApiError(415, 'unsupported_media', 'Body must be audio (Content-Type audio/*).');
    }
    const audio = await readBody(req, BODY_LIMITS.transcribe);
    if (audio.length === 0) throw badRequest('Audio body is empty.');

    const result = await transcribe(config, audio, contentType);
    const transcript = result.text.trim();
    if (!transcript) {
      throw new ApiError(422, 'empty_audio', 'No speech was recognised in the recording.');
    }
    return { transcript, durationSeconds: result.duration, generator: generator(result.model) };
  }

  async function draftRoute(req) {
    requireKey();
    const input = parseDraftRequest(await readJson(req, BODY_LIMITS.draft));
    const { data, model } = await generateJson(config, {
      name: DRAFT.name,
      instructions: DRAFT.instructions,
      schema: DRAFT.schema,
      input: DRAFT.input(input),
    });
    return { ...checkDraftOutput(data, input), generator: generator(model) };
  }

  async function followupRoute(req) {
    requireKey();
    const input = parseFollowupRequest(await readJson(req, BODY_LIMITS.followup));
    const wantQuestion = input.asked.length < LIMITS.asked;

    // Nothing to extract and no question allowed: no need to ask the model.
    if (!wantQuestion && !input.answer.trim()) {
      // No model call was made, so don't label this as a Grok result.
      return { facts: [], question: null, generator: { provider: 'none', model: 'none' } };
    }

    const { data, model } = await generateJson(config, {
      name: FOLLOWUP.name,
      instructions: FOLLOWUP.instructions,
      schema: wantQuestion ? FOLLOWUP.schema : FOLLOWUP.schemaFactsOnly,
      input: FOLLOWUP.input(input),
    });
    return { ...checkFollowupOutput(data, input), generator: generator(model) };
  }

  async function talkingPointsRoute(req) {
    requireKey();
    const input = parseTalkingPointsRequest(await readJson(req, BODY_LIMITS.talkingPoints));
    const { data, model } = await generateJson(config, {
      name: TALKING_POINTS.name,
      instructions: TALKING_POINTS.instructions,
      schema: TALKING_POINTS.schema,
      input: TALKING_POINTS.input(input),
    });
    return { ...checkTalkingPointsOutput(data, input), generator: generator(model) };
  }

  /**
   * Save what the person said during onboarding. The app calls this once, when
   * they finish, and only if they allowed cloud processing. Text only: audio is
   * never stored.
   */
  async function onboardingTranscriptRoute(req) {
    if (!config.supabaseUrl || !config.supabaseSecretKey) throw storageNotConfigured();
    const input = parseTranscriptRequest(await readJson(req, BODY_LIMITS.onboardingTranscript));
    await insertTranscript(config, input);
    return { saved: true };
  }

  const routes = {
    '/healthz': { GET: healthz },
    '/v1/transcribe': { POST: transcribeRoute },
    '/v1/profile/draft': { POST: draftRoute },
    '/v1/profile/followup': { POST: followupRoute },
    '/v1/talking-points': { POST: talkingPointsRoute },
    '/v1/voice/session': { POST: voiceSessionRoute },
    '/v1/profile/revise': { POST: reviseRoute },
    '/v1/onboarding/transcript': { POST: onboardingTranscriptRoute },
  };

  // --- Request pipeline ---------------------------------------------------

  function checkRateLimit(req, pathname) {
    if (pathname === '/healthz') return; // cheap, and useful for the app to poll
    const ip = req.socket.remoteAddress ?? 'unknown';
    // Check every applicable limiter before charging any of them, so a
    // request blocked by one doesn't use up the other's quota.
    const applicable =
      pathname === '/v1/transcribe' ? [limiter, sttLimiter]
        : pathname === '/v1/voice/session' ? [limiter, voiceLimiter]
          : [limiter];
    const full = applicable.find((l) => !l.allows(ip));
    const results = full ? [full.hit(ip)] : applicable.map((l) => l.hit(ip));
    const blocked = results.find((r) => !r.ok);
    if (blocked) {
      throw new ApiError(429, 'rate_limited', 'Too many requests. Please wait a moment.', {
        'retry-after': String(blocked.retryAfter),
      });
    }
  }

  async function handle(req, res) {
    const pathname = (req.url ?? '/').split('?')[0];
    const route = routes[pathname];
    if (!route) throw new ApiError(404, 'not_found', 'No such endpoint.');
    const handler = route[req.method];
    if (!handler) throw new ApiError(405, 'method_not_allowed', 'Method not allowed.');
    checkRateLimit(req, pathname);
    const body = await handler(req);
    sendJson(res, 200, body);
  }

  const server = http.createServer((req, res) => {
    const started = performance.now();
    const pathname = (req.url ?? '/').split('?')[0].slice(0, 100);
    // One line per request. Never bodies, headers, or user text.
    res.once('close', () => {
      const ms = Math.round(performance.now() - started);
      config.log(`${req.method} ${pathname} ${res.statusCode} ${ms}ms`);
    });

    handle(req, res).catch((err) => {
      const apiErr =
        err instanceof ApiError ? err : new ApiError(500, 'internal_error', 'Something went wrong.');
      if (!(err instanceof ApiError)) config.log(`internal error: ${err?.name ?? 'unknown'}`);
      if (res.headersSent) {
        res.destroy();
        return;
      }

      sendJson(res, apiErr.status, { error: { code: apiErr.code, message: apiErr.message } }, apiErr.headers);

      // If we answered before the whole body arrived (413, 415, 429, 503...),
      // discard the rest without buffering it so the client can finish its
      // upload and read the error. Closing the socket immediately would make
      // most clients report a broken pipe instead of our status code. A
      // client that keeps sending for too long is cut off.
      if (!req.complete) {
        req.resume();
        const timer = setTimeout(() => req.socket.destroy(), 5000);
        timer.unref();
        req.once('end', () => clearTimeout(timer));
      }
    });
  });

  server.config = config; // handy for tests; contains the key, so never serialise it
  return server;
}

/** Create and start listening. Resolves with the http.Server once bound. */
export function start(options = {}) {
  const server = createServer(options);
  const { port, host } = server.config;
  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(port, host, () => {
      server.off('error', reject);
      resolve(server);
    });
  });
}

// ---------------------------------------------------------------------------
// Entry point: `node src/server.js`
// ---------------------------------------------------------------------------

const isMain = process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href;

if (isMain) {
  const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
  loadDotEnv(path.join(root, '.env'));
  const server = await start(configFromEnv());
  const { host, model, sttModel, apiKey } = server.config;
  const { port } = server.address();
  console.log(`bump-api listening on http://${host}:${port}`);
  console.log(`storageConfigured=${Boolean(server.config.supabaseUrl && server.config.supabaseSecretKey)}`);
  console.log(`model=${model} reasoningEffort=${server.config.reasoningEffort || '(model default)'} sttModel=${sttModel} grokConfigured=${Boolean(apiKey)}`);
  if (!apiKey) console.log('XAI_API_KEY is not set: Grok endpoints will answer 503 not_configured.');

  const shutdown = () => server.close(() => process.exit(0));
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}
