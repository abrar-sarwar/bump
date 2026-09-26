# bump-api contract

The iOS app talks only to this service. This service talks to xAI. The app never
sees an xAI key.

All JSON bodies are UTF-8. Every successful response carries
`"generator": {"provider": "xai", "model": "<model id actually used>"}` so the
app can label results accurately. **The server never returns mock or fallback
content on a success status** — if Grok fails, the request fails, and the app
uses its own local fallback, labelled as such.

## Errors

Every non-2xx response has this shape:

```json
{ "error": { "code": "<code>", "message": "<human text, safe to show>" } }
```

| status | code | when |
|---|---|---|
| 400 | `bad_request` | malformed JSON, wrong types, missing fields |
| 413 | `too_large` | body over the endpoint limit |
| 415 | `unsupported_media` | transcribe body is not an audio content type |
| 422 | `empty_audio` | transcription produced no words |
| 429 | `rate_limited` | per-client limit hit (`Retry-After` header set) |
| 502 | `upstream_invalid` | xAI answered but the output failed validation |
| 502 | `upstream_error` | xAI returned a non-2xx |
| 503 | `not_configured` | `XAI_API_KEY` is not set |
| 504 | `upstream_timeout` | xAI did not answer within the server timeout |

## `GET /healthz`

```json
{ "ok": true, "grokConfigured": true, "model": "grok-4.3", "sttModel": "grok-voice-transcribe-2.0" }
```

Never includes the key or any part of it.

## `POST /v1/transcribe`

Raw audio body (not multipart). `Content-Type` must start with `audio/`
(the app sends `audio/mp4` for `.m4a`). Max **3 MB**. Held in memory only,
forwarded to xAI `/v1/stt`, then dropped — never written to disk, never logged.

```json
{ "transcript": "string", "durationSeconds": 12.4, "generator": { ... } }
```

Empty or whitespace transcript → `422 empty_audio`.

## `POST /v1/profile/draft`

Max body 16 KB.

```json
{
  "transcript": "string, 1..2000 chars (user-corrected)",
  "catalogLabels": ["Music", "Coffee", "Espresso", "..."]   // ≤ 150 items, each ≤ 40 chars
}
```

Response:

```json
{
  "bio": { "text": "string ≤ 200 chars, first person", "sources": ["exact excerpt", "..."] } | null,
  "facts": [
    { "kind": "interest" | "experience" | "goal",
      "label": "string 1..60",
      "source": "exact excerpt of the transcript, 1..200" }
  ],                                  // ≤ 12
  "question": "string ≤ 160 ending in ?" | null,
  "generator": { ... }
}
```

## `POST /v1/profile/followup`

Max body 16 KB.

```json
{
  "known": [ { "kind": "interest|experience|goal", "label": "string ≤ 60" } ],  // ≤ 30, what the user has kept so far
  "asked": ["previous question", "..."],                                    // ≤ 3
  "answer": "string 0..500 — the answer to the LAST asked question, or empty when skipped",
  "catalogLabels": ["..."]
}
```

Response:

```json
{
  "facts": [ { "kind": ..., "label": ..., "source": "exact excerpt of `answer`" } ],   // ≤ 6
  "question": "next question" | null,     // always null once `asked` has 3 entries
  "generator": { ... }
}
```

## `POST /v1/talking-points`

Called only by the one phone generating for a confirmed pair, and only when both
people allowed cloud processing. Contains no names, bios or transcripts — only
the candidate pairs the app has already verified.

Max body 8 KB.

```json
{
  "candidates": [
    { "id": "string ≤ 80",
      "kind": "shared" | "complementary",
      "mine": "label ≤ 60",
      "theirs": "label ≤ 60" }
  ]   // 0..8
}
```

Response:

```json
{
  "points": [ { "candidateId": "must be one of the request ids", "prompt": "question ≤ 180 ending in ?" } ],  // ≤ 4, unique ids
  "opener": "one question ≤ 180 ending in ?",
  "generator": { ... }
}
```

With zero candidates the model writes only a warm, general `opener` and `points`
is empty.

## `POST /v1/voice/session`

Issues a short-lived token for xAI's realtime voice API (spoken onboarding).
Empty body. Rate limited separately (6/min per client by default).

```json
{ "token": "xai-realtime-client-secret-…", "expiresAt": 1790000000,
  "url": "wss://api.x.ai/v1/realtime", "model": "grok-voice-latest", "voice": "eve" }
```

The phone opens `url?model=<model>` with the WebSocket subprotocol
`xai-client-secret.<token>`. The API key never leaves the server; the token
expires after 5 minutes and is never logged.

## `POST /v1/profile/revise`

A spoken reply to "Does that sound right?", turned into card edits. Max body 16 KB.

```json
{ "items": [ { "id": "fact-1", "kind": "interest", "label": "Valorant" } ],   // ≤ 30
  "utterance": "Change Valorant to Overwatch" }                               // 1..500
```

Response:

```json
{ "intent": "confirm" | "correct" | "unclear",
  "remove": ["fact-1"],                                   // known ids only
  "rename": [ { "id": "fact-1", "label": "Overwatch" } ], // label must be in the utterance
  "add": [ { "kind": "interest", "label": "Techno", "source": "exact excerpt of utterance" } ],
  "generator": { ... } }
```

A `correct` with nothing usable after validation is returned as `unclear`.

## Server-side validation (all endpoints)

* Output must parse as JSON and match the schema (types, enums, lengths, counts).
* Every `source` / `bio.sources` entry must appear in the user's text after
  case/whitespace/punctuation folding. Facts that fail are dropped; a bio with
  no valid sources is replaced by `null`.
* Duplicate facts (same kind + folded label) are dropped.
* Questions must end in `?` and must not repeat anything in `asked`.
* Talking points referencing unknown candidate ids are dropped; duplicates dropped.
* If after validation nothing usable remains where something was required
  (e.g. `opener`), respond `502 upstream_invalid`.
