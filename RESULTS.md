# Results — BLANK TEMPLATES

Two sets of templates, both unfilled:

- **Part A — Native BUMP MVP** (below). The current product.
- **Part B — Original hardware spikes** (further down). Preserved from the web +
  UWB feasibility experiments.

Nothing here is filled in. No physical testing has been done. Do not write a
decision before the numbers above it exist.

---

# PART A — Native BUMP MVP

## A1. Test context

| Field | Value |
|---|---|
| Date |  |
| Testers |  |
| Commit |  |
| Event/room code used |  |
| Phones running BUMP |  |
| Other people / phones in the room |  |
| Detection mode (motion / UWB / combined) |  |
| Which phone hosted |  |

| Label | Model | iOS | UWB supported? | Direction? | Apple Intelligence available? |
|---|---|---|---|---|---|
| A |  |  |  |  |  |
| B |  |  |  |  |  |
| C |  |  |  |  |  |
| D |  |  |  |  |  |

## A2. Settings

| Setting | Value |
|---|---|
| Motion threshold (m/s²) |  |
| Motion cooldown (s) |  |
| Per-device thresholds needed? |  |
| Pairing window (s) |  |
| Ambiguity margin (s) |  |
| Buffer (s) |  |
| UWB proximity threshold (m) |  |
| UWB freshness limit (s) |  |

## A3. Core journey

| Step | Worked? | Time taken | Notes |
|---|---|---|---|
| Onboarding → profile saved |  |  |  |
| Host room |  |  |  |
| Join room (peer appeared) |  |  |  |
| Ready → bump felt |  |  |  |
| Proposal shown on both phones |  |  |  |
| Both confirmed |  |  |  |
| Profiles exchanged |  |  |  |
| Reveal identical on both phones? |  |  |  |
| Save connection → appears in Connections |  |  |  |

## A4. Bump detection — 20+ intentional bumps

Denominators, agreed before testing:

- **Detection rate** = bumps felt ÷ intentional bumps attempted.
- **Match accuracy** = correct-partner proposals ÷ proposals produced.
- **Rejection rate** = (ambiguous + timeout) ÷ bumps that reached the coordinator.
- Report these **separately**. Rejecting everything yields zero wrong matches and
  is not success.

| # | Gentle/hard | Holding angle | Felt? | Proposal? | Right person? | UWB corroborated? | Time to proposal | Notes |
|---|---|---|---|---|---|---|---|---|
| 1 |  |  |  |  |  |  |  |  |
| 2 |  |  |  |  |  |  |  |  |
| 3 |  |  |  |  |  |  |  |  |
| 4 |  |  |  |  |  |  |  |  |
| 5 |  |  |  |  |  |  |  |  |
| 6 |  |  |  |  |  |  |  |  |
| 7 |  |  |  |  |  |  |  |  |
| 8 |  |  |  |  |  |  |  |  |
| 9 |  |  |  |  |  |  |  |  |
| 10 |  |  |  |  |  |  |  |  |
| 11 |  |  |  |  |  |  |  |  |
| 12 |  |  |  |  |  |  |  |  |
| 13 |  |  |  |  |  |  |  |  |
| 14 |  |  |  |  |  |  |  |  |
| 15 |  |  |  |  |  |  |  |  |
| 16 |  |  |  |  |  |  |  |  |
| 17 |  |  |  |  |  |  |  |  |
| 18 |  |  |  |  |  |  |  |  |
| 19 |  |  |  |  |  |  |  |  |
| 20 |  |  |  |  |  |  |  |  |

Totals: attempted ____ · felt ____ · **missed** ____ · proposals ____ ·
**wrong-person** ____ · ambiguous ____ · timeouts ____ ·
manual selection needed ____ times.

Detection rate ____ · Match accuracy ____ · **Rejection rate** ____ ·
Median time to confirmation ____ s.

## A5. False triggers

| Condition | Device-minutes | False triggers | **Per device-minute** |
|---|---|---|---|
| Sitting on a table |  |  |  |
| In hand, walking |  |  |  |
| In pocket, walking |  |  |  |
| Normal handling (unlock, scroll, put down) |  |  |  |

## A6. Crowded room

| Scenario | Correct | Wrong person | Ambiguous (rejected) | Timeout | Notes |
|---|---|---|---|---|---|
| Two pairs, four phones, simultaneous |  |  |  |  |  |
| Bystanders nearby running BUMP |  |  |  |  |  |
| Three or more bumping at once |  |  |  |  |  |
| One-sided motion (only one phone felt it) |  |  |  |  |  |

Did anyone ever get proposed to the **wrong** person? ____
(This is the number that matters most.)

## A7. UWB behaviour in the MVP

| Question | Answer |
|---|---|
| Distance at a steady 1 m — stable? For how long? |  |
| **Does ranging survive a close approach, or drop out below ~10 cm?** |  |
| Typical reading when the phones touch |  |
| How often was a bump UWB-corroborated? (n / total) |  |
| Direction available? Did it matter? |  |
| Body blocking line of sight |  |
| Stale measurements cleared correctly (no frozen number)? |  |

## A8. Failure and recovery

| Test | Result |
|---|---|
| "Not this person" on one side |  |
| Cancel while waiting for partner |  |
| Confirmation timeout (one side never confirms) |  |
| Background mid-bump, return to foreground |  |
| **Host disconnects** — was the rejoin/re-host path clear? |  |
| Guest disconnects mid-proposal |  |
| Nearby Interaction permission denied |  |
| Local Network permission denied |  |
| Motion unavailable |  |
| Room full (8 phones) |  |
| Any crash, hang, or indefinite spinner? |  |

## A9. Shared interests and AI

| Question | Answer |
|---|---|
| Were the shared interests correct and genuinely in both profiles? |  |
| Any invented/wrong shared interest? (should be zero) |  |
| Both phones showed the **same** result? |  |
| Opener source shown (AI vs Suggested question) |  |
| Quality of AI opener |  |
| Quality of fallback opener |  |
| With AI unavailable on one phone — did the other generate? |  |
| No-overlap case — was the wording warm and honest? |  |
| Talking points: shared vs "worth asking about" correctly separated? |  |
| Talking point evidence reads correctly on **both** phones ("You" = that phone's owner)? |  |
| Both allowed cloud → source shows "Written by Grok (xAI) via the BUMP server"? |  |
| One person local-only → **no** Grok request made (check bump-api log shows no `/v1/talking-points`)? |  |
| BUMP server stopped mid-event → fallback within ~9 s, labelled honestly? |  |

## A9b. Pre-event onboarding (voice + Grok)

| Question | Answer |
|---|---|
| Onboarding time, voice path (target ≈ 1 min) |  |
| Onboarding time, typed / local-only path |  |
| Transcript accuracy (noisy room?) |  |
| Any suggested fact NOT supported by what was said? (should be zero) |  |
| Follow-up questions repeated something already said? |  |
| Mic permission denied → clear message + Type instead? |  |
| Phone call during recording → take stopped, message shown? |  |
| Airplane mode → local draft, notice shown, nothing labelled Grok? |  |
| Profile saved before this update still loads after upgrading? |  |

## A10. Decision — native MVP

Success criteria, agreed **before** testing:

| Criterion | Target | Met? |
|---|---|---|
| Detection rate |  |  |
| Wrong-person proposals |  |  |
| Rejection rate with two pairs |  |  |
| False triggers per device-minute walking |  |  |
| Time to confirmation |  |  |
| Crashes / dead ends |  |  |

**Decision:** ☐ GO ☐ NO-GO ☐ NEEDS MORE TESTING

Evidence:

```
```

Biggest limitation found:

```
```

Next smallest experiment:

```
```

---

# PART B — Original hardware spikes

Preserved from the original feasibility experiments. The code for both has since
been removed from the tree — the web spike lives in git history at commit
`278d2e0`, and the UWB spike was refactored into the app in `ios/`.

## B0. Experiment results — BLANK TEMPLATE

Nothing here is filled in. No physical testing has been done. Do not write a
decision before the numbers above it exist.

---

## 1. Test context

| Field | Value |
|---|---|
| Date |  |
| Testers |  |
| Commit / app version |  |
| Room and approximate size |  |
| People in the room |  |
| **Phones running experiment 1** |  |
| **Phones running experiment 2** |  |
| Other UWB/BLE devices present (AirTags, Watches…) |  |
| Network (venue Wi-Fi / hotspot / cellular) |  |
| Measured RTT to server (ms) |  |
| Deployment method (Render / cloudflared / ngrok / localhost) |  |

### Devices

| Label | Model | OS version | Browser + version (exp. 1) | UWB supported? (exp. 2) | Direction supported? |
|---|---|---|---|---|---|
| A |  |  |  |  |  |
| B |  |  |  |  |  |
| C |  |  |  |  |  |
| D |  |  |  |  |  |

---

## 2. Experiment 1 — web bump pairing

### Settings used

| Setting | Value |
|---|---|
| Threshold (m/s²) |  |
| Per-device thresholds needed? (which, and what values) |  |
| Sensor source per device (`acceleration` / gravity-filtered) |  |
| Units confirmed as m/s² |  |
| Pairing window (ms) |  |
| Ambiguity margin (ms) |  |
| Buffering period (ms) |  |
| Bump timeout (ms) |  |

### Detection (the sensor question)

| Pair | Intentional bumps attempted | Spikes detected | Missed (no spike) | Suppressed by cooldown |
|---|---|---|---|---|
| iPhone ↔ iPhone |  |  |  |  |
| Android ↔ Android |  |  |  |  |
| iPhone ↔ Android |  |  |  |  |
| Gentle bumps |  |  |  |  |
| Harder bumps |  |  |  |  |

**Detection rate** = spikes detected ÷ intentional bumps attempted = ______

### False triggers (the noise question)

| Condition | Device-minutes observed | False triggers | **False positives per device-minute** (triggers ÷ device-minutes) |
|---|---|---|---|
| Stationary on a table |  |  |  |
| In pocket, walking |  |  |  |
| In hand, walking |  |  |  |
| Running / jogging |  |  |  |

### Matching (the pairing question)

Denominators, agreed before testing:

- **Matching accuracy** = correct matches ÷ *bumps that produced a server event*.
- **Rejection rate** = (ambiguous + timeout) ÷ bumps that produced a server event.
- These are reported **separately on purpose**. An algorithm that rejects every
  bump has 0 wrong matches and is still useless, so a high accuracy figure means
  nothing without the rejection rate beside it.

| Scenario | Server bump events | Correct matches | **Wrong** matches | Ambiguous (rejected) | Timeouts | Accuracy | Rejection rate |
|---|---|---|---|---|---|---|---|
| One pair alone in a room |  |  |  |  |  |  |  |
| Two pairs, same room, deliberately simultaneous |  |  |  |  |  |  |  |
| Two pairs, separate rooms |  |  |  |  |  |  |  |
| Three or more near-simultaneous bumps |  |  |  |  |  |  |  |
| Bump with no partner present |  |  |  |  |  |  |  |
| **Overall** |  |  |  |  |  |  |  |

Cross-room matches observed (must be 0): ______

### Latency

| Measure | Value |
|---|---|
| Median bump → proposal shown (ms) |  |
| Worst observed (ms) |  |
| Median proposal → both confirmed (s) |  |
| How measured |  |

### Robustness

| Test | Result |
|---|---|
| Motion permission denied — was the message clear? |  |
| Disconnect mid-proposal, then reconnect |  |
| Cancel and retry immediately |  |
| One side confirms, other never does (confirmation timeout) |  |
| Page backgrounded mid-experiment |  |
| Server cold start / restart during testing |  |

### Notes and surprises

```
```

---

## 3. Experiment 2 — iPhone UWB proximity

### Range and reliability

| True separation | Median reading | Spread (min–max) | Error vs truth | Update rate (Hz) | Dropouts in 30 s | Direction available? |
|---|---|---|---|---|---|---|
| 1 m |  |  |  |  |  |  |
| 3 m |  |  |  |  |  |  |
| 5 m |  |  |  |  |  |  |
| 9 m |  |  |  |  |  |  |
| Max range where ranging still worked: ______ | | | | | | |

### Direction

| Question | Answer |
|---|---|
| Devices reporting `supportsDirectionMeasurement` |  |
| % of updates with a non-nil direction (roughly) |  |
| Is the bearing stable or jittery? |  |
| Field of view where direction appears / disappears |  |
| Usable for pointing at a person? |  |

### Environment effects

| Condition | Effect on distance | Effect on direction | Dropouts |
|---|---|---|---|
| Portrait |  |  |  |
| Landscape |  |  |  |
| Line of sight blocked by a body |  |  |  |
| Phone in a case |  |  |  |
| Crowded room (____ phones running this app) |  |  |  |

### Proximity trigger near 0.15 m

| Measure | Value |
|---|---|
| Deliberate contacts attempted |  |
| **BUMP DETECTED** fired correctly |  |
| **Missed** (touched, no detection) |  |
| **False** detections (fired without contact) |  |
| Typical reading when phones physically touch |  |
| Smallest distance the radio would report at all |  |
| Is 0.15 m the right threshold? What would you use? |  |

### Connection and lifecycle

| Test | Result |
|---|---|
| Time from Start to first distance reading |  |
| Did the peer picker show the right phone in a crowd? |  |
| Duplicate/crossed invitations observed? |  |
| Backgrounded — did ranging stop and values clear? |  |
| Returned to foreground — resumed without Reset? How long? |  |
| Peer walked out of range, then back |  |
| Peer force-quit the app |  |
| Nearby Interaction permission denied — message clear? |  |
| Local Network permission denied — message clear? |  |
| Session invalidations seen (and error text) |  |
| Crashes or hangs |  |

### Hardware differences

| Device pair | Notable difference |
|---|---|
|  |  |
|  |  |

Unsupported devices encountered (model + what the app showed):

```
```

---

## 4. Decision

### Success criteria — agree on these BEFORE testing

| Experiment | Criterion | Target | Met? |
|---|---|---|---|
| Web bump | Detection rate |  |  |
| Web bump | Wrong matches |  |  |
| Web bump | Rejection rate in a dense room |  |  |
| Web bump | False positives per device-minute while walking |  |  |
| Web bump | Bump → proposal latency |  |  |
| UWB | Distance error at 1 m |  |  |
| UWB | Proximity-trigger hit rate at contact |  |  |
| UWB | False proximity detections |  |  |
| UWB | Dropouts in a crowded room |  |  |

### Experiment 1 — web bump matching

**Decision:** ☐ GO ☐ NO-GO ☐ NEEDS MORE TESTING

Evidence:

```
```

### Experiment 2 — UWB proximity detection

**Decision:** ☐ GO ☐ NO-GO ☐ NEEDS MORE TESTING

Evidence:

```
```

### Direct comparison

| | Motion bump (web) | UWB proximity (native iOS) |
|---|---|---|
| Works on Android |  |  |
| Works on all iPhones |  |  |
| Needs an app install |  |  |
| Needs a server |  |  |
| Measured accuracy in a crowd |  |  |
| Failure mode when it goes wrong |  |  |
| Time from "two strangers meet" to "paired" |  |  |
| Setup friction for the user |  |  |
| Effort to make production-ready |  |  |
| **Which one would you build on, and why** |  |  |

### Limitations we hit

```
```

### Unresolved questions

```
```

### The next smallest experiment

```
```
