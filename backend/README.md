# backend (`bump-api`)

**Optional.** The core bump-to-connection journey in `../ios` works entirely
between nearby phones, with no account and no network. This service only adds
opt-in cloud features (voice transcription, Grok profile drafting, Grok talking
points); if it's down or not configured, the app falls back on the phone and
says so. Keep it that way: nothing here should become required.


A tiny, zero-dependency Node.js (>= 20) service that sits between the BUMP iOS
app and xAI Grok. The app never sees an xAI key. It does four things:

- `POST /v1/transcribe`: spoken intro audio → text (xAI speech to text)
- `POST /v1/profile/draft`: transcript → draft bio, facts and one follow-up question
- `POST /v1/profile/followup`: follow-up answer → more facts and the next question
- `POST /v1/talking-points`: verified shared/complementary pairs → conversation starters

The exact HTTP contract (paths, fields, limits, error codes) is in
[CONTRACT.md](./CONTRACT.md). Everything the model returns is checked on the
server: every fact must quote the user's own words, and questions must end in "?".
Anything that fails is dropped. If nothing usable is left, the server returns
`502` and never sends fallback content.

## Run it

```sh
cd backend
cp .env.example .env      # then put your real key in .env (never commit it; .env is git-ignored)
npm start                 # listens on 0.0.0.0:8787 so a phone on the same Wi-Fi can reach it
curl http://localhost:8787/healthz
```

Configuration comes from environment variables. A local `.env` is read if it
exists, and it never overrides variables already set in the environment.

| variable | default | |
|---|---|---|
| `XAI_API_KEY` | none | required for Grok; without it Grok endpoints return `503 not_configured` |
| `XAI_MODEL` | `grok-4.3` | model for draft/followup/talking points |
| `XAI_REASONING_EFFORT` | `none` | `grok-4.3` defaults to `low`; `none` measured ~3× faster for these short tasks. Set empty for a model that doesn't accept `reasoning.effort` |
| `XAI_STT_MODEL` | `grok-voice-transcribe-2.0` | speech-to-text model |
| `PORT` / `HOST` | `8787` / `0.0.0.0` | |

### Picking a model

Set `XAI_MODEL`. The available models are listed at
https://docs.x.ai/developers/models. To see which models your key can actually
use, call `GET /v1/models` (see the REST reference at
https://docs.x.ai/developers/rest-api-reference):

```sh
curl https://api.x.ai/v1/models -H "Authorization: Bearer $XAI_API_KEY"
```

## Tests

```sh
npm test      # MOCKED: runs a fake xAI server locally, no network, no key, free
npm run smoke # LIVE: calls a running bump-api, which calls real xAI (needs the key, costs a tiny amount)
```

`BUMP_API_URL` points the smoke test at another server (default
`http://localhost:8787`). To include speech to text, generate a clip on macOS:

```sh
say -o /tmp/intro.m4a --data-format=aac "Hi, I'm Sam. I play jazz piano and I've been getting into bouldering. I'd love to meet people building hardware."
npm run smoke -- --audio /tmp/intro.m4a
```

## Privacy and security notes

- Audio is held in memory only. bump-api never writes it to disk or logs it.
  The server logs one line per request (method, path, status, duration) and
  never logs bodies, transcripts, answers, labels, headers or the key.
- Grok requests are sent with `store: false`.
- xAI's docs say API requests and responses are retained for up to 30 days by
  default for auditing (https://docs.x.ai/developers/faq/security). We have
  **not** verified how long xAI keeps speech-to-text audio specifically.
- There is **no authentication** beyond per-IP rate limiting (30 requests per minute
  overall, 6 per minute for transcription). For the demo, run it on a trusted network. Don't
  expose it publicly without adding auth.
