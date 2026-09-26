// MOCKED test helpers. Nothing here talks to xAI: a fake xAI server runs on
// an ephemeral local port and the real bump-api points at it via `baseUrl`.

import http from 'node:http';
import { start } from '../src/server.js';

export const DUMMY_KEY = 'xai-DUMMY-test-key-0000';

/**
 * Fake xAI. Set `fake.reply = (req) => ({ status, json })` or
 * `fake.reply = 'hang'` per test. Every request is recorded in `fake.requests`
 * as { path, headers, raw (Buffer), json (parsed if JSON) }.
 */
export async function startFakeXai() {
  const fake = { requests: [], reply: () => ({ status: 500, json: {} }) };
  const server = http.createServer((req, res) => {
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => {
      const raw = Buffer.concat(chunks);
      let json = null;
      if (String(req.headers['content-type']).startsWith('application/json')) {
        json = JSON.parse(raw.toString('utf8'));
      }
      const record = { path: req.url, headers: req.headers, raw, json };
      fake.requests.push(record);

      const reply = typeof fake.reply === 'function' ? fake.reply(record) : fake.reply;
      if (reply === 'hang') return; // never answer
      if (typeof reply.body === 'string') {
        res.writeHead(reply.status ?? 200, { 'content-type': 'application/json' });
        res.end(reply.body);
        return;
      }
      res.writeHead(reply.status ?? 200, { 'content-type': 'application/json' });
      res.end(JSON.stringify(reply.json ?? {}));
    });
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  fake.url = `http://127.0.0.1:${server.address().port}`;
  fake.close = () =>
    new Promise((r) => {
      server.closeAllConnections();
      server.close(r);
    });
  return fake;
}

/** A Responses API payload whose output_text is JSON.stringify(obj). */
export function responsesPayload(obj, model = 'grok-4.3-fake') {
  return {
    id: 'resp_fake',
    object: 'response',
    model,
    output: [
      { type: 'reasoning', summary: [] },
      {
        type: 'message',
        role: 'assistant',
        content: [{ type: 'output_text', text: typeof obj === 'string' ? obj : JSON.stringify(obj) }],
      },
    ],
  };
}

/** Start the real bump-api on an ephemeral port. Returns { url, server, logs, close }. */
export async function startApi(overrides = {}) {
  const logs = [];
  const server = await start({
    apiKey: DUMMY_KEY,
    port: 0,
    host: '127.0.0.1',
    llmTimeoutMs: 300,
    sttTimeoutMs: 300,
    log: (line) => logs.push(line),
    ...overrides,
  });
  return {
    server,
    logs,
    url: `http://127.0.0.1:${server.address().port}`,
    close: () =>
      new Promise((r) => {
        server.closeAllConnections();
        server.close(r);
      }),
  };
}

export async function postJson(url, body) {
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: typeof body === 'string' ? body : JSON.stringify(body),
  });
  const text = await res.text();
  return { status: res.status, headers: res.headers, text, json: text ? JSON.parse(text) : null };
}

/** Tiny multipart parser: returns [{ name, filename, contentType, data }] in order. */
export function parseMultipart(raw, contentType) {
  const boundary = /boundary=(?:"([^"]+)"|([^;]+))/.exec(contentType);
  const delim = Buffer.from(`--${boundary[1] ?? boundary[2]}`);
  const parts = [];
  let pos = raw.indexOf(delim);
  while (pos !== -1) {
    const start = pos + delim.length;
    if (raw.slice(start, start + 2).toString() === '--') break; // closing delimiter
    const next = raw.indexOf(delim, start);
    const chunk = raw.slice(start + 2, next - 2); // skip CRLF after delim, before next
    const headerEnd = chunk.indexOf('\r\n\r\n');
    const head = chunk.slice(0, headerEnd).toString();
    const data = chunk.slice(headerEnd + 4);
    parts.push({
      name: /name="([^"]*)"/.exec(head)?.[1],
      filename: /filename="([^"]*)"/.exec(head)?.[1],
      contentType: /content-type:\s*([^\r\n]+)/i.exec(head)?.[1],
      data,
    });
    pos = next;
  }
  return parts;
}
