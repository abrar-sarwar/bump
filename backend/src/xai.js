// Upstream calls to xAI. Two endpoints:
//   POST {base}/v1/responses : structured JSON output (Responses API)
//   POST {base}/v1/stt        : speech to text (multipart)
//   POST {base}/v1/tts        : text to speech (MP3 bytes)
//
// Failures map to contract errors: abort/timeout → 504 upstream_timeout,
// non-2xx or network failure → 502 upstream_error, unusable body → 502
// upstream_invalid. Upstream bodies are never echoed to the client or logged;
// only the upstream status code is logged.

import { upstreamError, upstreamInvalid, upstreamTimeout } from './errors.js';

const isTimeout = (err) => err?.name === 'TimeoutError' || err?.name === 'AbortError';

async function postUpstream(config, path, { headers = {}, body, raw = false }, timeoutMs) {
  const signal = AbortSignal.timeout(timeoutMs);
  let res;
  try {
    res = await fetch(`${config.baseUrl}${path}`, {
      method: 'POST',
      headers: { ...headers, authorization: `Bearer ${config.apiKey}` },
      body,
      signal,
    });
  } catch (err) {
    if (isTimeout(err)) throw upstreamTimeout();
    config.log(`upstream ${path} network error`);
    throw upstreamError();
  }

  if (!res.ok) {
    config.log(`upstream ${path} status ${res.status}`);
    await res.body?.cancel().catch(() => {});
    throw upstreamError();
  }

  // Reading the body is covered by the same timeout signal.
  try {
    if (raw) return Buffer.from(await res.arrayBuffer());
    return await res.json();
  } catch (err) {
    if (isTimeout(err)) throw upstreamTimeout();
    throw upstreamInvalid();
  }
}

/** Pull the model's text out of a Responses API result. */
export function extractOutputText(json) {
  if (typeof json?.output_text === 'string') return json.output_text;
  if (!Array.isArray(json?.output)) return null;
  for (const item of json.output) {
    if (item?.type !== 'message' || !Array.isArray(item.content)) continue;
    const part = item.content.find((c) => c?.type === 'output_text' && typeof c.text === 'string');
    if (part) return part.text;
  }
  return null;
}

/**
 * Run one structured-output call. Returns { data, model } where `data` is the
 * parsed JSON object (not yet validated) and `model` is the model xAI says it used.
 */
export async function generateJson(config, { name, instructions, schema, input }) {
  const body = {
    model: config.model,
    instructions,
    input: [{ role: 'user', content: input }],
    store: false,
    // Includes reasoning tokens on reasoning models, so leave headroom.
    max_output_tokens: 4000,
    temperature: 0.4,
    text: { format: { type: 'json_schema', name, schema, strict: true } },
  };
  if (config.reasoningEffort) body.reasoning = { effort: config.reasoningEffort };
  const json = await postUpstream(
    config,
    '/v1/responses',
    { headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) },
    config.llmTimeoutMs,
  );

  const text = extractOutputText(json);
  if (typeof text !== 'string') throw upstreamInvalid();
  let data;
  try {
    data = JSON.parse(text);
  } catch {
    throw upstreamInvalid();
  }
  const model = typeof json.model === 'string' && json.model ? json.model : config.model;
  return { data, model };
}

/** Pick a filename extension xAI will recognise for the incoming audio type. */
export function audioFilename(contentType) {
  const type = contentType.split(';')[0].trim().toLowerCase();
  if (type === 'audio/wav' || type === 'audio/x-wav' || type === 'audio/wave') return 'intro.wav';
  if (type === 'audio/mpeg' || type === 'audio/mp3') return 'intro.mp3';
  return 'intro.m4a'; // audio/mp4, audio/m4a, audio/x-m4a and anything else
}

/**
 * Transcribe audio held in memory. Returns { text, duration, model }.
 * The audio buffer is never written anywhere; it is dropped after the call.
 */
export async function transcribe(config, audio, contentType) {
  const type = contentType.split(';')[0].trim().toLowerCase();
  const form = new FormData();
  form.append('model', config.sttModel);
  form.append('language', 'en');
  form.append('format', 'true');
  // xAI requires the file part to be LAST.
  form.append('file', new Blob([audio], { type }), audioFilename(type));

  const json = await postUpstream(config, '/v1/stt', { body: form }, config.sttTimeoutMs);
  if (json === null || typeof json !== 'object' || typeof json.text !== 'string') throw upstreamInvalid();
  const duration = typeof json.duration === 'number' && Number.isFinite(json.duration) ? json.duration : null;
  return { text: json.text, duration, model: config.sttModel };
}

/** Text to speech. Returns MP3 bytes. */
export async function speak(config, text, voice) {
  const audio = await postUpstream(
    config,
    '/v1/tts',
    {
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        text,
        voice_id: voice,
        language: 'en',
        output_format: { codec: 'mp3', sample_rate: 24000, bit_rate: 64000 },
      }),
      raw: true,
    },
    config.ttsTimeoutMs,
  );
  if (!audio.length) throw upstreamInvalid();
  return audio;
}
