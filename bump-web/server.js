'use strict';

/**
 * Minimal Socket.io server for the bump feasibility spike.
 * All state is in memory: restart the process and every room is gone. That is
 * fine for a spike, and it is why this must run as ONE instance (see README).
 */

const http = require('http');
const path = require('path');
const fs = require('fs');
const { Server } = require('socket.io');
const { Matcher, DEFAULTS } = require('./matcher');

const PORT = Number(process.env.PORT) || 3000;
// 0.0.0.0 so phones on the LAN (and PaaS health checks) can reach us.
const HOST = process.env.HOST || '0.0.0.0';
const TICK_MS = Number(process.env.TICK_MS) || 25;

const PUBLIC_DIR = path.join(__dirname, 'public');
const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css' };

const server = http.createServer((req, res) => {
  const url = (req.url || '/').split('?')[0];
  if (url === '/healthz') {
    res.writeHead(200, { 'content-type': 'text/plain' });
    res.end('ok');
    return;
  }
  const rel = url === '/' ? 'index.html' : url.replace(/^\/+/, '');
  const file = path.join(PUBLIC_DIR, rel);
  if (!file.startsWith(PUBLIC_DIR) || !fs.existsSync(file) || !fs.statSync(file).isFile()) {
    res.writeHead(404).end('not found');
    return;
  }
  res.writeHead(200, { 'content-type': MIME[path.extname(file)] || 'application/octet-stream' });
  fs.createReadStream(file).pipe(res);
});

const io = new Server(server);

const matcher = new Matcher({
  emit: (clientId, event, payload) => io.to(clientId).emit(event, payload),
  emitRoom: (roomCode, event, payload) => io.to(`room:${roomCode}`).emit(event, payload),
});

// One rolling resolver for every room. Cheap: it only walks pending bumps.
setInterval(() => matcher.resolve(), TICK_MS);

const clean = (s, max) => String(s == null ? '' : s).replace(/[\u0000-\u001f]/g, '').trim().slice(0, max);

io.on('connection', (socket) => {
  socket.on('join', (payload = {}, ack) => {
    const name = clean(payload.name, 40) || 'anon';
    const roomCode = clean(payload.room, 24).toLowerCase() || 'lobby';
    for (const r of socket.rooms) if (r.startsWith('room:')) socket.leave(r);
    socket.join(`room:${roomCode}`);
    const cfg = matcher.join(socket.id, roomCode, name);
    if (typeof ack === 'function') ack({ ok: true, ...cfg, clientId: socket.id });
  });

  socket.on('config', (payload = {}) => {
    if (typeof payload.windowMs === 'number') matcher.setWindow(socket.id, payload.windowMs);
  });

  socket.on('bump', (_payload, ack) => {
    const result = matcher.bump(socket.id);
    if (typeof ack === 'function') ack(result);
  });

  socket.on('confirm', (payload = {}, ack) => {
    const result = matcher.confirm(socket.id, clean(payload.proposalId, 64));
    if (typeof ack === 'function') ack(result);
  });

  socket.on('cancel', (payload = {}) => {
    matcher.cancelProposal(clean(payload.proposalId, 64), socket.id, 'peer-cancelled');
  });

  socket.on('disconnect', () => matcher.leave(socket.id));
});

server.listen(PORT, HOST, () => {
  console.log(`bump-web listening on http://${HOST}:${PORT}`);
  console.log(`defaults: window=${DEFAULTS.windowMs}ms ambiguity=${DEFAULTS.ambiguityMarginMs}ms buffer=${DEFAULTS.bufferMs}ms timeout=${DEFAULTS.timeoutMs}ms`);
});
