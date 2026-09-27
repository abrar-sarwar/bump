// bump-api: a tiny HTTP server between the BUMP iOS app and xAI.
// The HTTP contract lives in ../CONTRACT.md.
//
// Run directly (`npm start`) it reads config from the environment (and an
// optional local .env). Tests import `start(config)` and pass config directly.

import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

import { ApiError, badRequest, notConfigured, tooLarge } from './errors.js';
import { createRateLimiter } from './ratelimit.js';
import { DRAFT, FOLLOWUP, TAG_INTERESTS, TALKING_POINTS } from './prompts.js';
import { generateJson, speak, transcribe } from './xai.js';
import { createRelay } from './relay.js';
import {
  LIMITS,
  checkDraftOutput,
  checkFollowupOutput,
  checkTalkingPointsOutput,
  parseDraftRequest,
  parseFollowupRequest,
  parseTalkingPointsRequest,
  parseTagRequest,
  checkTagOutput,
} from './validate.js';

// Body size limits per endpoint (bytes).
const BODY_LIMITS = {
  transcribe: 3 * 1024 * 1024,
  draft: 16 * 1024,
  followup: 16 * 1024,
  talkingPoints: 8 * 1024,
  relay: 128 * 1024,
  tts: 4 * 1024,
  tags: 16 * 1024,
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
  ttsTimeoutMs: 10_000,
  ttsVoice: 'eve',
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
    reasoningEffort: env.XAI_REASONING_EFFORT !== undefined ? env.XAI_REASONING_EFFORT.trim() : DEFAULTS.reasoningEffort,
    baseUrl: env.XAI_BASE_URL?.trim() || DEFAULTS.baseUrl,
    port: Number.isInteger(port) ? port : DEFAULTS.port,
    host: env.HOST?.trim() || DEFAULTS.host,
    ttsVoice: env.XAI_TTS_VOICE?.trim() || DEFAULTS.ttsVoice,
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

  const generator = (model) => ({ provider: 'xai', model });
  const relay = createRelay({ log: config.log, limits: config.relayLimits });

  function requireKey() {
    if (!config.apiKey) throw notConfigured();
  }

  // --- Route handlers -----------------------------------------------------

  async function healthz() {
    return {
      ok: true,
      grokConfigured: Boolean(config.apiKey),
      relay: true,
      model: config.model,
      sttModel: config.sttModel,
    };
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

  async function relaySendRoute(req) {
    const body = await readJson(req, BODY_LIMITS.relay);
    try {
      return relay.send(body);
    } catch (code) {
      if (code === 'too_large') throw tooLarge();
      if (code === 'not_a_member') throw new ApiError(409, 'not_a_member', 'Open the relay stream before sending.');
      throw badRequest('room, from, to[] and data are required.');
    }
  }

  async function relayLeaveRoute(req) {
    try {
      return relay.leave(await readJson(req, 1024));
    } catch (err) {
      if (err instanceof ApiError) throw err;
      throw badRequest('room and peer are required.');
    }
  }

  // Short text only: this reads onboarding questions aloud.
  async function ttsRoute(req, res) {
    requireKey();
    const body = await readJson(req, BODY_LIMITS.tts);
    const text = typeof body?.text === 'string' ? body.text.trim() : '';
    if (!text || text.length > 300) throw badRequest('text is required, up to 300 characters.');
    const audio = await speak(config, text, config.ttsVoice);
    res.writeHead(200, { 'content-type': 'audio/mpeg', 'content-length': audio.length, 'cache-control': 'no-store' });
    res.end(audio);
    return undefined;
  }

  async function tagRoute(req) {
    requireKey();
    const input = parseTagRequest(await readJson(req, BODY_LIMITS.tags));
    if (input.interests.length === 0) return { tags: {}, generator: { provider: 'none', model: 'none' } };
    const { data, model } = await generateJson(config, {
      name: TAG_INTERESTS.name,
      instructions: TAG_INTERESTS.instructions,
      schema: TAG_INTERESTS.schema,
      input: TAG_INTERESTS.input(input),
    });
    return { ...checkTagOutput(data, input), generator: generator(model) };
  }

  const routes = {
    '/v1/interests/tag': { POST: tagRoute },
    '/v1/tts': { POST: ttsRoute },
    '/v1/relay/send': { POST: relaySendRoute },
    '/v1/relay/leave': { POST: relayLeaveRoute },
    '/healthz': { GET: healthz },
    '/v1/transcribe': { POST: transcribeRoute },
    '/v1/profile/draft': { POST: draftRoute },
    '/v1/profile/followup': { POST: followupRoute },
    '/v1/talking-points': { POST: talkingPointsRoute },
  };

  // --- Request pipeline ---------------------------------------------------

  function checkRateLimit(req, pathname) {
    if (pathname === '/healthz') return; // cheap, and useful for the app to poll
    if (pathname.startsWith('/v1/relay/')) return; // bump traffic, not Grok spend
    const ip = req.socket.remoteAddress ?? 'unknown';
    // Check every applicable limiter before charging any of them, so a
    // request blocked by one doesn't use up the other's quota.
    const applicable = pathname === '/v1/transcribe' ? [limiter, sttLimiter] : [limiter];
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
    if (pathname === '/v1/relay/poll' && req.method === 'GET') {
      const query = new URL(req.url, 'http://x').searchParams;
      const abort = new AbortController();
      res.once('close', () => abort.abort());
      try {
        const reply = await relay.poll(query, abort.signal);
        if (!res.destroyed) sendJson(res, 200, reply);
      } catch (code) {
        if (code === 'room_full') throw new ApiError(409, 'room_full', 'This room is full.');
        throw badRequest('room and peer are required.');
      }
      return;
    }
    const route = routes[pathname];
    if (!route) throw new ApiError(404, 'not_found', 'No such endpoint.');
    const handler = route[req.method];
    if (!handler) throw new ApiError(405, 'method_not_allowed', 'Method not allowed.');
    checkRateLimit(req, pathname);
    const body = await handler(req, res);
    if (!res.headersSent) sendJson(res, 200, body);
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
  console.log(`model=${model} reasoningEffort=${server.config.reasoningEffort || '(model default)'} sttModel=${sttModel} grokConfigured=${Boolean(apiKey)}`);
  if (!apiKey) console.log('XAI_API_KEY is not set: Grok endpoints will answer 503 not_configured.');

  const shutdown = () => server.close(() => process.exit(0));
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}
