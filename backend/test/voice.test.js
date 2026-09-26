// MOCKED tests for spoken onboarding: the voice-session token endpoint and
// spoken corrections. A FAKE xAI answers; no request leaves this machine.

import test, { before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

import { REVISE } from '../src/prompts.js';
import { DUMMY_KEY, postJson, responsesPayload, startApi, startFakeXai } from './helpers.js';

let fake;
let api;

before(async () => {
  fake = await startFakeXai();
  api = await startApi({ baseUrl: fake.url, rateLimitPerMinute: 10_000, voiceRateLimitPerMinute: 10_000 });
});
after(async () => { await api.close(); await fake.close(); });
beforeEach(() => { fake.requests.length = 0; fake.reply = () => ({ status: 500, json: {} }); });

const ITEMS = [
  { id: 'a', kind: 'interest', label: 'Cybersecurity' },
  { id: 'b', kind: 'interest', label: 'Valorant' },
  { id: 'c', kind: 'interest', label: 'House music' },
];

test('MOCKED voice session: returns only a short-lived token, never the key', async () => {
  fake.reply = () => ({ status: 200, json: { value: 'xai-realtime-client-secret-TEMP', expires_at: 1_900_000_000 } });
  const r = await postJson(`${api.url}/v1/voice/session`, {});
  assert.equal(r.status, 200);
  assert.equal(r.json.token, 'xai-realtime-client-secret-TEMP');
  assert.equal(r.json.model, 'grok-voice-latest');
  assert.equal(r.json.voice, 'eve');
  assert.match(r.json.url, /^ws:\/\/127\.0\.0\.1:\d+\/v1\/realtime$/);
  assert.ok(!r.text.includes(DUMMY_KEY), 'the permanent key never reaches the phone');
  // Upstream call: the right endpoint, authenticated with the key, short expiry.
  assert.equal(fake.requests[0].path, '/v1/realtime/client_secrets');
  assert.equal(fake.requests[0].headers.authorization, `Bearer ${DUMMY_KEY}`);
  assert.deepEqual(fake.requests[0].json, { expires_after: { seconds: 300 } });
  assert.ok(!api.logs.join('\n').includes('TEMP'), 'the token is never logged');
});

test('MOCKED voice session: missing key → 503, bad upstream → 502', async () => {
  const noKey = await startApi({ apiKey: null, baseUrl: fake.url });
  try {
    assert.equal((await postJson(`${noKey.url}/v1/voice/session`, {})).json.error.code, 'not_configured');
  } finally { await noKey.close(); }
  fake.reply = () => ({ status: 200, json: { nope: true } });
  assert.equal((await postJson(`${api.url}/v1/voice/session`, {})).json.error.code, 'upstream_invalid');
  fake.reply = () => ({ status: 401, json: {} });
  assert.equal((await postJson(`${api.url}/v1/voice/session`, {})).json.error.code, 'upstream_error');
});

test('MOCKED voice session: has its own rate limit', async () => {
  const tight = await startApi({ baseUrl: fake.url, rateLimitPerMinute: 10_000, voiceRateLimitPerMinute: 1 });
  try {
    fake.reply = () => ({ status: 200, json: { value: 't', expires_at: 1 } });
    assert.equal((await postJson(`${tight.url}/v1/voice/session`, {})).status, 200);
    assert.equal((await postJson(`${tight.url}/v1/voice/session`, {})).status, 429);
  } finally { await tight.close(); }
});

test('MOCKED revise: a spoken correction becomes grounded edits', async () => {
  fake.reply = () => ({ status: 200, json: responsesPayload({
    intent: 'correct',
    remove: ['c', 'zzz'],                                   // unknown id dropped
    rename: [{ id: 'b', label: 'Overwatch' }, { id: 'a', label: 'Hacking' }], // "Hacking" not said → dropped
    add: [{ kind: 'interest', label: 'Techno', source: 'I like techno' }, { kind: 'interest', label: 'Jazz', source: 'jazz' }],
  }) });
  const r = await postJson(`${api.url}/v1/profile/revise`, { items: ITEMS, utterance: 'Change Valorant to Overwatch, drop house music, I like techno' });
  assert.equal(r.status, 200);
  assert.equal(r.json.intent, 'correct');
  assert.deepEqual(r.json.remove, ['c']);
  assert.deepEqual(r.json.rename, [{ id: 'b', label: 'Overwatch' }]);
  assert.deepEqual(r.json.add.map((f) => f.label), ['Techno']);
  // The card and the words went to the model only as data.
  const sent = fake.requests[0].json;
  assert.equal(sent.instructions, REVISE.instructions);
  assert.match(sent.input[0].content, /<user_data>/);
});

test('MOCKED revise: confirm, and a "correction" with nothing usable becomes unclear', async () => {
  fake.reply = () => ({ status: 200, json: responsesPayload({ intent: 'confirm', remove: [], rename: [], add: [] }) });
  assert.equal((await postJson(`${api.url}/v1/profile/revise`, { items: ITEMS, utterance: 'yep that is right' })).json.intent, 'confirm');
  fake.reply = () => ({ status: 200, json: responsesPayload({ intent: 'correct', remove: ['nope'], rename: [], add: [] }) });
  assert.equal((await postJson(`${api.url}/v1/profile/revise`, { items: ITEMS, utterance: 'hmm' })).json.intent, 'unclear');
});

test('MOCKED revise: input limits', async () => {
  assert.equal((await postJson(`${api.url}/v1/profile/revise`, { items: ITEMS, utterance: '' })).status, 400);
  assert.equal((await postJson(`${api.url}/v1/profile/revise`, { items: ITEMS, utterance: 'x'.repeat(501) })).status, 400);
  assert.equal((await postJson(`${api.url}/v1/profile/revise`, { items: [{ id: 'a', kind: 'hobby', label: 'x' }], utterance: 'hi' })).status, 400);
});
