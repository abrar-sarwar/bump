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
switches between iOS 26 (Liquid Glass tab bar and buttons) and iOS 17/18 (flat bars).
Xcode 26 builds pick up whichever one the phone runs.

## How it maps to Swift

| Here | In `ios/UWBBumpTest/` | Port by |
|---|---|---|
| `tokens.css` | `Design/Theme.swift` | Same names, same values. `--BumpColor-navy` is `BumpColor.navy`, `--Space-l` is `Space.l`. Copy the numbers across. |
| `components.css` + `ui.js` | `Design/Components.swift` (+ small private views) | One block / one function per Swift type, named in a comment. |
| `screens.js` | `View/*.swift` | Each screen lists its Swift file and view. Copy is verbatim from Swift. |
| `ios-chrome.css` | nothing | Status bar, nav bar, tab bar, sheets, switches: iOS draws these itself. |
| `app.js`, `app.css` | nothing | The review harness. |

Type sizes are SwiftUI's text styles at the default Dynamic Type size
(`.largeTitle` 34, `.title3` 20, `.body` 17, `.footnote` 13, `.caption2` 11).
The wordmark uses Archivo at width 125 / weight 900 to stand in for
SF Pro Expanded Black.

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
