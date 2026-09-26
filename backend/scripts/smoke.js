// LIVE smoke test against a RUNNING bump-api (which talks to real xAI).
// Costs a tiny amount of API credit. The key lives only in the server's
// environment; this script never reads or prints it.
//
//   npm start                                  # in one terminal
//   npm run smoke                              # in another
//   npm run smoke -- --audio /tmp/intro.m4a    # also test speech to text
//
// Target defaults to http://localhost:8787; override with BUMP_API_URL.

import fs from 'node:fs';
import path from 'node:path';

const BASE = (process.env.BUMP_API_URL || 'http://localhost:8787').replace(/\/+$/, '');

const audioFlag = process.argv.indexOf('--audio');
const audioPath = audioFlag !== -1 ? process.argv[audioFlag + 1] : null;
if (audioFlag !== -1 && !audioPath) {
  console.error('Usage: npm run smoke -- --audio <path-to-audio-file>');
  process.exit(2);
}

const TRANSCRIPT =
  "Hi, I'm Sam. I play jazz piano and I've been getting into bouldering. I'd love to meet people building hardware.";

let failures = 0;

async function step(label, fn) {
  const started = Date.now();
  try {
    const result = await fn();
    console.log(`\n[LIVE] ✔ ${label} (${Date.now() - started} ms)`);
    console.log(JSON.stringify(result, null, 2));
    return result;
  } catch (err) {
    failures += 1;
    console.log(`\n[LIVE] ✖ ${label} (${Date.now() - started} ms)`);
    console.log(`  ${err.message}`);
    return null;
  }
}

async function call(method, pathName, { json, body, contentType } = {}) {
  const res = await fetch(`${BASE}${pathName}`, {
    method,
    headers: json !== undefined ? { 'content-type': 'application/json' } : contentType ? { 'content-type': contentType } : {},
    body: json !== undefined ? JSON.stringify(json) : body,
  });
  const text = await res.text();
  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new Error(`HTTP ${res.status}: response was not JSON`);
  }
  if (!res.ok) throw new Error(`HTTP ${res.status}: ${JSON.stringify(parsed)}`);
  return parsed;
}

function expect(cond, message) {
  if (!cond) throw new Error(`unexpected response: ${message}`);
}

console.log(`[LIVE] bump-api smoke test against ${BASE} (real xAI calls)`);

const health = await step('GET /healthz', async () => {
  const h = await call('GET', '/healthz');
  expect(h.ok === true, 'ok should be true');
  expect(h.grokConfigured === true, 'grokConfigured is false — set XAI_API_KEY in backend/.env and restart');
  return h;
});

if (!health) {
  console.log('\n[LIVE] Server not reachable or not configured; stopping.');
  process.exit(1);
}

let transcript = TRANSCRIPT;

if (audioPath) {
  const ext = path.extname(audioPath).toLowerCase();
  const type = { '.wav': 'audio/wav', '.mp3': 'audio/mpeg' }[ext] ?? 'audio/mp4';
  const audio = fs.readFileSync(audioPath);
  const stt = await step(`POST /v1/transcribe (${path.basename(audioPath)}, ${audio.length} bytes, ${type})`, async () => {
    const r = await call('POST', '/v1/transcribe', { body: audio, contentType: type });
    expect(typeof r.transcript === 'string' && r.transcript.length > 0, 'transcript should be non-empty');
    return r;
  });
  if (stt) transcript = stt.transcript.slice(0, 2000);
}

const draft = await step('POST /v1/profile/draft', async () => {
  const r = await call('POST', '/v1/profile/draft', {
    json: { transcript, catalogLabels: ['Music', 'Jazz piano', 'Bouldering', 'Hardware', 'Espresso'] },
  });
  expect(Array.isArray(r.facts), 'facts should be an array');
  expect(r.generator?.provider === 'xai', 'generator.provider should be xai');
  return r;
});

const firstQuestion = draft?.question ?? 'What are you hoping to get out of today?';

await step('POST /v1/profile/followup', async () => {
  const r = await call('POST', '/v1/profile/followup', {
    json: {
      known: (draft?.facts ?? []).map(({ kind, label }) => ({ kind, label })).slice(0, 30),
      asked: [firstQuestion],
      answer: 'Mostly Bill Evans, and I am prototyping a small synth on a Raspberry Pi.',
      catalogLabels: ['Music', 'Jazz piano', 'Hardware'],
    },
  });
  expect(Array.isArray(r.facts), 'facts should be an array');
  return r;
});

await step('POST /v1/talking-points', async () => {
  const r = await call('POST', '/v1/talking-points', {
    json: {
      candidates: [
        { id: 'c1', kind: 'shared', mine: 'Jazz piano', theirs: 'Jazz piano' },
        { id: 'c2', kind: 'complementary', mine: 'Bouldering', theirs: 'Climbing coach' },
      ],
    },
  });
  expect(typeof r.opener === 'string' && r.opener.endsWith('?'), 'opener should be a question');
  return r;
});

console.log(failures ? `\n[LIVE] ${failures} step(s) failed.` : '\n[LIVE] All steps passed.');
process.exit(failures ? 1 : 0);
