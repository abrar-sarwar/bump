# Swift port handoff: the site-style redesign

**Status (2026-09-26):** the HTML mockup's design (`ios-mockup/`) has been
ported into the SwiftUI app. **It has never been compiled by Xcode.** The
person who asked for it has no Mac. Everything below is what the next agent,
working on a Mac with **Xcode 26+**, needs to finish and verify.

Nothing is committed and nothing is pushed. The user said **do not push yet**.

---

## 1. What was done

The design language: the marketing site (`web/`) with the brand kept exactly.
That means the wordmark **artwork** (never set in a font), Archivo type,
sentence case, the site's MD3 colours, frosted cards, glossy orbs, pill rows,
chat bubbles, and the morphing "you both share this" badge. The full design
rules and the directions the user rejected are in `.agents/31-ios-mockup.md`
(git-ignored and local to the original machine; if it's missing, use
`ios-mockup/README.md`).

### Changed files (all under `ios/`)

| File | What changed |
|---|---|
| `UWBBumpTest/Design/Theme.swift` | Rewritten. Same names (`BumpColor.navy`, `Space.l`, `BumpFont.body` …), repointed at the site's values. Adds MD3 roles, `Archivo` PostScript names, `BumpFont.captionEmphasis/captionMedium/eyebrow/display`, `Tracking`, `BumpMotion`. |
| `UWBBumpTest/Design/Components.swift` | Rewritten. **Old signatures kept** (`Wordmark`, `BumpField`, `InterestChip`, `FlowLayout`, `Card`, `StatusPill`, `Avatar`, `PhonesIllustration`, `Screen`, `SectionHeading`, button styles). New: `FrostedBackground`, `.frostedCard()`, `.frostedCapsule()`, `TonalButtonStyle`/`.bumpTonal`, `TrailingIconLabel`, `SquareIconButton`, `Eyebrow`, `ScreenTitle`, `Wash`, `Bento`, `Orb`, `IconOrb`, `RowPill`, `RowText`, `PillTabs`, `BubbleShape`, `BubbleBody`, `ChatBubble`, `FloaterLine`, `Floater`, `.floaters()`, `Toast`, `ScallopShape`, `BlendedScallop`, `MorphingBlob`, `SharedBadge`, `Backdrop`, `SegmentedProgress`, `BumpCheckbox`. |
| `UWBBumpTest/Design/ScallopGeometry.swift` | **New.** Foundation-only shape maths (the site's `scallop()` formula), badge morph phase, rotation and interest cycling. Badge loop = 23 s (0.4x the site's). |
| `UWBBumpTest/View/*.swift` | Restyled: Welcome, OnboardingFlow, BumpTutorial, BumpScreen, ConfirmPartnerView, RevealView, TalkingPointsSection, ConnectionsScreen, YouScreen, ProfileEditor, TopicBrowser, RootView. **Logic and model calls are unchanged**; only layout and styling moved. |
| `UWBBumpTest/View/RootView.swift` | System tab bar hidden (`.toolbar(.hidden, for: .tabBar)`); new `MainTab` enum and `FloatingTabBar` in a `.safeAreaInset(edge: .bottom)`. |
| `UWBBumpTest/Fonts/` | **New.** Archivo Regular/Medium/SemiBold/Bold/ExtraBold `.ttf` (fontsource static, latin subset) + `OFL.txt` licence. |
| `UWBBumpTest/Info.plist` | Added `UIAppFonts` listing the five `.ttf` files. |
| `UWBBumpTest/Assets.xcassets/Wordmark.imageset/` | **New.** The site's `wordmark.png`, template rendering. |
| `BumpTests/DesignTests.swift` | **New.** 11 tests for `ScallopGeometry`. |

The project uses **synchronized folders** (`objectVersion = 77`), so new files
are picked up with no `.pbxproj` edits.

## 2. What was verified (off a Mac)

- `swiftc -parse` on all 43 Swift files (app + tests): **0 diagnostics**. That
  proves syntax only, not types.
- `DesignTests` compiled and ran with swift-corelibs-xctest on Linux
  (Swift 6.2): **11 of 11 pass**, including a regression test that the badge
  morph never shrinks below either form.
- **NOT verified:** type checking of any SwiftUI code, the build, runtime
  rendering, the fonts, and the existing 100-test suite. A SwiftUI type-check
  harness (stand-in modules) was half built and then abandoned; see section 5.

## 3. Must do, in order

1. **Build** the `UWBBumpTest` scheme for an iOS 17+ simulator. Fix every
   compile error. The likeliest spots are in the files I rewrote, especially
   `Components.swift` (generic views with `@ViewBuilder` stored properties:
   `RowPill`, `Toast`, `MorphingBlob`, `ChatBubble`, `BubbleBody`, `Bento`) and
   the `RowPill { } content: { } trail: { }` call sites in the views.
2. **Run all tests (⌘U).** Expect the old 96 passing / 4 skipped, plus 11 new
   `DesignTests`. If `DesignTests` fails to build, check that
   `ScallopGeometry.swift` is in the app target.
3. **Check the fonts actually load.** The static files' PostScript names are
   odd: every face reports family "Archivo SemiBold", and the names are
   `ArchivoSemiBold-Regular`, `-Medium`, `-SemiBold`, `-Bold`, `-ExtraBold`
   (read from the files' `name` tables). `Theme.swift` uses exactly those
   names. If a name is wrong, SwiftUI **silently falls back to the system
   font**. Confirm with
   `UIFont.familyNames.forEach { print($0, UIFont.fontNames(forFamilyName: $0)) }`,
   then fix the constants in `enum Archivo`.
4. **Screenshot every screen and compare with the mockup.** Run the mockup
   with `python3 -m http.server 8000 -d ios-mockup` and open
   http://localhost:8000. The app's demo launch arguments cover most states:
   `xcrun simctl launch <sim> com.jaredberesford.uwbbumptest -BumpDemo <mode>`
   with `onboarding`, `onboardingintro`, `onboardingquestion`,
   `onboardingcard`, `tutorial`, `home`, `ready`, `confirm`, `reveal`,
   `timedout`, `ambiguous`, `unsupported`, `connections`, `you`, `tools`.

## 4. Known risks to check on device / simulator

- **Floating tab bar** (`RootView`): check it doesn't cover content and that
  scroll views end above it. Check that sheets and full-screen covers (reveal,
  tutorial) still show over it, and that the keyboard doesn't push it
  awkwardly. If `.safeAreaInset` on the `TabView` misbehaves, move the inset
  onto each tab's root instead.
- **`SharedBadge` / `MorphingBlob`** use `TimelineView(.animation)` and
  redraw a 180-point path every frame. Check CPU in Instruments. If it's heavy,
  lower `samples` in `ScallopGeometry.points` (it's 180) or pass
  `minimumInterval: 1/30`. Its `@State start` resets when the view is
  recreated. That's fine, but on the tutorial's last page `popIn` only fires
  the first time.
- **`Wordmark`** is template-rendered in `BumpColor.brand` (`#70AAF9`, the
  artwork's own ink). Check it's crisp at hero size (300 pt wide; the PNG is
  1371 px, so it's fine at 3x). The text fallback only appears if the asset
  is missing.
- **ConnectionsScreen** keeps a plain `List` (for swipe to delete) with
  frosted `RowPill` rows. Check `.listRowBackground(Color.clear)` and the
  insets look right, and that `onDelete` still deletes the right row. The
  `ForEach` iterates `store.connections.enumerated()`, so offsets match the
  store's indices.
- **CardStep rows:** the checkbox `Button` sits inside `RowPill`'s leading
  slot with `.padding(-8)`, and a `Menu` sits in the trailing slot. Check tap
  targets don't overlap.
- **`.weight(...)` on custom fonts:** the rewritten views use explicit faces
  (`captionEmphasis` and so on). Untouched files still use
  `BumpFont.caption.weight(.semibold)` (TestingToolsScreen) and
  `.caption2.weight(.semibold)` (PhotoPickerAvatar). For custom fonts `.weight`
  may not pick the right face. Swap in the explicit fonts if they look wrong.
- **Bundle resources:** the synchronized group also copies `Fonts/OFL.txt`
  and this `.md` into the app bundle. That's harmless, but you can add them to
  the target's membership exceptions (as `Info.plist` already is), or move this
  file out, once the port is done.
- **Icons are SF Symbols** (the mockup used Material Symbols). Each mapping is
  a plain `systemImage:` string. Check they all exist on iOS 17:
  `iphone.radiowaves.left.and.right`, `person.crop.circle.badge.checkmark`,
  `location.magnifyingglass`, `person.fill.questionmark`,
  `dot.radiowaves.left.and.right`, `hand.wave.fill`.

## 5. The type-check harness (optional; abandoned mid-way)

To type-check SwiftUI without a Mac, I built a Swift 6.2 Linux toolchain plus
hand-written **interface stubs** of SwiftUI, Combine, UIKit, PhotosUI,
CoreMotion, NearbyInteraction, MultipeerConnectivity and simd. They lived in a
session scratch directory, which is **not** in the repo and is probably gone.
The last blocker was trivial: the SwiftUI stub's `FocusState`,
`FocusState.Binding` and `AppStorage` property wrappers needed explicit
`public init`s. `IntroRecorder.swift` can never type-check on Linux (`@objc` /
`#selector`), so it needed an interface stand-in.

On a Mac this is moot. **Just build in Xcode.**

## 6. Not ported / left as is

- `TestingToolsScreen` wasn't restyled. It picks up the new components
  automatically; its segmented `Picker` is still the system one.
- The mockup's "Simulate a bump" link is mockup-only, not a feature.
- Mic-denied and recording-failed states were restyled in Swift (peach bento)
  but were never designed in the mockup. Review them.

## 7. House rules (from the user)

- **Do not push** until the user says so. When committing, stage only
  `ios/` (and `ios-mockup/` if it's part of the same change). **Never stage
  `web/`**; other people are editing it.
- Keep the brand: the wordmark is the artwork image, never a font. Sentence
  case, Archivo, drawn phones (not hand photos). No "Message them" feature
  (BUMP has no messaging).
- Copy stays verbatim from the existing Swift strings unless the user
  approves new copy. The only additions are "Step N of 4" eyebrows, the
  decorative bubble lines (verbatim from `web/src/components/HeroFloaters.tsx`)
  and the tutorial badge's example interests.
