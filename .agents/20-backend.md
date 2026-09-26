# backend/ — `bump-api`

A tiny **zero-dependency** Node.js (>= 20) service that sits between the iOS app
and xAI Grok, and offers a short-poll room relay for phone-to-phone messages.
**The app never sees an xAI key.** The full HTTP contract is
`backend/CONTRACT.md` — that file is authoritative, this one is orientation.

```bash
cd backend && cp .env.example .env   # put the real key in .env, never commit
npm start                            # 0.0.0.0:8787 so a phone on the same Wi-Fi can reach it
curl http://localhost:8787/healthz
```

## Files

| File | Lines | What |
|---|---|---|
| `src/server.js` | 355 | routing, limits, logging, the four endpoints |
| `src/validate.js` | 282 | output checking. The heart of the trust model. |
| `src/prompts.js` | 166 | Grok prompts |
| `src/xai.js` | 117 | xAI HTTP client |
| `src/ratelimit.js` | 49 | per-IP limiting |
| `src/errors.js` | 25 | the error shape |
| `src/relay.js` | | ephemeral room membership, coordinator choice and message forwarding |
| `test/api.test.js` | 511 | mocked end-to-end, runs a fake xAI locally |
| `test/relay.test.js` | | local relay membership and delivery tests |
| `test/validate.test.js` | 117 | |
| `scripts/smoke.js` | | LIVE test against a real server + real xAI |

## Endpoints

| | |
|---|---|
| `GET /healthz` | `{ok, grokConfigured, relay, model, sttModel}`. Never leaks any part of the key. |
| `POST /v1/transcribe` | raw audio body (not multipart), `Content-Type: audio/*`, max **3 MB**. In memory only, forwarded to xAI `/v1/stt`, dropped. Never written to disk, never logged. |
| `POST /v1/profile/draft` | transcript → draft bio, facts, one follow-up question |
| `POST /v1/profile/followup` | follow-up answer → more facts, next question |
| `POST /v1/talking-points` | verified shared/complementary pairs → conversation starters |
| `/v1/relay/poll`, `/send`, `/leave` | ephemeral room transport; see `src/relay.js` and the current `ios/README.md` |

Every success carries `"generator": {"provider": "xai", "model": "<id used>"}`
so the app can label results honestly.

## The trust rule — do not weaken it

**The server never returns mock or fallback content on a success status.**

Everything the model returns is checked server-side: every fact must quote the
user's own words, and questions must end in "?". Anything failing is dropped.
If nothing usable survives, the server returns **502** — it does not substitute
invented content. The app then uses its own local fallback, *labelled as local*.

## Errors

`{ "error": { "code": "...", "message": "..." } }` on every non-2xx.

`400 bad_request` · `413 too_large` · `415 unsupported_media` ·
`422 empty_audio` · `429 rate_limited` (with `Retry-After`) ·
`502 upstream_invalid` · `502 upstream_error` · `503 not_configured` ·
`504 upstream_timeout`

## Config

| var | default | |
|---|---|---|
| `XAI_API_KEY` | none | required; without it Grok endpoints return `503 not_configured` |
| `XAI_MODEL` | `grok-4.3` | |
| `XAI_REASONING_EFFORT` | `none` | model default is `low`; `none` measured ~3× faster for these short tasks |
| `XAI_STT_MODEL` | `grok-voice-transcribe-2.0` | |
| `PORT` / `HOST` | `8787` / `0.0.0.0` | |

A local `.env` is read if present and **never overrides** variables already in
the environment.

## Mac server and quick tunnel for phone tests

The team runs the backend on a Mac and exposes it to the phones through a
Cloudflare quick tunnel. The `trycloudflare.com` URL changes whenever
`cloudflared` restarts. Start these in separate Mac terminals:

```bash
cd backend && npm start
cloudflared tunnel --protocol http2 --url http://localhost:8787
```

Copy the printed `https://<name>.trycloudflare.com` URL. Check
`curl https://<name>.trycloudflare.com/healthz`; the response should include
`"grokConfigured":true` and `"relay":true` when the key is configured.
The xAI key stays in ignored `backend/.env`; never copy it into a build setting
or this folder. See `30-ios.md` for updating both app build configurations or
the per-phone Server URL override. The relay has no authentication, so the
quick tunnel is for a controlled test session.

## Tests

```bash
npm test      # Local tests. Fake xAI server and relay, no real key. 47 tests.
npm run smoke # LIVE. Needs the key. Costs a small amount. BUMP_API_URL to retarget.
```

To include speech-to-text in the smoke test, generate a clip on macOS:
`say -o /tmp/intro.m4a --data-format=aac "..."` then `npm run smoke -- --audio /tmp/intro.m4a`.

## Privacy and security posture

- Audio is **memory only**. One log line per request (method, path, status,
  duration). Bodies, transcripts, answers, labels, headers and the key are
  never logged.
- Grok requests are sent with `store: false`.
- xAI retains API requests/responses up to 30 days by default. **We have not
  verified how long xAI keeps STT audio specifically.** Do not claim otherwise.
- **There is no authentication** beyond per-IP rate limiting (30 req/min
  overall, 6/min for transcription). Fine on a trusted demo network. Do not
  expose publicly without adding auth.
