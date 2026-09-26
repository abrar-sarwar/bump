# BUMP

**Meet someone. Find your overlap.**

Two people tap phones, confirm each other, and get the specific things they
actually have in common, plus a few grounded talking points to start on.

```
bump/
├── web/        # React marketing site (Vite + GSAP scroll sequence)
├── ios/        # SwiftUI app: onboarding, motion, UWB, pairing, talking points
├── backend/    # The BUMP server between the app and xAI (bump-api)
└── README.md
```

| | What it is | Status |
|---|---|---|
| [**`ios/`**](ios/README.md) | The product. Swift + SwiftUI, Core Motion, Nearby Interaction, MultipeerConnectivity, voice-intro onboarding, Grok talking points with Apple Intelligence and deterministic fallbacks. | Builds clean, 100 unit tests (96 pass, 4 server contract tests skipped), UI inspected in the Simulator and on one iPhone. **Unproven on two physical phones.** |
| [`web/`](web/README.md) | The marketing site. React + TypeScript + Vite, with one scroll-driven opening sequence built on GSAP/ScrollTrigger. | Built. Verified across both breakpoints, reduced motion, resize and fast scroll. |
| [`backend/`](backend/README.md) | The BUMP server (`bump-api`), a Node service between the app and xAI: speech-to-text and Grok structured outputs. Holds the `XAI_API_KEY`. | 42 mocked tests pass; live smoke test against xAI passed. |
| [`RESULTS.md`](RESULTS.md) | Blank results templates for the MVP and the original spikes. | To fill in on test day. |

BUMP runs with a server. The backend powers the spoken intro, Grok-drafted
profiles and Grok talking points, and it holds the xAI key so the app never
does. There's still no account. Bumping, matching and the profile exchange
happen directly between the phones in the room, and each person chooses
whether their data goes to the server. If the server can't be reached, the app
falls back to on-phone suggestions and says so, so an event doesn't stop.

## Quick start

```bash
open ios/UWBBumpTest.xcodeproj      # then follow ios/README.md

# The BUMP server (voice + Grok)
cd backend && cp .env.example .env  # put your XAI_API_KEY in .env
npm start                           # http://0.0.0.0:8787

# The marketing site
cd web && npm install && npm run dev  # http://localhost:5173
```

Prerequisites: a Mac with **Xcode 26+** and **two iPhones**. Deployment target is
iOS 17; UWB and on-device AI are both optional and degrade cleanly. The Simulator
cannot validate UWB or motion.

## The shortest two-phone test

1. Build and run on both phones (`ios/README.md` has the signing steps).
2. Onboard on both (speak or type an intro, approve your card). **Give them at least one interest in common.**
3. Both: Bump tab → **Start bumping**. The phones find each other automatically
   (one quietly becomes the coordinator); no event code needed.
4. When "1 person nearby" shows, tap the phones together once.
5. Both: **Confirm & share interests**.
6. Shared interests + talking points appear on both → **Save connection**.

For a big event, **Have an event code?** on the Bump tab still gives named
rooms (8 phones each).

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
