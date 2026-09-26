// MOCKED tests for saving onboarding transcripts. A FAKE Supabase REST API
// answers; no request leaves this machine and no real key is used.

import test, { before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

import { postJson, startApi, startFakeXai } from './helpers.js';

const SECRET = 'sb_secret_DUMMY-test-key-0000';
const INSTALL = '6f1c2b1e-9d7a-4c3e-8b5a-2f4d6e8a0c11';
const TRANSCRIPT = "Hi, I'm Sam. I play jazz piano and I've been getting into bouldering.";

let supabase;
let api;

before(async () => {
  supabase = await startFakeXai(); // any JSON-recording fake server will do
  api = await startApi({ supabaseUrl: supabase.url, supabaseSecretKey: SECRET, rateLimitPerMinute: 10_000 });
});
after(async () => { await api.close(); await supabase.close(); });
beforeEach(() => { supabase.requests.length = 0; supabase.reply = () => ({ status: 201, json: {} }); });

test('MOCKED transcript: inserts one row with the secret key on the apikey header', async () => {
  const r = await postJson(`${api.url}/v1/onboarding/transcript`, {
    installId: INSTALL.toUpperCase(),
    source: 'typed',
    transcript: `  ${TRANSCRIPT}  `,
    answers: [{ question: 'What got you into bouldering?', answer: 'A friend dragged me along.' },
              { question: 'Any hardware projects?', answer: null }],
  });
  assert.equal(r.status, 200);
  assert.deepEqual(r.json, { saved: true });
  assert.equal(supabase.requests.length, 1);
  const req = supabase.requests[0];
  assert.equal(req.path, '/rest/v1/onboarding_transcripts');
  assert.equal(req.headers.apikey, SECRET);
  assert.equal(req.headers.authorization, undefined, 'secret keys are not JWTs');
  assert.deepEqual(req.json, {
    install_id: INSTALL,
    source: 'typed',
    transcript: TRANSCRIPT,
    answers: [{ question: 'What got you into bouldering?', answer: 'A friend dragged me along.' },
              { question: 'Any hardware projects?', answer: null }],
  });
  assert.ok(!r.text.includes(SECRET));
  assert.ok(!api.logs.join('\n').includes('jazz'), 'user text is never logged');
});

test('MOCKED transcript: voice with no answers defaults to an empty list', async () => {
  const r = await postJson(`${api.url}/v1/onboarding/transcript`, { installId: INSTALL, source: 'voice', transcript: TRANSCRIPT });
  assert.equal(r.status, 200);
  assert.deepEqual(supabase.requests[0].json.answers, []);
});

test('MOCKED transcript: bad input is 400 and never reaches Supabase', async () => {
  const good = { installId: INSTALL, source: 'voice', transcript: TRANSCRIPT };
  for (const body of [
    { ...good, installId: 'not-a-uuid' },
    { ...good, source: 'email' },
    { ...good, transcript: '   ' },
    { ...good, transcript: 'x'.repeat(2001) },
    { ...good, answers: [{ question: 'q?', answer: 1 }] },
    { ...good, answers: Array(4).fill({ question: 'q?', answer: 'a' }) },
  ]) {
    const r = await postJson(`${api.url}/v1/onboarding/transcript`, body);
    assert.equal(r.status, 400, JSON.stringify(body).slice(0, 80));
    assert.equal(r.json.error.code, 'bad_request');
  }
  assert.equal(supabase.requests.length, 0);
});

test('MOCKED transcript: a Supabase failure is 502 storage_error without echoing its body', async () => {
  supabase.reply = () => ({ status: 500, json: { message: `boom ${TRANSCRIPT}` } });
  const r = await postJson(`${api.url}/v1/onboarding/transcript`, { installId: INSTALL, source: 'voice', transcript: TRANSCRIPT });
  assert.equal(r.status, 502);
  assert.equal(r.json.error.code, 'storage_error');
  assert.ok(!r.text.includes('boom'));
});

test('MOCKED transcript: without Supabase config → 503 storage_not_configured', async () => {
  const bare = await startApi({ rateLimitPerMinute: 10_000 });
  try {
    const health = await (await fetch(`${bare.url}/healthz`)).json();
    assert.equal(health.storageConfigured, false);
    const r = await postJson(`${bare.url}/v1/onboarding/transcript`, { installId: INSTALL, source: 'voice', transcript: TRANSCRIPT });
    assert.equal(r.status, 503);
    assert.equal(r.json.error.code, 'storage_not_configured');
  } finally {
    await bare.close();
  }
});
