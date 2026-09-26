'use strict';

// One end-to-end pass over the real socket path: two clients join the same
// room, both "bump", and both confirm. This catches wiring mistakes that the
// pure matcher tests cannot see (event names, ack shapes, room scoping).
//
// It starts the real server on an ephemeral port as a child process.

const test = require('node:test');
const assert = require('node:assert');
const { spawn } = require('node:child_process');
const path = require('node:path');
const { io } = require('socket.io-client');

const PORT = 3456;

test('two clients bump, match and confirm over a real socket', async (t) => {
  const server = spawn(process.execPath, [path.join(__dirname, '..', 'server.js')], {
    env: { ...process.env, PORT: String(PORT) },
    stdio: ['ignore', 'pipe', 'inherit'],
  });
  t.after(() => server.kill());
  await new Promise((resolve) => server.stdout.on('data', (d) => String(d).includes('listening') && resolve()));

  const url = `http://127.0.0.1:${PORT}`;
  const a = io(url, { transports: ['websocket'] });
  const b = io(url, { transports: ['websocket'] });
  t.after(() => { a.close(); b.close(); });

  const once = (sock, ev) => new Promise((res) => sock.once(ev, res));
  const join = (sock, name) => new Promise((res) => sock.emit('join', { name, room: 'e2e' }, res));

  await Promise.all([once(a, 'connect'), once(b, 'connect')]);
  const cfgA = await join(a, 'Ada');
  await join(b, 'Bo');
  assert.strictEqual(cfgA.windowMs, 500);

  const proposals = Promise.all([once(a, 'match:proposed'), once(b, 'match:proposed')]);
  a.emit('bump', {});
  setTimeout(() => b.emit('bump', {}), 80);
  const [pa, pb] = await proposals;

  assert.strictEqual(pa.peerName, 'Bo');
  assert.strictEqual(pb.peerName, 'Ada');
  assert.strictEqual(pa.proposalId, pb.proposalId);

  const confirmed = Promise.all([once(a, 'match:confirmed'), once(b, 'match:confirmed')]);
  a.emit('confirm', { proposalId: pa.proposalId });
  await once(a, 'match:waiting');
  b.emit('confirm', { proposalId: pb.proposalId });
  const [ca] = await confirmed;
  assert.strictEqual(ca.peerName, 'Bo');
});
