# BUMP

**Meet someone. Find your overlap.**

Two people tap phones, confirm each other, and get the specific things they
actually have in common — plus a few grounded talking points. No account.
Bumping, matching and the profile exchange run on the phones in the room.
Optional cloud features — a spoken intro, Grok-drafted profiles and Grok talking
points — go through our small `bump-api` server, only with each person's
permission. The app never holds an API key.

| | What it is | Status |
|---|---|---|
| [**`uwb-ios/`**](uwb-ios/README.md) | **The native iOS MVP.** Swift + SwiftUI, Core Motion, Nearby Interaction, MultipeerConnectivity, voice-intro onboarding, Grok via `bump-api` with Apple Intelligence and deterministic fallbacks. | Builds clean, 89 unit tests pass (mocked network), onboarding + reveal inspected in the Simulator. **Unproven on two physical phones; not yet run against live xAI.** |
| [**`bump-api/`**](bump-api/README.md) | Tiny zero-dependency Node service between the app and xAI (speech-to-text + Grok structured outputs). Holds the `XAI_API_KEY`. | 41 mocked tests pass. **Not yet run against live xAI.** |
| [`bump-web/`](bump-web/README.md) | The earlier browser experiment (Node + Socket.io + `devicemotion`). Kept for reference and Android testing. | Working spike. Not on the native app's critical path. |
| [`RESULTS.md`](RESULTS.md) | Blank results templates — the original spikes, plus one for the native MVP. | To fill in on test day. |

## Quick start

```bash
# The app
open uwb-ios/UWBBumpTest.xcodeproj        # then follow uwb-ios/README.md

# The Grok backend (optional — the app works without it)
cd bump-api && cp .env.example .env   # put your XAI_API_KEY in .env
npm start                             # http://0.0.0.0:8787

# The old web experiment (optional, Android testing)
cd bump-web && npm install && npm start
```

Prerequisites for the MVP: a Mac with **Xcode 26+** and **two iPhones**. The
deployment target is iOS 17, and UWB and on-device AI are both optional — the app
degrades cleanly without either. The Simulator cannot validate UWB or motion.

## The shortest two-phone test

1. Build and run on both phones (`uwb-ios/README.md` has the signing steps).
2. Onboard on both (speak or type an intro, approve your card). **Give them at least one interest in common.**
3. Both: Bump tab → **Start bumping**. The phones find each other automatically
   (one quietly becomes the coordinator); no event code needed.
4. When "1 person nearby" shows, tap the phones together once.
5. Both: **Confirm & share interests**.
6. Shared interests + talking points appear on both → **Save connection**.

For a big event, **Have an event code?** on the Bump tab still gives named
rooms (8 phones each).

Instrumentation lives in **You ▸ Testing tools** (live acceleration, live UWB
distance, pairing sliders, event log, diagnostics export). It is deliberately
kept out of the normal flow.

## What we know and don't know

Motion tells a phone *that* it was tapped, not *who* tapped it. The coordinator
pairs bumps by its own arrival times, and when several people bump at the same
instant that genuinely cannot identify partners — so BUMP **rejects** rather than
guesses, and offers a manual pick that is recorded honestly as a manual pick.
UWB distance is much stronger evidence about *which* peer, when it's available.

How well that holds up in a crowded room is exactly what has not been measured
yet. The number that decides it is the **rejection rate**, reported separately
from accuracy in `RESULTS.md` — rejecting everything would otherwise look perfect.

The root `bump/` + `bump.xcodeproj` is the original stock SwiftUI template,
untouched.
