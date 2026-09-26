# ios-mockup

An HTML stand-in for the SwiftUI app in `ios/`, so the app's UI can be designed
without a Mac. Design here, get it approved, then port the approved changes to
Swift.

**This is not the app.** It is a careful transcription of it: same tokens, same
components, same copy, same layout rules. The fonts, spacing and system chrome
will still be slightly off, because the browser isn't iOS. Anything that matters
at the pixel level gets a final check in Xcode or a CI screenshot once it's ported.

## Open it

No build step, no install. Either:

- double-click `ios-mockup/index.html` in Windows Explorer, or
- `python3 -m http.server -d ios-mockup 8000` then http://localhost:8000

Two ways to look at it:

- **Prototype**: one phone, fully clickable. Get started → onboarding → tutorial →
  bump → confirm → reveal, with the waiting states advancing on their own.
  Use ← → to step through every screen in order.
- **All screens**: every screen and state side by side, for reviewing.

`index.html#reveal` (or any screen id) opens a screen directly. The **Chrome** menu
switches between Material 3 (the default), iOS 26 (Liquid Glass) and iOS 17/18
(flat bars).

## Design language: the marketing site

The mockup follows the live site (`web/`, localhost:5173). `web/` is never
edited from here; its tokens and assets are copied in.

- **Brand, unchanged:** the Horizon wordmark artwork (`assets/wordmark.png`,
  never set in a font), Archivo for type, sentence case, the site's MD3 colour
  scheme (seed `#70aaf9`), blue pill buttons with a trailing icon, the drawn
  blue and orange phones.
- **Borrowed from the site:** the hero backdrop (dot grid, faint MD3 shapes),
  frosted cards with layered shadows, glossy orbs, pill rows, tags, pill tabs,
  chat bubbles and tilted bubble "floaters" (lines verbatim from
  `HeroFloaters.tsx`), and the morphing "you both share this" badge
  (`SharedBadge.tsx`), here at 0.4x the site's speed (23s loop).
- **Not borrowed:** the sections' lowercase and rounded system face.
- `shapes.js` uses the site's `scallop()` formula, so the shapes match.
- Chrome defaults to "BUMP (site)": frosted square buttons and a frosted
  floating tab bar with a blue active tab. The MD3 and iOS options remain.

## How it maps to Swift

| Here | In `ios/UWBBumpTest/` | Port by |
|---|---|---|
| `tokens.css` | `Design/Theme.swift` | Same names, same values. `--BumpColor-navy` is `BumpColor.navy`, `--Space-l` is `Space.l`. Copy the numbers across. |
| `components.css` + `ui.js` | `Design/Components.swift` (+ small private views) | One block / one function per Swift type, named in a comment. |
| `screens.js` | `View/*.swift` | Each screen lists its Swift file and view. Copy is verbatim from Swift. |
| `ios-chrome.css` | nothing (iOS) / custom views (MD3) | Status bar, top bar, tab bar, sheets. |
| `app.js`, `app.css` | nothing | The review harness. |

The `.t-*` classes keep the `BumpFont` names but now map to MD3 roles:
`screenTitle` is headline-medium, `sectionTitle` title-large, `body` body-large,
`bodyEmphasis` title-medium, `caption` body-medium, `caption2` body-small. The
wordmark is Archivo at width 125 / weight 900.

## Rules that keep the port painless

1. **Change tokens, not one-offs.** A new colour or spacing value goes in
   `tokens.css` under a name you'll also add to `Theme.swift`. A hex value typed
   into a screen won't make it across.
2. **Only use layouts SwiftUI has.** Stacks with a spacing value, padding,
   `FlowLayout`, cards, `ScrollView`. If you can't say which SwiftUI modifier
   gives you a CSS rule, it'll be hard to port.
3. **Say which Swift file a new screen belongs to** in its `add(...)` line.
4. **Copy changes are real changes.** The Swift strings are the source of truth
   until a change here is approved; then update both.
5. Sample people are fictional and labelled `(demo)` / `(sample)`, as in
   `PreviewFixtures.swift`.

## Porting and merge conflicts

The mockup only lives in `ios-mockup/`, so design work never touches `ios/`
and can't conflict with Swift work going on at the same time. When a batch of
changes is approved, port them in one pass, tokens first (`Theme.swift`), then
components, then views. The diff of this folder since the last port is your
checklist:

```bash
git diff <last-port-commit> -- ios-mockup/
```

Tag the commit you ported from (for example `git tag mockup-ported-1`) so the
next port starts from there.
