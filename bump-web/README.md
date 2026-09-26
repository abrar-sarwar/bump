# Experiment 1 — Web bump pairing (motion + Socket.io)

**Question this answers:** can two phones that physically bump be paired reliably
using nothing but a devicemotion spike and the *server's* receive time, in a room
where other people are bumping too?

This is a throwaway spike. No accounts, no database, no AI, no styling budget.
All state is in memory in one process.

---

## Files

| File | Purpose |
|---|---|
| `matcher.js` | The pairing algorithm. Pure, no I/O, injectable clock — this is the part under test. |
| `server.js` | HTTP static file serving + Socket.io wiring + a 25 ms resolver tick. |
| `public/index.html` | The whole client: markup, CSS, motion processing, UI. Vanilla JS. |
| `test/matcher.test.js` | 15 deterministic algorithm tests with injected timestamps. |
| `test/server.e2e.test.js` | One end-to-end pass over the real socket (join → bump → match → confirm). |
| `render.yaml` | Render Blueprint, if you deploy there. |

---

## Local development

Prerequisites: **Node.js 20 or newer** (developed and tested on Node 25). No
global tools needed.

```bash
cd bump-web
npm install          # project-local only
npm test             # 16 tests, ~0.5 s
npm start            # http://localhost:3000
```

Environment variables:

| Var | Default | Meaning |
|---|---|---|
| `PORT` | `3000` | Listen port. Read from the environment so PaaS hosts work unchanged. |
| `HOST` | `0.0.0.0` | Bind address. Must stay `0.0.0.0` for phones on your LAN and for Render. |
| `TICK_MS` | `25` | Resolver interval. Lower = snappier matching, more CPU. |

### Getting two phones onto it

1. Start the server and expose it over **HTTPS** (see below — plain `http://<lan-ip>:3000`
   will *not* work on a phone).
2. Open the HTTPS URL on each phone.
3. Type a display name on each, and **the same room code** on both (default `test1`).
4. Tap **Ready to bump** on each and accept the motion prompt.
5. Bump the phones together. Each phone shows the other's name and a Confirm button.

### Why HTTPS is mandatory on real phones

`devicemotion` is a powerful-feature API gated on a **secure context**. Safari on
iOS will not even expose `DeviceMotionEvent.requestPermission()` outside HTTPS,
and Chrome on Android suppresses sensor events the same way. `localhost` counts as
secure, but `http://192.168.x.x:3000` does not — so a phone pointed at your laptop's
LAN address gets a dead page. The page detects this and says so in the debug log.
Refs: [MDN: DeviceMotionEvent.requestPermission](https://developer.mozilla.org/en-US/docs/Web/API/DeviceMotionEvent/requestPermission_static),
[MDN: Secure contexts / features restricted to them](https://developer.mozilla.org/en-US/docs/Web/Security/Secure_Contexts/features_restricted_to_secure_contexts).

---

## The matching algorithm, precisely

Every bump is stamped **on arrival at the server** with a server-side monotonic
clock. Phone clocks are never used for matching — they are skewed by seconds and
the user can change them. Phones use their own `performance.now()` only for the
local 1.5 s cooldown.

State per room: a rolling list of pending bumps plus the room's authoritative
window. There are **no fixed time buckets**; a bucketed scheme would split a real
pair whose timestamps straddle a boundary (covered by a test at 490 ms / 510 ms).

The resolver runs every 25 ms and, per room:

1. **Age out.** Any bump older than `timeoutMs` (**2500 ms**) is dropped and its
   phone gets `bump:timeout`. Nothing pends forever, however busy the room is.
2. **Buffer.** A bump only becomes eligible to be committed after `bufferMs`
   (**250 ms**). This is what prevents an early greedy pairing: with arrivals at
   0, 300 and 310 ms we do *not* commit 0+300 at t=300; we wait, then see that
   300+310 is far closer and pair those instead.
3. **Candidates.** All pairs of *different* clients in the *same* room whose
   receive times differ by at most the room's `windowMs` (**500 ms**), where at
   least one member has matured past the buffer.
4. **Closest first.** Sort candidates by gap ascending (ties broken by earliest
   receive time, so behaviour is deterministic).
5. **Ambiguity check.** Before committing the best pair `(a,b)` with gap `g`, look
   for another candidate pair that shares **exactly one** member with `(a,b)` and
   has gap `<= g + ambiguityMarginMs` (**50 ms**). If one exists, we genuinely
   cannot tell who bumped whom, so every bump involved is **rejected** with
   `bump:ambiguous`. We never pick arbitrarily. The margin is deliberately an
   order of magnitude smaller than the window: the window says "could these be the
   same bump?", the margin says "is there a rival explanation that is just as good?".
6. **Disjoint pairs.** Otherwise commit the pair, remove both bumps, and loop, so
   two clearly separated simultaneous pairs (0/10 ms and 250/260 ms) both match in
   one pass.

A bump is never reused in two pairs; a client is never matched to itself. Per-client
guards: a **1000 ms** server-side cooldown, rejection of a second bump while one is
still pending, and rejection of any bump while a proposal is open.

All four numbers live in `DEFAULTS` at the top of `matcher.js`.

### Confirmation

On a committed pair the server issues a **proposal ID** and sends each phone the
*other* participant's entered name. Both must press Confirm; confirmations are
validated against the proposal ID and membership, so a stale or forged ID is
rejected. After one side confirms it sees "waiting for the other person"; success
shows only when both have. Either side can cancel, and the proposal expires after
**15 s**. Both clients are locked out of new pairings while it is open. Names are
rendered with `textContent`, never HTML.

### Window changes

The window is **per room and server-authoritative**. When any participant moves
the slider the server clamps it (50–3000 ms), stores it on the room, and broadcasts
`room:config` so everyone displays the same number. Bumps already pending are
**not** discarded — they are simply re-evaluated under the new value on the next
tick. Widening can therefore rescue a bump that was about to time out; narrowing
can strand one until its timeout fires.

### Known limitations — this is what the experiment measures

- **Receive-time proximity is not identity.** If two separate pairs bump within
  tens of milliseconds of each other, arrival order alone cannot say who bumped
  whom. The algorithm's honest answer is to reject the lot as ambiguous, so in a
  dense room we expect a *rejection* rate, not wrong matches. Rejections are a
  cost, not a success — report them separately (see `/RESULTS.md`).
- **Network delay can reorder arrivals.** Phone A's bump can reach the server
  after phone B's even though A moved first. On congested conference Wi-Fi jitter
  of 100 ms+ is normal, which is a large fraction of a 500 ms window.
- **Motion is not contact.** A hard table tap, a pocket jolt, or running can all
  clear the threshold. False positives are measured explicitly in the checklist.
- **Foreground only.** Backgrounding the tab or locking the phone stops
  `devicemotion` and usually drops the socket. Keep the page open and awake.
- **One instance only.** All state is in memory, so two server instances would be
  two unconnected experiments.

### Motion processing

`acceleration` (gravity already excluded) is used when the browser provides it.
Where only `accelerationIncludingGravity` exists we run a one-pole high-pass:

```
gravity = 0.9 * gravity + 0.1 * sample      // slow estimate of the gravity vector
linear  = sample - gravity
```

At ~60 Hz that is roughly a 25 ms time constant — it tracks slowly changing
gravity while letting a sharp bump through. The magnitude is
`sqrt(x²+y²+z²)` in **m/s²**, and the *same* processed value drives both the live
display and the threshold comparison. The debug panel names which source is in use.

Threshold starts at **12 m/s²** with a 4–40 m/s² slider. That is a starting guess,
not a result: iOS and Android report different sample rates and scaling, so expect
per-device tuning. Firing uses crossing + rearm (rearm below 0.6× threshold) plus a
1.5 s cooldown, so one bump sends one event and sustained shaking does not spam.

---

## Hosted HTTPS (recommended for a crowded-room test)

**Render's free tier is verified to work for this** as of September 2026: free web
services run a persistent Node process, support WebSockets, and give you HTTPS on a
`*.onrender.com` hostname. The limits that matter:

- Free services **spin down after ~15 minutes of inactivity**; the next request
  takes roughly a minute to wake them, and **open WebSockets are dropped** when
  they sleep. Open the URL a minute before testing and keep it busy.
- **750 free instance hours per workspace per month**; exhausting them suspends
  free services until the next month.
- A restart wipes all in-memory rooms. Nobody is "in a room" across a cold start.

Sources: [Render free tier article](https://render.com/articles/platforms-with-a-real-free-tier-for-developers-in-2026),
[Render docs — free instance types](https://render.com/docs/free).
Re-check these before your test day; free tiers change. **Railway is not free** —
it runs on a trial credit and then bills, so do not reach for it as a free option.

Deploy path (Blueprint, using the committed `render.yaml`):

1. Push this repo to GitHub.
2. Render dashboard → **New** → **Blueprint** → pick the repo. Render reads
   `render.yaml` (root dir `bump-web`, build `npm ci --omit=dev`, start `node server.js`,
   health check `/healthz`).
3. Deploy, then open `https://<service>.onrender.com` on every phone.

Or without the Blueprint: **New → Web Service**, root directory `bump-web`, build
command `npm ci --omit=dev`, start command `node server.js`, instance type Free.

The server already binds `0.0.0.0` and reads `process.env.PORT`, which is what
Render requires.

**Static hosting (GitHub Pages, Netlify, `vercel --prod` with no function) cannot
run this.** The pairing state is a long-lived in-process object and matching depends
on a persistent bidirectional WebSocket. A static host serves files only; there is
no process to hold the rooms and no socket to push `match:proposed` to a phone.

> Deploying is not something I can do for you without asking — see the approval
> note at the end.

## Alternative: HTTPS tunnel from your laptop

Faster to set up, but it depends on your laptop staying awake and on the venue's
network. Pick one.

**cloudflared** (no account needed for a quick tunnel):

```bash
brew install cloudflared                    # NEEDS APPROVAL: global/system install
cd bump-web && npm start                    # terminal 1
cloudflared tunnel --url http://localhost:3000   # terminal 2
```

It prints a `https://<random>.trycloudflare.com` URL. Quick tunnels are anonymous,
rate-limited and not for production — fine for a spike.
Ref: [Cloudflare quick tunnels](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/do-more-with-tunnels/trycloudflare/).

**ngrok** (requires a free account and one-time auth):

```bash
brew install ngrok                          # NEEDS APPROVAL: global/system install
ngrok config add-authtoken <token>          # from dashboard.ngrok.com
ngrok http 3000
```

Ref: [ngrok getting started](https://ngrok.com/docs/getting-started/).

Either way: everyone opens the printed **https://** URL, types a name, types the
**same room code**, taps Ready, and bumps. Tunnels add a hop, so expect more
arrival-time jitter than a hosted deploy — note which method you used in
`/RESULTS.md`, because it affects the numbers.

---

## Physical-device checklist

Fill in `/RESULTS.md` as you go. Record for every run: device model, OS version,
browser version, threshold, pairing window, deployment method (hosted / tunnel /
localhost), and network (venue Wi-Fi / hotspot / cellular).

**Devices:** at least two iPhones and two Android phones.

| # | Test | What to record |
|---|---|---|
| 1 | iPhone ↔ iPhone | detections / misses out of 20 intentional bumps |
| 2 | Android ↔ Android | same |
| 3 | iPhone ↔ Android (mixed) | same; also whether one side needs a different threshold |
| 4 | Gentle bumps (barely touching) | miss rate — is the threshold too high? |
| 5 | Harder bumps | does it over-trigger or re-trigger? |
| 6 | Walk 2 min, no intentional bumps | false triggers per device-minute |
| 7 | Run/jog 1 min, no intentional bumps | false triggers per device-minute |
| 8 | Two pairs bumping simultaneously, same room | correct / wrong / ambiguous-rejected |
| 9 | Two pairs in **separate** rooms | must be zero cross-room matches |
| 10 | Three or more near-simultaneous bumps | expect `ambiguous`; count them |
| 11 | Bump with no partner present | should end in a clean `timeout` message |
| 12 | Deny the motion permission | clear explanation, no silent failure |
| 13 | Kill Wi-Fi mid-proposal, reconnect | proposal cancelled, retry works |
| 14 | Confirm on one phone only, then wait | "waiting…" then confirmation timeout |
| 15 | Cancel and retry immediately | both phones unlock and can bump again |

Read the debug panel while testing — the event log distinguishes *no spike* from
*spike suppressed by cooldown* from *bump sent but timed out* from *ambiguous*,
which is exactly the difference between a sensor problem and a matching problem.
