// Room relay: lets phones in the same room reach each other through this
// server instead of Multipeer. The server does NOT match bumps or read
// messages. It keeps a member list per room, names one member coordinator
// (the earliest still present), and forwards opaque BUMP wire frames.
//
// Long-polling rather than a held-open stream, because proxies such as
// Cloudflare tunnels buffer streamed responses.
//
//   GET  /v1/relay/poll?room=R&peer=P&name=N&cursor=C&mv=V
//        Joins (or refreshes) P in R, then answers as soon as there is a
//        message after cursor C or the member list has changed from version V,
//        or after `pollHoldMs` with nothing new:
//        {"members":[{"id","name"}],"coordinator":"id","mv":V,
//         "messages":[{"seq","from","data"}],"cursor":C}
//   POST /v1/relay/send   {"room","from","to":["id"],"data":"<base64>"}
//        -> {"delivered":["id"],"missing":["id"]}
//   POST /v1/relay/leave  {"room","peer"}
//
// A member that has not polled for `presenceMs` is dropped.
// No accounts: anyone who can reach this server can join a room. Fine for a
// test server; not for a public deployment.

export const RELAY_LIMITS = {
  frameBytes: 96 * 1024, // base64 of the app's 64 KB Wire.maxFrame, plus slack
  membersPerRoom: 8, // matches the app's MCSession cap
  queuePerMember: 200,
  pollHoldMs: 20_000,
  presenceMs: 8_000, // longer than the gap between a reply and the next poll
};

const ID = /^[\p{L}\p{N} ._#'-]{1,64}$/u;

export function createRelay({ log = () => {}, limits = {} } = {}) {
  const L = { ...RELAY_LIMITS, ...limits };
  /** room -> { version, members: Map(peer -> Member) } */
  const rooms = new Map();
  let joinCounter = 0;

  function roomOf(name) {
    let r = rooms.get(name);
    if (!r) rooms.set(name, (r = { version: 0, members: new Map() }));
    return r;
  }

  function snapshot(r) {
    const list = [...r.members.entries()].sort((a, b) => a[1].joinedAt - b[1].joinedAt);
    return {
      members: list.map(([id, m]) => ({ id, name: m.name })),
      coordinator: list[0]?.[0] ?? null,
      mv: r.version,
    };
  }

  function membershipChanged(name, r) {
    r.version += 1;
    for (const m of r.members.values()) wake(m);
    if (r.members.size === 0) rooms.delete(name);
  }

  function wake(m) {
    const waiter = m.waiter;
    m.waiter = null;
    waiter?.();
  }

  function remove(name, peer, why) {
    const r = rooms.get(name);
    const m = r?.members.get(peer);
    if (!m) return;
    wake(m);
    clearTimeout(m.presence);
    r.members.delete(peer);
    log(`relay leave room=${name} members=${r.members.size} (${why})`);
    membershipChanged(name, r);
  }

  function touch(name, peer, m) {
    clearTimeout(m.presence);
    m.presence = setTimeout(() => remove(name, peer, 'timeout'), L.presenceMs);
    m.presence.unref?.();
  }

  /** Resolves with the poll reply. Throws a string code on bad input. */
  async function poll(query, signal) {
    const name = String(query.get('room') ?? '').trim().toLowerCase();
    const peer = String(query.get('peer') ?? '');
    if (!ID.test(name) || !ID.test(peer)) throw 'bad_request';
    const cursor = Number(query.get('cursor') ?? 0) || 0;
    const mv = Number(query.get('mv') ?? -1);

    const r = roomOf(name);
    let m = r.members.get(peer);
    if (!m) {
      if (r.members.size >= L.membersPerRoom) throw 'room_full';
      m = { name: String(query.get('name') ?? '').slice(0, 40), joinedAt: ++joinCounter,
            queue: [], seq: 0, waiter: null, presence: null, polling: 0 };
      r.members.set(peer, m);
      log(`relay join room=${name} members=${r.members.size}`);
      membershipChanged(name, r);
    }
    // Everything up to the cursor has been received; forget it.
    m.queue = m.queue.filter((x) => x.seq > cursor);
    // A newer poll from the same phone supersedes an older one.
    wake(m);
    m.polling += 1;
    clearTimeout(m.presence); // never drop a phone while it is waiting

    const ready = () => m.queue.length > 0 || r.version !== mv;
    if (!ready()) {
      await new Promise((resolve) => {
        const timer = setTimeout(resolve, L.pollHoldMs);
        timer.unref?.();
        m.waiter = () => { clearTimeout(timer); resolve(); };
        signal?.addEventListener('abort', () => m.waiter?.(), { once: true });
      });
    }
    m.polling -= 1;
    // Presence is measured from the END of a poll, so a phone holding a poll
    // open is never dropped mid-wait.
    // A superseded older poll must not arm the timer under a newer one.
    if (r.members.get(peer) === m && m.polling === 0) touch(name, peer, m);
    const messages = m.queue.slice();
    return { ...snapshot(r), messages, cursor: messages.at(-1)?.seq ?? cursor };
  }

  /** Forward a frame. Throws a string code on invalid input. */
  function send(body) {
    const name = String(body?.room ?? '').trim().toLowerCase();
    const from = String(body?.from ?? '');
    const data = body?.data;
    const to = Array.isArray(body?.to) ? body.to.map(String) : null;
    if (!ID.test(name) || !ID.test(from) || !to || typeof data !== 'string') throw 'bad_request';
    if (data.length > L.frameBytes) throw 'too_large';
    const r = rooms.get(name);
    if (!r?.members.has(from)) throw 'not_a_member';

    const delivered = [];
    const missing = [];
    for (const id of to) {
      const m = id !== from ? r.members.get(id) : null;
      if (!m) {
        missing.push(id);
        continue;
      }
      m.seq += 1;
      m.queue.push({ seq: m.seq, from, data });
      if (m.queue.length > L.queuePerMember) m.queue.shift();
      wake(m);
      delivered.push(id);
    }
    return { delivered, missing };
  }

  function leave(body) {
    const name = String(body?.room ?? '').trim().toLowerCase();
    const peer = String(body?.peer ?? '');
    if (!ID.test(name) || !ID.test(peer)) throw 'bad_request';
    remove(name, peer, 'left');
    return { ok: true };
  }

  return { poll, send, leave, rooms };
}
