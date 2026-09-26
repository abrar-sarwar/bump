'use strict';

/**
 * PAIRING ALGORITHM (see README.md for prose + limitations)
 * =========================================================
 *
 * Every bump is stamped with a SERVER-SIDE MONOTONIC time on arrival. Phone
 * clocks are never trusted for matching (they are skewed by seconds and users
 * can change them). Phones only use their own monotonic clock for local
 * cooldowns.
 *
 * Instead of fixed time buckets (which would split a real pair that straddles a
 * boundary), we keep a ROLLING list of pending bumps per room and re-evaluate it
 * on every tick:
 *
 *   1. AGE OUT   bumps older than `timeoutMs` -> "timeout" (never pend forever).
 *   2. BUFFER    a bump is only eligible to be paired once it has waited
 *                `bufferMs`. This is what stops an early greedy match: with
 *                arrivals at 0, 300, 310 ms we do not commit 0+300 at t=300,
 *                we wait and then see that 300+310 is the far better pair.
 *   3. CANDIDATES all ordered pairs of DIFFERENT clients in the SAME room whose
 *                receive times differ by <= the room's `windowMs`, and where at
 *                least one member has matured past the buffer.
 *   4. CLOSEST   sort candidates by gap ascending; take the closest first.
 *   5. AMBIGUITY before committing pair (a,b) with gap g, look for another
 *                candidate pair that shares exactly ONE member with (a,b) and
 *                has gap <= g + `ambiguityMarginMs`. If one exists we genuinely
 *                cannot tell who bumped whom, so we REJECT every bump involved
 *                ("ambiguous") rather than guess.
 *   6. DISJOINT  otherwise commit the pair, remove both bumps, and keep going so
 *                clearly separated simultaneous pairs (0/10 and 250/260) both
 *                match in one pass.
 *
 * A bump is never reused in two pairs and a client is never matched to itself.
 */

const DEFAULTS = {
  // Max server-receive-time difference for two bumps to be considered a pair.
  windowMs: 500,
  // A rival pair within this much of the best pair's gap makes the match
  // ambiguous. Deliberately much smaller than windowMs.
  ambiguityMarginMs: 50,
  // How long a bump waits before it may be committed, so a closer later
  // arrival can still win.
  bufferMs: 250,
  // Hard cap on how long a bump may stay pending before it is timed out.
  timeoutMs: 2500,
  // Server-side per-client cooldown; a second bump inside this is dropped.
  clientCooldownMs: 1000,
  // How long a proposal may sit unconfirmed.
  proposalTimeoutMs: 15000,
};

class Matcher {
  /**
   * @param {object} opts
   * @param {{now: () => number}} opts.clock monotonic ms source (injectable)
   * @param {(clientId: string, event: string, payload: object) => void} opts.emit
   * @param {(roomCode: string, event: string, payload: object) => void} opts.emitRoom
   */
  constructor(opts = {}) {
    this.cfg = { ...DEFAULTS, ...opts.config };
    this.clock = opts.clock || { now: () => Number(process.hrtime.bigint() / 1000000n) };
    this.emit = opts.emit || (() => {});
    this.emitRoom = opts.emitRoom || (() => {});

    /** @type {Map<string, {code: string, windowMs: number, pending: Array, clients: Set<string>}>} */
    this.rooms = new Map();
    /** @type {Map<string, {id: string, roomCode: string, name: string, lastBumpAt: number, proposalId: ?string}>} */
    this.clients = new Map();
    /** @type {Map<string, {id, roomCode, members: Array, confirmed: Set<string>, createdAt: number}>} */
    this.proposals = new Map();

    this._seq = 0;
  }

  _id(prefix) {
    this._seq += 1;
    return `${prefix}_${this._seq}`;
  }

  _room(code) {
    let room = this.rooms.get(code);
    if (!room) {
      room = { code, windowMs: this.cfg.windowMs, pending: [], clients: new Set() };
      this.rooms.set(code, room);
    }
    return room;
  }

  // ---------------------------------------------------------------- lifecycle

  join(clientId, roomCode, name) {
    this.leave(clientId); // a room change clears any pending state first
    const room = this._room(roomCode);
    room.clients.add(clientId);
    this.clients.set(clientId, { id: clientId, roomCode, name, lastBumpAt: -Infinity, proposalId: null });
    return { roomCode, windowMs: room.windowMs, ambiguityMarginMs: this.cfg.ambiguityMarginMs, bufferMs: this.cfg.bufferMs };
  }

  /** Remove a client and everything it owns: pending bumps and live proposals. */
  leave(clientId) {
    const client = this.clients.get(clientId);
    if (!client) return;
    const room = this.rooms.get(client.roomCode);
    if (room) {
      room.clients.delete(clientId);
      room.pending = room.pending.filter((b) => b.clientId !== clientId);
      if (room.clients.size === 0 && room.pending.length === 0) this.rooms.delete(room.code);
    }
    if (client.proposalId) this.cancelProposal(client.proposalId, clientId, 'disconnected');
    this.clients.delete(clientId);
  }

  /** The window is authoritative per room and identical for every participant. */
  setWindow(clientId, windowMs) {
    const client = this.clients.get(clientId);
    if (!client) return;
    const room = this._room(client.roomCode);
    room.windowMs = Math.max(50, Math.min(3000, Math.round(windowMs)));
    // Pending bumps are NOT discarded: they are simply re-evaluated under the
    // new window on the next tick. Widening can therefore rescue a bump that
    // was about to time out; narrowing can strand one until its timeout.
    this.emitRoom(room.code, 'room:config', {
      windowMs: room.windowMs,
      ambiguityMarginMs: this.cfg.ambiguityMarginMs,
      bufferMs: this.cfg.bufferMs,
    });
  }

  // -------------------------------------------------------------------- bumps

  /** A phone reported a motion spike. Timestamped HERE, on arrival. */
  bump(clientId) {
    const now = this.clock.now();
    const client = this.clients.get(clientId);
    if (!client) return { accepted: false, reason: 'not-in-room' };
    if (client.proposalId) return { accepted: false, reason: 'proposal-active' };

    const room = this._room(client.roomCode);
    if (now - client.lastBumpAt < this.cfg.clientCooldownMs) {
      this.emit(clientId, 'bump:rejected', { reason: 'server-cooldown' });
      return { accepted: false, reason: 'server-cooldown' };
    }
    if (room.pending.some((b) => b.clientId === clientId)) {
      this.emit(clientId, 'bump:rejected', { reason: 'duplicate-pending' });
      return { accepted: false, reason: 'duplicate-pending' };
    }

    client.lastBumpAt = now;
    const bump = { id: this._id('bump'), clientId, name: client.name, t: now };
    room.pending.push(bump);
    this.emit(clientId, 'bump:ack', { bumpId: bump.id, serverT: now, windowMs: room.windowMs });
    return { accepted: true, bumpId: bump.id, t: now };
  }

  // ----------------------------------------------------------------- resolver

  /** Drive from a short interval on the server; call directly in tests. */
  resolve() {
    const now = this.clock.now();
    for (const room of [...this.rooms.values()]) {
      this._resolveRoom(room, now);
    }
    this._expireProposals(now);
  }

  _resolveRoom(room, now) {
    // 1. age out
    const stale = room.pending.filter((b) => now - b.t >= this.cfg.timeoutMs);
    if (stale.length) {
      room.pending = room.pending.filter((b) => now - b.t < this.cfg.timeoutMs);
      for (const b of stale) this.emit(b.clientId, 'bump:timeout', { bumpId: b.id });
    }

    // Repeat until no more committable/rejectable pairs remain this tick.
    for (;;) {
      const candidates = this._candidates(room, now);
      if (candidates.length === 0) return;
      const best = candidates[0];

      // 5. ambiguity: a rival pair sharing exactly one member, nearly as close.
      const rivals = candidates.filter((c) => {
        if (c === best) return false;
        const shared = (c.a === best.a ? 1 : 0) + (c.a === best.b ? 1 : 0)
          + (c.b === best.a ? 1 : 0) + (c.b === best.b ? 1 : 0);
        return shared === 1 && c.gap <= best.gap + this.cfg.ambiguityMarginMs;
      });

      if (rivals.length) {
        const involved = new Set([best.a, best.b]);
        for (const r of rivals) { involved.add(r.a); involved.add(r.b); }
        room.pending = room.pending.filter((b) => !involved.has(b));
        for (const b of involved) {
          this.emit(b.clientId, 'bump:ambiguous', {
            bumpId: b.id,
            candidates: involved.size,
            reason: `another bump was within ${this.cfg.ambiguityMarginMs} ms of the best pair`,
          });
        }
        continue;
      }

      // 6. commit, then loop for further disjoint pairs.
      room.pending = room.pending.filter((b) => b !== best.a && b !== best.b);
      this._propose(room, best);
    }
  }

  /** Ordered-by-closeness list of legal pairs. */
  _candidates(room, now) {
    const out = [];
    const list = room.pending;
    for (let i = 0; i < list.length; i += 1) {
      for (let j = i + 1; j < list.length; j += 1) {
        const a = list[i];
        const b = list[j];
        if (a.clientId === b.clientId) continue; // never match a phone to itself
        const gap = Math.abs(a.t - b.t);
        if (gap > room.windowMs) continue;
        // at least one member must have matured past the buffer
        const matured = (now - a.t >= this.cfg.bufferMs) || (now - b.t >= this.cfg.bufferMs);
        if (!matured) continue;
        out.push({ a, b, gap });
      }
    }
    // Stable tie-break on earliest receive time keeps behaviour deterministic.
    out.sort((x, y) => x.gap - y.gap || Math.min(x.a.t, x.b.t) - Math.min(y.a.t, y.b.t));
    return out;
  }

  // ------------------------------------------------------------- confirmation

  _propose(room, pair) {
    const now = this.clock.now();
    const proposal = {
      id: this._id('prop'),
      roomCode: room.code,
      members: [
        { clientId: pair.a.clientId, name: pair.a.name },
        { clientId: pair.b.clientId, name: pair.b.name },
      ],
      confirmed: new Set(),
      createdAt: now,
      gap: pair.gap,
    };
    this.proposals.set(proposal.id, proposal);
    for (const m of proposal.members) {
      const client = this.clients.get(m.clientId);
      // Locking the client stops it entering a second pairing concurrently.
      if (client) client.proposalId = proposal.id;
      const peer = proposal.members.find((x) => x.clientId !== m.clientId);
      this.emit(m.clientId, 'match:proposed', {
        proposalId: proposal.id,
        peerName: peer.name,
        gapMs: pair.gap,
        expiresInMs: this.cfg.proposalTimeoutMs,
      });
    }
    return proposal;
  }

  confirm(clientId, proposalId) {
    const proposal = this.proposals.get(proposalId);
    if (!proposal) return { ok: false, reason: 'unknown-proposal' };
    if (!proposal.members.some((m) => m.clientId === clientId)) return { ok: false, reason: 'not-a-member' };
    const client = this.clients.get(clientId);
    if (!client || client.proposalId !== proposalId) return { ok: false, reason: 'stale-proposal' };

    proposal.confirmed.add(clientId);
    if (proposal.confirmed.size < proposal.members.length) {
      this.emit(clientId, 'match:waiting', { proposalId });
      const peer = proposal.members.find((m) => m.clientId !== clientId);
      this.emit(peer.clientId, 'match:peer-confirmed', { proposalId });
      return { ok: true, complete: false };
    }

    for (const m of proposal.members) {
      const peer = proposal.members.find((x) => x.clientId !== m.clientId);
      this.emit(m.clientId, 'match:confirmed', { proposalId, peerName: peer.name });
      const c = this.clients.get(m.clientId);
      if (c) c.proposalId = null;
    }
    this.proposals.delete(proposalId);
    return { ok: true, complete: true };
  }

  cancelProposal(proposalId, byClientId, reason = 'cancelled') {
    const proposal = this.proposals.get(proposalId);
    if (!proposal) return { ok: false, reason: 'unknown-proposal' };
    this.proposals.delete(proposalId);
    for (const m of proposal.members) {
      const c = this.clients.get(m.clientId);
      if (c && c.proposalId === proposalId) c.proposalId = null;
      if (m.clientId !== byClientId) this.emit(m.clientId, 'match:cancelled', { proposalId, reason });
      else this.emit(m.clientId, 'match:cancelled', { proposalId, reason: 'you-cancelled' });
    }
    return { ok: true };
  }

  _expireProposals(now) {
    for (const proposal of [...this.proposals.values()]) {
      if (now - proposal.createdAt >= this.cfg.proposalTimeoutMs) {
        this.proposals.delete(proposal.id);
        for (const m of proposal.members) {
          const c = this.clients.get(m.clientId);
          if (c && c.proposalId === proposal.id) c.proposalId = null;
          this.emit(m.clientId, 'match:cancelled', { proposalId: proposal.id, reason: 'confirmation-timeout' });
        }
      }
    }
  }
}

module.exports = { Matcher, DEFAULTS };
