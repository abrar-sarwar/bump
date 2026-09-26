# ios-mockup/ — the iOS app, as HTML, for designing without a Mac

**Current update:** the mockup design was ported to Swift in commit `a38909d`,
then the current `main` behavior was merged locally into that UI. The merged
Swift app still needs an Xcode build and screen review. The historical porting
notes below describe the earlier mockup-only stage.

Read this before touching `ios-mockup/`. Written 2026-09-26 by Claude Code,
after one long session with the human. Everything here is what is true and
what the human asked for; where a direction was tried and rejected, it says so,
so the next tool does not re-propose it.

## Why it exists

The human has **no Mac**, so SwiftUI Previews, the Simulator and Xcode are out
of reach (see `30-ios.md`: the app needs Xcode 26+). The UI is where most of
their work will be. Options looked at and **turned down** ("hackathon project,
quick and free"):

- **Rent a Mac.** Researched 2026-09-26: Scaleway Mac mini M4 at €0.22/hr with
  Apple's mandatory 24h minimum (~€5.30), Paris only; MacinCloud pay-as-you-go
  $1/hr (25 hr prepaid) but a *managed* Mac with no admin and only macOS
  Sequoia 15.x listed, Xcode 26 availability unconfirmed; AWS EC2 mac2-m2
  ~$0.88/hr, 24h minimum, most setup friction. Xcode 26.0–26.3 needs macOS
  15.6+, Xcode 26.4+ needs Tahoe 26.2. No rental can plug in a real iPhone.
- **GitHub Actions macOS runners** taking Simulator screenshots via the app's
  `-BumpDemo <screen>` launch args (`View/DemoMode.swift`). Free for a public
  repo, ~10 min round trip. Offered, not built. Would need the repo owner's OK
  (`abrar-sarwar/bump`) or a fork.

**Chosen:** an HTML mockup. The human's plan, in their words: design everything
on the HTML side, get it approved, then move it to Swift and "figure out merge
conflicts for the application" afterwards.

## How to run it

No build, no install. Any of:

```bash
python3 -m http.server 8000 --bind 0.0.0.0 -d ios-mockup   # http://localhost:8000
# or double-click ios-mockup/index.html in Windows Explorer
```

A Claude Code session started that server in the background on 2026-09-26; it
dies with the session. `#screen-id` in the URL opens a screen directly
(`http://localhost:8000/#reveal`). Toolbar: **Prototype** (one clickable
phone; ← → steps every screen; waiting states auto-advance) / **All screens**
(grid), **Chrome** menu, **Zoom**. Viewer prefs persist in localStorage under
`bump-mockup-v3` (bump the suffix to reset everyone's defaults).

## Files

```
ios-mockup/
├── index.html      fonts (Archivo var wdth 75..125 wght 400..900, Inter), Material
│                   Symbols Rounded SUBSET (icon_names= must stay alphabetical;
│                   a missing icon renders as its name in text), script order
├── tokens.css      THE PORTING CONTRACT with Design/Theme.swift (see below)
├── components.css  every component; each block names its Swift type + web source
├── ios-chrome.css  device frame, status bar, top bar, tab bar, sheets; 4 chromes
├── shapes.js       MD3 shape formula (web's scallop()), badge morph keyframes
├── ui.js           HTML builders, one per component; screens use only these
├── screens.js      all 38 screens/states, copy verbatim from Swift
├── app.js          harness: state, router, grid, actions (not ported)
├── app.css         harness styles (not ported)
├── assets/wordmark.png   copied from web/src/assets (the real logo artwork)
└── README.md       human-facing guide + porting rules
```

38 screens in groups: Start (welcome) · Onboarding (name, consent, record,
recording, transcribing, transcript, typing on-phone, typing cloud, drafting,
questions, card) · Tutorial (4 pages) · Bump (home, event-code sheet, looking,
ready, event ready, checking, confirm, confirm manual, waiting, exchanging,
4 error states, pick-someone sheet) · Reveal (overlap, no overlap) ·
Connections (empty, list, detail) · You (you, edit profile).

**Not modelled:** Testing tools screen, mic-denied / recording-failed cards,
the Edit/Remove menus and alerts on the card step.

Sample data is `PreviewFixtures.swift` (Jared; "Sample Partner (demo)"; Sam
(sample) in onboarding). Copy is verbatim from the Swift views except where a
comment in `screens.js` says otherwise (the decorative bubble lines, "Step N of
4" eyebrows, "35mm photography" in the tutorial badge).

## The design language (current, after several rounds with the human)

**Rule from the human, in capitals: KEEP THE BRANDING THE SAME. LOGO SHOULD NOT
CHANGE.** Take heavy inspiration from the live site (`web/`, localhost:5173),
but **do not edit `web/`** from mockup work.

- **Logo = the Horizon wordmark artwork**, `assets/wordmark.png` via
  `ui.wordmark()`. Never set "BUMP" in a font. `wordmark--white` inverts it on
  blue, like the site's closing panel.
- **Type = Archivo** (the site's `--md-ref-typeface-brand`), **sentence case**.
  The site's sections use lowercase and a rounded system face: **NOT borrowed**
  (the human said the first attempt went "too far into folk").
- **Colour = the site's MD3 scheme**, copied verbatim from
  `web/src/styles/tokens.css` (seed `#70aaf9`, primary `#155fa9`, surface
  `#fdfcff`). Brand blue `#70aaf9` and phone orange `#f0955a` are artwork only.
- **Borrowed from the site** (tokens `--folk-*` copied verbatim): frosted cards
  with layered soft shadows, glossy orbs holding Material Symbols or a coloured
  letter (avatars: blue = you, orange = them), pill rows (`.row-pill`), grey
  tags with a blue check tag for shared/selected, grey pill tabs (the
  Experience/Goal picker), pastel bento washes (consent, cloud, errors), the
  hero backdrop (dot grid fading in from the edges + faint MD3 outline shapes +
  faint glyphs), blue pill buttons with a trailing icon, the uppercase
  letter-spaced eyebrow ("SCROLL TO BUMP" style), chat bubbles.
- **Phones = the DRAWN blue and orange phones** (`ui.phones()`), not the
  site's hand photographs. The human rejected the photos in the app.
- **Bubbles everywhere** (the human asked for more): tilted `ui.floaters()`
  around the phones on welcome, home, looking, ready, empty connections and
  two tutorial pages, using lines **verbatim from
  `web/src/components/HeroFloaters.tsx`** (lecture / 35mm / mixer); onboarding
  questions render as a chat (Grok = them, you = blue me-bubble); "Worth asking
  about" are bubbles; the conversation opener is your own blue bubble; bios
  are bubbles.
- **The shared badge** = the site's `SharedBadge.tsx`: pale circle, darker MD3
  shape inside that morphs and turns, text fixed on top. Used on reveal
  ("You're both into / Jazz"), the recording state (red), and the tutorial.
- **Tutorial "See what you share"**, exactly as the human specified: the badge
  **alone** (no card, no wash, no outline, **no "Message them?"** — the human
  sketched one, then said "DONT LITERALLY JUST ADD THE MESSAGE THEM"). It pops
  in (spring overshoot) and cycles "35mm photography" → "Climbing" → "Cold
  brew" every 4s. 300px, centred in the free space; title pushed down above the
  page dots.
- **Badge speed = 0.4x the site's.** Site loop ≈ 9.2s (4 morphs × 1.4s + 0.9s
  holds, one full turn), so the app loop is 23s. `badge--fast` (6s) is for the
  recording state.
- **Chrome "BUMP (site)" is the default:** frosted square back button (the
  site's back-to-top), frosted floating tab bar (the site's header pill) with a
  solid blue active tab, the wordmark in the top bar. "Material 3", "iOS 26"
  and "iOS 17/18" remain in the menu for comparison.

### The badge morph: a trap already hit

`shapes.js` builds `clip-path: polygon()` with 72 points so CSS can interpolate
between shapes. **Do not bake rotation into the polygon keyframes**: each point
then moves along a chord across the shape and the form visibly shrinks
mid-morph, cutting into the text (the human caught this). The morph carries no
rotation; a separate `rotate` animation (`badge-turn`) turns the element.
Lobes are shallower than the site's (5/.1, 9/.07, 4/.14, 7/.08, form inset 7%)
so it never pinches the text. Single-line interests are centred with
`align-items: center` on `.badge__cycle`.

**Open:** the human saw a thin black line under the tutorial badge. It could
not be reproduced in headless Chromium at 1x or 2x across the whole cycle.
Probably the old shrinking morph; if it returns, ask which browser.

## Directions tried and rejected (do not re-propose without being asked)

1. **Plain MD3 first pass** (Roboto Flex body, MD3 outlined fields, filter
   chips, MD3 top app bar / nav bar / bottom sheet). Human: "super generic".
2. **M3 Expressive** (explored m3.material.io: shape library, shape-morph
   loader, wavy progress, button groups, floating toolbar; generated a
   "vibrant" scheme with material-color-utilities). Human interrupted it and
   redirected to copying the live site instead. The "expressive" scheme variant
   swings primary to green; "vibrant" keeps blue, if ever needed.
3. **Folk all the way** (grey page, lowercase, rounded face). "Too far into
   folk", "KEEP THE BRANDING THE SAME".
4. **Hand photographs** as the phone art. Human: "change the hands stuff back
   to the phone images".
5. **Badge inside a card with a "Message them?" sheet.** Rejected; see above.

## Porting to Swift (not started)

- `tokens.css` keeps the `Theme.swift` names (`--BumpColor-*`, `--Space-*`) at
  the bottom, repointed at the site's roles. Port = add the MD3 roles and the
  folk card tokens to `Theme.swift`, then repoint `BumpColor` the same way.
- Components are built from tokens, **not `@material/web`** (Lit elements have
  no SwiftUI counterpart). Each block → one `ButtonStyle` / `ViewModifier` /
  `View`. Frosted card = white gradient + three shadows; orb = radial gradient +
  inner/outer shadow; shapes = the `scallop()` formula as a SwiftUI `Shape`
  with `animatableData` for the morph.
- Bundling needed on iOS: Archivo, Material Symbols Rounded (or swap back to SF
  Symbols; each icon helper in `ui.js` has the SF Symbol name in a comment),
  the wordmark PNG. The BUMP chrome's floating tab bar is a custom view (a
  `TabView` won't draw it).
- Workflow the README proposes: port in batches, tokens → components → views,
  using `git diff <last-port-commit> -- ios-mockup/` as the checklist; tag the
  commit ported from.

## Verification recipe (what was done each round)

Headless Chromium per `00-start-here.md` Environment
(`LD_LIBRARY_PATH=~/.local/lib/chromium-deps`, playwright imported by absolute
path from `web/node_modules`). Scratch scripts screenshot `.device` per screen
id with `reducedMotion: 'reduce'` (static frames), stitch contact sheets, and
check `pageerror`/console errors. For animation, capture frames without reduced
motion at intervals (the badge was checked across ~9s at 1.3s steps). Last
state: all 38 screens render, **no console errors**, controls work (checkbox,
chips, switch, sheet, text input).

## Git state (2026-09-26, end of session)

- Branch **`ios-mockup-vis-charan`** (from `landing-page-design` at `6124dc3`,
  so it carries the web commits too). The human asked for "ios mockup vis |
  charan"; spaces and `|` are invalid in git refs, so this name was used.
- `32de3f3` "iOS: HTML mockup of the app for designing without a Mac" = the
  FIRST, plain transcription only. **Pushed** to origin. No PR.
- Superseded: everything since is now committed in `a38909d` (pushed). Previously uncommitted in
  `ios-mockup/` (modified files + untracked `assets/`, `shapes.js`). The human
  said earlier: when committing, stage only `ios-mockup/`, nothing else.
- `web/` has uncommitted changes (`IntroSection.tsx`,
  `SharedInterestsPreview.tsx`, `sections.css`, new `SharedBadge.tsx`) that
  were **not made by the mockup work**: another tool/human was editing `web/`
  in parallel. Never stage them with mockup commits.
