# BUMP

**Meet someone. Find your overlap.**

Two people tap phones, confirm each other, and get the specific things they
actually have in common — plus one question to start on. No account, no server,
no cloud AI, no API keys. Everything runs on the phones in the room.

| | What it is | Status |
|---|---|---|
| [**`uwb-ios/`**](uwb-ios/README.md) | **The native iOS MVP.** Swift + SwiftUI, Core Motion, Nearby Interaction, MultipeerConnectivity, on-device Apple Intelligence with a real fallback. | Builds clean, 43 unit tests pass, UI inspected in the Simulator. **Unproven on two physical phones.** |
| [`bump-web/`](bump-web/README.md) | The earlier browser experiment (Node + Socket.io + `devicemotion`). Kept for reference and Android testing. | Working spike. Not on the native app's critical path. |
| [`RESULTS.md`](RESULTS.md) | Blank results templates — the original spikes, plus one for the native MVP. | To fill in on test day. |

## Quick start

```bash
# The app
open uwb-ios/UWBBumpTest.xcodeproj        # then follow uwb-ios/README.md

# The old web experiment (optional, Android testing)
cd bump-web && npm install && npm start
```

Prerequisites for the MVP: a Mac with **Xcode 26+** and **two iPhones**. The
deployment target is iOS 17, and UWB and on-device AI are both optional — the app
degrades cleanly without either. The Simulator cannot validate UWB or motion.

## The shortest two-phone test

1. Build and run on both phones (`uwb-ios/README.md` has the signing steps).
2. Onboard on both. **Give them at least one interest in common.**
3. Phone A: event code `hackgt` → **Host it on this phone**.
4. Phone B: same code → **Join this event**.
5. Both: **Ready to bump** → tap the phones together once.
6. Both: **Confirm & share interests**.
7. Shared interests + opener appear on both → **Save connection**.

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
