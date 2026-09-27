<div align="center">

<img src="web/src/assets/wordmark.png" alt="BUMP logo" width="300" />

**Meet someone. Find your overlap.**

The hardest part is often not meeting someone. It is knowing what to say first.

Bump helps two nearby people uncover the specific interests, experiences, and goals they already share, so the first conversation does not have to start from nothing.

Tap phones. Find the overlap. Start talking.

![platform iOS 17+](https://img.shields.io/badge/iOS-17%2B-ff9500?logo=apple&logoColor=white)
![Swift + SwiftUI](https://img.shields.io/badge/Swift-SwiftUI-ff9500?logo=swift&logoColor=white)
![backend Node 20+](https://img.shields.io/badge/backend-Node%2020%2B-ff9500?logo=nodedotjs&logoColor=white)
![web React + Vite](https://img.shields.io/badge/web-React%20%2B%20Vite-ff9500?logo=vite&logoColor=white)
<!-- TODO: add a license badge once LICENSE exists -->

[Problem](#the-problem) · [What it does](#what-it-does) · [Demo](#demo) ·
[How it works](#how-it-works) · [Tech stack](#tech-stack) · [Roadmap](#roadmap) ·
[Team](#team--acknowledgments)

</div>

---

## The problem

**The people you would get along with may already be in the room. You just don't know what to say to them yet.**

Before class, at a hackathon, or waiting for an event to begin, people can stand a few feet apart and never speak. That small moment sits inside a much larger problem: the [WHO Commission on Social Connection](https://www.who.int/groups/commission-on-social-connection) estimates that roughly **1 in 6 people worldwide experience loneliness**. But the missed connection itself often happens somewhere much more ordinary: two people have an opportunity to talk, and neither knows whether to begin.

Research suggests that this uncertainty is often miscalibrated. [Epley & Schroeder (2014)](https://doi.org/10.1037/a0037323) found that commuters assigned to talk with a stranger reported more positive experiences than those assigned to remain disconnected, even though separate participants predicted the opposite. Across seven studies, [Sandstrom & Boothby (2021)](https://doi.org/10.1080/15298868.2020.1816568) similarly found that people's fears before talking to strangers were generally worse than the conversations that followed. **Silence is weak evidence that a conversation would be unwelcome.**

But willingness alone does not tell you what to say. A stranger gives you almost no context. You have to guess what they care about, whether you share anything, and which opening will actually land. **"We both like music" is trivia. "You build modular synths too?" is a conversation.**

Not every similarity carries the same signal. [Alves (2018)](https://doi.org/10.1177/0146167218766861) found that sharing rarer interests produced stronger interpersonal attraction than sharing common ones, suggesting that distinctive overlap can reveal more than broad similarity. Two people can already share the thing that would start a ten-minute conversation and still walk past each other without ever finding out.

**The common ground already exists. The missing piece is seeing it when it matters.**

## What it does

**Bump gives two people who are already near each other just enough common ground to start talking.**

Create a lightweight profile from a short spoken introduction, then edit it until it feels like you. When someone nearby also has Bump open, **Wave can surface one shared-interest teaser**. Enough to make you curious. Not enough to replace meeting them.

See someone you want to meet? **Bump your phones together.** Once both people confirm the interaction, Bump reveals a few specific things you genuinely have in common, along with grounded conversation starters.

> **you both like music**  
> useful, but broad.
>
> **you both build modular synths**  
> now there is something to talk about.

There is no compatibility percentage and no feed to scroll. Bump is not trying to decide who you should be friends with. It helps answer a much smaller question:

**“what could we talk about right now?”**

Then you put the phones down.

## Demo

<!-- TODO: add a demo GIF or screenshots of onboarding, the bump, and the overlap screen -->
<!-- TODO: add the demo video link once recorded -->

| Marketing site | Demo video | Screenshots |
|---|---|---|
| _Not deployed yet_ | _To record_ | _To capture_ |

## How it works

**One gesture. Four systems underneath it.**

### 1. Build a profile

```mermaid
flowchart LR
    A["Voice or text"] --> B["Bump API"]
    B --> C["xAI Grok"]
    C --> D["Transcribe + structure"]
    D --> E["User reviews"]
    E --> F["Approved profile"]
```

Grok structures what you say into profile facts. **You decide what actually represents you.**

### 2. Discover nearby people

```mermaid
flowchart LR
    A["Your device"] --> C["MultipeerConnectivity"]
    B["Nearby Bump user"] --> C
    C --> D["Peer discovered"]
    D --> E["Nearby Interaction / UWB"]
    E --> F["Close-range encounter"]
    F --> G["One shared-interest teaser"]
```

MultipeerConnectivity finds participating devices. UWB adds proximity evidence. **StreetPass reveals one reason you might want to meet, not their whole profile.**

### 3. Pair the bump

```mermaid
flowchart LR
    A["Core Motion<br/>gesture"] --> C["Pairing coordinator"]
    B["UWB<br/>distance"] --> C
    C --> D{"Clear pair?"}
    D -- "No" --> E["Reject"]
    D -- "Yes" --> F["Propose match"]
    F --> G["Both confirm"]
```

**Motion tells us a bump happened. UWB helps tell us who it happened with.** If the signals are ambiguous, Bump does not guess.

### 4. Find the overlap

```mermaid
flowchart LR
    A["Both confirm"] --> B["Encrypted profile exchange"]
    B --> C["Grounded matching"]
    C --> D["Shared interests"]
    C --> E["Complementary interests"]
    C --> F["Goals ↔ experience"]
    D --> G["Conversation starters"]
    E --> G
    F --> G
    G --> H["Grok or on-device fallback"]
    H --> I["Same result on both phones"]
```

Bump finds the connection first. **AI helps phrase grounded overlap into something worth saying. It does not invent the match.**

## Tech stack

Bump is built as a native iOS experience, with nearby communication and sensor processing happening on the phones and optional cloud AI routed through a small backend.

| Layer | Technology | Role |
|---|---|---|
| **App** | Swift + SwiftUI | Native iOS interface and application logic |
| **Bump detection** | Core Motion | Detects the physical bump gesture from device acceleration |
| **Peer ranging** | Nearby Interaction + Ultra Wideband | Provides peer-specific distance evidence when supported |
| **Nearby communication** | MultipeerConnectivity | Discovers nearby devices and carries peer-to-peer session data |
| **StreetPass** | MultipeerConnectivity + Nearby Interaction | Detects close encounters and surfaces a single shared-interest teaser |
| **Profile + matching AI** | xAI Grok | Transcription, profile drafting, and grounded conversation-starter phrasing |
| **On-device fallback** | Apple Foundation Models + deterministic templates | Keeps matching usable when cloud AI is unavailable or disabled |
| **Backend** | Node.js | Proxies xAI requests and keeps API credentials off-device |
| **Local state** | JSON on device | Stores the editable user profile and prototype state |
| **Landing page** | React + TypeScript + Vite + GSAP | Project website and product presentation |

### Architecture at a glance

**The phones handle the encounter. The server handles optional intelligence.**

Core Motion, Nearby Interaction, and MultipeerConnectivity run the real-world discovery and pairing flow directly on iOS. Approved profile data is exchanged between the confirmed devices.

The backend is deliberately small. It keeps the xAI API key off the phone and provides cloud transcription and Grok-assisted generation when users opt into it.

Bump does not depend on the cloud to recognize a physical bump or establish a nearby peer connection.

## Roadmap

Everything here is future work; none of it is in the current build.

- [ ] **A real two-phone session**, measured, with [`RESULTS.md`](RESULTS.md) filled in.
      Pairing in a crowded room has not been measured yet; the number that decides
      it is the rejection rate, reported separately from accuracy so that
      rejecting everything cannot score as perfect.
- [ ] **Crowded-room testing**: many simultaneous bumps, rejection rate under load.
- [ ] **Android**, or the honest conclusion that the UWB path can't cross platforms.
- [ ] **Connection follow-up**: an export or share of a saved connection.
- [ ] **Event mode polish**: larger rooms than the current 8 phones per event code.

## Team & acknowledgments

[@jsberesford](https://github.com/jsberesford)
[@CharanPeeriga](https://github.com/CharanPeeriga)
[@lui-gi](https://github.com/lui-gi)
[@abrar-sarwar](https://github.com/abrar-sarwar)

## License

<!-- TODO: no LICENSE file exists; choose one and add the badge above -->

_No license file yet._
