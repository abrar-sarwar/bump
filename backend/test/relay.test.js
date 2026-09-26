// Relay: room membership, coordinator choice, forwarding. Local only.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { start } from '../src/server.js';

async function api(relayLimits = {}) {
  const server = await start({ port: 0, host: '127.0.0.1', log: () => {}, relayLimits });
  return { server, url: `http://127.0.0.1:${server.address().port}` };
}

const poll = (url, room, peer, { cursor = 0, mv = -1 } = {}) =>
  fetch(`${url}/v1/relay/poll?room=${room}&peer=${encodeURIComponent(peer)}&name=x&cursor=${cursor}&mv=${mv}`)
    .then(async (r) => ({ status: r.status, json: await r.json() }));

const post = (url, path, body) =>
  fetch(`${url}/v1/relay/${path}`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) })
    .then(async (r) => ({ status: r.status, json: await r.json() }));

test('first member coordinates; messages reach only the room, once, in order', async () => {
  const { server, url } = await api({ pollHoldMs: 300 });
  const a0 = await poll(url, 'nearby', 'A#1');
  assert.equal(a0.json.coordinator, 'A#1');
  const b0 = await poll(url, 'nearby', 'B#2');
  assert.equal(b0.json.members.length, 2);
  assert.equal(b0.json.coordinator, 'A#1');
  await poll(url, 'elsewhere', 'C#3');

  // A waits; B's send wakes it immediately.
  const waiting = poll(url, 'nearby', 'A#1', { mv: b0.json.mv });
  const sent = await post(url, 'send', { room: 'nearby', from: 'B#2', to: ['A#1', 'C#3'], data: 'MQ==' });
  assert.deepEqual(sent.json, { delivered: ['A#1'], missing: ['C#3'] });
  await post(url, 'send', { room: 'nearby', from: 'B#2', to: ['A#1'], data: 'Mg==' });
  const got = await waiting;
  const again = await poll(url, 'nearby', 'A#1', { cursor: got.json.cursor, mv: got.json.mv });
  const all = [...got.json.messages, ...again.json.messages].map((m) => m.data);
  assert.deepEqual(all, ['MQ==', 'Mg=='], 'in order, none lost or repeated');
  server.close();
});

test('the coordinator role moves when the coordinator leaves', async () => {
  const { server, url } = await api({ pollHoldMs: 200 });
  await poll(url, 'r', 'A#1');
  await poll(url, 'r', 'B#2');
  await post(url, 'leave', { room: 'r', peer: 'A#1' });
  const b = await poll(url, 'r', 'B#2');
  assert.equal(b.json.coordinator, 'B#2');
  assert.equal(b.json.members.length, 1);
  server.close();
});

test('a phone that stops polling is dropped', async () => {
  const { server, url } = await api({ pollHoldMs: 100, presenceMs: 150 });
  await poll(url, 'r', 'A#1');
  await poll(url, 'r', 'B#2');
  await new Promise((r) => setTimeout(r, 300));
  const b = await poll(url, 'r', 'B#2');
  assert.deepEqual(b.json.members.map((m) => m.id), ['B#2']);
  server.close();
});

test('a non-member cannot send', async () => {
  const { server, url } = await api();
  const res = await post(url, 'send', { room: 'nearby', from: 'Z#9', to: ['A#1'], data: 'aGk=' });
  assert.equal(res.status, 409);
  server.close();
});

test('a phone holding a long poll is not dropped mid-wait', async () => {
  const { server, url } = await api({ pollHoldMs: 400, presenceMs: 100 });
  const first = await poll(url, 'r', 'A#1');
  const held = poll(url, 'r', 'A#1', { mv: first.json.mv });
  await new Promise((r) => setTimeout(r, 250));
  const b = await poll(url, 'r', 'B#2');
  assert.deepEqual(b.json.members.map((m) => m.id).sort(), ['A#1', 'B#2']);
  await held;
  server.close();
});
