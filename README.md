# BUMP

**Meet someone. Find your overlap.**

Two people tap phones, confirm each other, and get the specific things they
actually have in common — plus one question to start on.

```
bump/
├── web/        # React website — not built yet
├── ios/        # SwiftUI app: motion detection, UWB, pairing, on-device AI
├── backend/    # Shared API if we ever need one — deliberately not required
└── README.md
```

| | What it is | Status |
|---|---|---|
| [**`ios/`**](ios/README.md) | The product. Swift + SwiftUI, Core Motion, Nearby Interaction, MultipeerConnectivity, on-device Apple Intelligence with a real fallback. | Builds clean, 43 unit tests pass, UI inspected in the Simulator. **Unproven on two physical phones.** |
| [`web/`](web/README.md) | The website. | Placeholder. |
| [`backend/`](backend/README.md) | Optional shared API. | Placeholder, and nothing depends on it. |
| [`RESULTS.md`](RESULTS.md) | Blank results templates for the MVP and the original spikes. | To fill in on test day. |

The iOS app needs **no account, no server, no cloud AI and no API keys** —
everything runs on the phones in the room. Keep it that way: anything added under
`backend/` should stay optional so the core journey still works with no network.

## Quick start

```bash
open ios/UWBBumpTest.xcodeproj      # then follow ios/README.md
```

Prerequisites: a Mac with **Xcode 26+** and **two iPhones**. Deployment target is
iOS 17; UWB and on-device AI are both optional and degrade cleanly. The Simulator
cannot validate UWB or motion.

## The shortest two-phone test

1. Build and run on both phones (`ios/README.md` has the signing steps).
2. Onboard on both. **Give them at least one interest in common.**
3. Phone A: event code `hackgt` → **Host it on this phone**.
4. Phone B: same code → **Join this event**.
5. Both: **Ready to bump** → tap the phones together once.
6. Both: **Confirm & share interests**.
7. Shared interests + opener appear on both → **Save connection**.

Instrumentation lives in **You ▸ Testing tools** (live acceleration, live UWB
distance, pairing sliders, event log, diagnostics export), deliberately kept out
of the normal flow.

## What we know and don't know

Motion tells a phone *that* it was tapped, not *who* tapped it. The coordinator
pairs bumps by its own arrival times, and when several people bump at the same
instant that genuinely cannot identify partners — so BUMP **rejects** rather than
guesses, and offers a manual pick that is recorded honestly as a manual pick. UWB
distance is much stronger evidence about *which* peer, when it's available.

How well that holds up in a crowded room has not been measured yet. The number
that decides it is the **rejection rate**, reported separately from accuracy in
`RESULTS.md` — rejecting everything would otherwise look perfect.

An earlier Node + Socket.io browser experiment was removed from the tree; it is
still in git history at commit `278d2e0`.
