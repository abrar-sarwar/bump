'use strict';

// Deterministic tests for the pairing algorithm. No test framework beyond
// node:test / node:assert, which ship with Node itself.
//
// Time is fully injected: `clock.now()` returns whatever we set, so every
// scenario is exact and instant.

const test = require('node:test');
const assert = require('node:assert');
const { Matcher } = require('../matcher');

function harness(config = {}) {
  const clock = { t: 0, now: () => clock.t };
  const events = [];
  const m = new Matcher({
    clock,
    config: { windowMs: 500, ambiguityMarginMs: 50, bufferMs: 250, timeoutMs: 2500, clientCooldownMs: 1000, ...config },
    emit: (clientId, event, payload) => events.push({ clientId, event, payload }),
    emitRoom: () => {},
  });
  return {
    m,
    events,
    at: (t) => { clock.t = t; return clock.t; },
    join: (id, room, name) => m.join(id, room, name || id),
    bump: (id, t) => { clock.t = t; return m.bump(id); },
    resolve: (t) => { clock.t = t; m.resolve(); },
    of: (event) => events.filter((e) => e.event === event),
    names: () => events.map((e) => e.event),
  };
}

test('two isolated bumps 100 ms apart match', () => {
  const h = harness();
  h.join('a', 'r'); h.join('b', 'r');
  h.bump('a', 0); h.bump('b', 100);
  h.resolve(400);
  const proposed = h.of('match:proposed');
  assert.strictEqual(proposed.length, 2);
  assert.strictEqual(proposed[0].payload.gapMs, 100);
});

test('bumps in different rooms never match', () => {
  const h = harness();
  h.join('a', 'r1'); h.join('b', 'r2');
  h.bump('a', 0); h.bump('b', 50);
  h.resolve(400);
  assert.strictEqual(h.of('match:proposed').length, 0);
  h.resolve(3000);
  assert.strictEqual(h.of('bump:timeout').length, 2);
});

test('window boundary: inside matches, outside times out', () => {
  const inside = harness();
  inside.join('a', 'r'); inside.join('b', 'r');
  inside.bump('a', 0); inside.bump('b', 500);
  inside.resolve(800);
  assert.strictEqual(inside.of('match:proposed').length, 2, '500 ms gap is inside a 500 ms window');

  const outside = harness();
  outside.join('a', 'r'); outside.join('b', 'r');
  outside.bump('a', 0); outside.bump('b', 501);
  outside.resolve(800);
  assert.strictEqual(outside.of('match:proposed').length, 0, '501 ms gap is outside');
  outside.resolve(3100);
  assert.strictEqual(outside.of('bump:timeout').length, 2);
});

test('closest pair wins over an early greedy match (0 / 300 / 310)', () => {
  const h = harness();
  h.join('a', 'r'); h.join('b', 'r'); h.join('c', 'r');
  h.bump('a', 0);
  h.resolve(250);                      // 'a' has matured but has nobody yet
  assert.strictEqual(h.of('match:proposed').length, 0);
  h.bump('b', 300);
  h.bump('c', 310);
  h.resolve(560);
  const proposed = h.of('match:proposed');
  assert.strictEqual(proposed.length, 2);
  assert.deepStrictEqual(proposed.map((e) => e.clientId).sort(), ['b', 'c']);
  assert.strictEqual(proposed[0].payload.gapMs, 10);
  h.resolve(2600);
  assert.deepStrictEqual(h.of('bump:timeout').map((e) => e.clientId), ['a']);
});

test('three bumps at 0 / 10 / 20 are ambiguous, not guessed', () => {
  const h = harness();
  ['a', 'b', 'c'].forEach((id) => h.join(id, 'r'));
  h.bump('a', 0); h.bump('b', 10); h.bump('c', 20);
  h.resolve(300);
  assert.strictEqual(h.of('match:proposed').length, 0);
  assert.deepStrictEqual(h.of('bump:ambiguous').map((e) => e.clientId).sort(), ['a', 'b', 'c']);
});

test('two clearly separated pairs (0/10 and 250/260) both match', () => {
  const h = harness();
  ['a', 'b', 'c', 'd'].forEach((id) => h.join(id, 'r'));
  h.bump('a', 0); h.bump('b', 10); h.bump('c', 250); h.bump('d', 260);
  h.resolve(520);
  const proposed = h.of('match:proposed');
  assert.strictEqual(proposed.length, 4, 'two proposals, two members each');
  const pairs = [...new Set(proposed.map((e) => e.payload.proposalId))];
  assert.strictEqual(pairs.length, 2);
  const byProposal = {};
  for (const e of proposed) (byProposal[e.payload.proposalId] ||= []).push(e.clientId);
  const sets = Object.values(byProposal).map((v) => v.sort().join(''));
  assert.deepStrictEqual(sets.sort(), ['ab', 'cd']);
});

test('four nearly simultaneous bumps are all ambiguous', () => {
  const h = harness();
  ['a', 'b', 'c', 'd'].forEach((id) => h.join(id, 'r'));
  h.bump('a', 0); h.bump('b', 5); h.bump('c', 10); h.bump('d', 15);
  h.resolve(300);
  assert.strictEqual(h.of('match:proposed').length, 0);
  assert.deepStrictEqual(h.of('bump:ambiguous').map((e) => e.clientId).sort(), ['a', 'b', 'c', 'd']);
});

test('a pair is not missed just because it straddles a would-be bucket boundary', () => {
  // 490 and 510 ms would land in different 500 ms buckets; rolling windows match.
  const h = harness();
  h.join('a', 'r'); h.join('b', 'r');
  h.bump('a', 490); h.bump('b', 510);
  h.resolve(800);
  assert.strictEqual(h.of('match:proposed').length, 2);
});

test('a phone cannot match itself, and duplicates are suppressed', () => {
  const h = harness();
  h.join('a', 'r');
  assert.strictEqual(h.bump('a', 0).accepted, true);
  assert.strictEqual(h.bump('a', 50).accepted, false, 'server-side cooldown');
  assert.strictEqual(h.bump('a', 1500).accepted, false, 'still pending -> duplicate');
  h.resolve(400);
  assert.strictEqual(h.of('match:proposed').length, 0);
});

test('unmatched bump gets a timeout, once', () => {
  const h = harness();
  h.join('a', 'r');
  h.bump('a', 0);
  h.resolve(2000);
  assert.strictEqual(h.of('bump:timeout').length, 0);
  h.resolve(2500);
  assert.strictEqual(h.of('bump:timeout').length, 1);
  h.resolve(5000);
  assert.strictEqual(h.of('bump:timeout').length, 1, 'not re-emitted');
});

test('confirmation needs both sides and validates the proposal id', () => {
  const h = harness();
  h.join('a', 'r', 'Ada'); h.join('b', 'r', 'Bo');
  h.bump('a', 0); h.bump('b', 60);
  h.resolve(400);
  const pid = h.of('match:proposed')[0].payload.proposalId;
  assert.strictEqual(h.of('match:proposed').find((e) => e.clientId === 'a').payload.peerName, 'Bo');

  assert.strictEqual(h.m.confirm('a', 'prop_bogus').ok, false);
  assert.strictEqual(h.m.confirm('a', pid).complete, false);
  assert.strictEqual(h.of('match:waiting').length, 1);
  assert.strictEqual(h.of('match:confirmed').length, 0);
  assert.strictEqual(h.m.confirm('b', pid).complete, true);
  assert.strictEqual(h.of('match:confirmed').length, 2);
});

test('a client with an open proposal cannot enter another pairing', () => {
  const h = harness();
  ['a', 'b', 'c'].forEach((id) => h.join(id, 'r'));
  h.bump('a', 0); h.bump('b', 60);
  h.resolve(400);
  assert.strictEqual(h.of('match:proposed').length, 2);
  assert.strictEqual(h.bump('a', 2000).reason, 'proposal-active');
});

test('disconnect clears pending bumps and cancels the live proposal', () => {
  const h = harness();
  h.join('a', 'r'); h.join('b', 'r');
  h.bump('a', 0);
  h.m.leave('a');
  h.resolve(3000);
  assert.strictEqual(h.of('bump:timeout').length, 0, 'the pending bump went with the client');

  const h2 = harness();
  h2.join('a', 'r'); h2.join('b', 'r');
  h2.bump('a', 0); h2.bump('b', 60);
  h2.resolve(400);
  h2.m.leave('a');
  assert.strictEqual(h2.of('match:cancelled').length, 2);
  assert.strictEqual(h2.m.proposals.size, 0);
  assert.strictEqual(h2.m.clients.get('b').proposalId, null, 'peer is unlocked and can retry');
});

test('confirmation times out and unlocks both clients', () => {
  const h = harness({ proposalTimeoutMs: 1000 });
  h.join('a', 'r'); h.join('b', 'r');
  h.bump('a', 0); h.bump('b', 60);
  h.resolve(400);
  h.resolve(1500);
  assert.deepStrictEqual(h.of('match:cancelled').map((e) => e.payload.reason), ['confirmation-timeout', 'confirmation-timeout']);
  assert.strictEqual(h.m.clients.get('a').proposalId, null);
});

test('the room window is authoritative and applies to still-pending bumps', () => {
  const h = harness();
  h.join('a', 'r'); h.join('b', 'r');
  h.bump('a', 0); h.bump('b', 700);          // outside the default 500 ms
  h.resolve(950);
  assert.strictEqual(h.of('match:proposed').length, 0);
  h.m.setWindow('a', 900);                    // widened by one participant, for the whole room
  h.resolve(1000);
  assert.strictEqual(h.of('match:proposed').length, 2, 'the pending pair is re-evaluated, not discarded');
});
