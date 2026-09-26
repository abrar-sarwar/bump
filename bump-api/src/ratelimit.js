// In-memory fixed-window rate limiter, keyed by client IP.
//
// Each key gets `limit` hits per `windowMs`. Memory stays bounded: stale
// windows are swept regularly, and if there are still too many keys the
// oldest are evicted (a Map iterates in insertion order).

export function createRateLimiter({ limit, windowMs = 60_000, maxKeys = 10_000 }) {
  const windows = new Map(); // key → { start, count }
  let hitsSinceSweep = 0;

  function sweep(now) {
    for (const [key, w] of windows) {
      if (now - w.start >= windowMs) windows.delete(key);
    }
    while (windows.size > maxKeys) {
      windows.delete(windows.keys().next().value);
    }
  }

  return {
    /** Record one hit. Returns { ok: true } or { ok: false, retryAfter: seconds }. */
    hit(key, now = Date.now()) {
      if (++hitsSinceSweep >= 1000 || windows.size >= maxKeys) {
        hitsSinceSweep = 0;
        sweep(now);
      }

      let w = windows.get(key);
      if (!w || now - w.start >= windowMs) {
        windows.delete(key); // re-insert so insertion order ≈ age
        w = { start: now, count: 0 };
        windows.set(key, w);
      }
      if (w.count >= limit) {
        return { ok: false, retryAfter: Math.max(1, Math.ceil((w.start + windowMs - now) / 1000)) };
      }
      w.count += 1;
      return { ok: true };
    },
    /** True if `key` has room for one more hit right now. Does not count. */
    allows(key, now = Date.now()) {
      const w = windows.get(key);
      return !w || now - w.start >= windowMs || w.count < limit;
    },
    get size() {
      return windows.size;
    },
  };
}
