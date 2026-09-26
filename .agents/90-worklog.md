# Worklog

Append-only. Newest at the bottom. One entry per meaningful chunk of work.

Format:
```
## YYYY-MM-DD — <tool> — <area>
- what changed (files)
- anything the next agent needs to know
- anything left unfinished
```

---

## 2026-09-26 — Claude Code — setup
- Cloned `abrar-sarwar/bump` into `/mnt/c/Users/chara/Projects/Bump` at `142fb3c` on `main`.
  Confirmed `origin` reachable and WRITE access via `gh` (`CharanPeeriga`).
- Read the whole tree and wrote this `.agents/` folder. No product code touched.
- Added `.agents/` to the root `.gitignore`.
- Node in WSL is nvm `v24.19.0`; the bare `node` on PATH is the Windows one and
  does not resolve. Prefix with
  `export PATH="$HOME/.nvm/versions/node/v24.19.0/bin:$PATH"`.
- `cd web && npm install` completed clean. Started `npm run dev` on :5173.
- **Human's current task: front-end design of the landing page (`web/`).**

## 2026-09-26 — Claude Code — web: Material Design 3 adopted
- Researched Google's actual MD3 web offering. Installed in `web/`:
  `@material/web@2.5.0`, `@material/material-color-utilities@0.4.0`,
  `material-symbols@0.47.5`. Clean install, 0 vulnerabilities.
- Verified: bundles under Vite/esbuild; React 19 renders the elements; the
  TS JSX augmentation pattern that works is `declare module 'react'`, NOT
  `declare global`. Raw `node` cannot import material-color-utilities.
- Generated the MD3 scheme from seed `#73a9f5`. Brand blue turns out to be
  primary tone 70. MD3's derived neutral is a cool `#fdfcff`, which would
  replace the warm brand ivory: flagged, not applied.
- **No product code changed.** Only `web/package.json` + lockfile.
- Full detail and the traps: `.agents/11-material-design.md`.
- **Open: how deep MD3 goes (tokens only vs full component swap) is undecided.**

## 2026-09-26 — Claude Code — web: MD3 token system applied
Branch **`landing-page-design`**, commit `ad94f55`. **Not pushed.** `main` is
untouched at `142fb3c`.

Human's decisions: **tokens only** (no component swap), and **MD3 picks the
neutrals** (brand ivory dropped). Both recorded in `50-decisions.md`.

Changed:
- `src/styles/tokens.css` rewritten as an MD3 token system: 29 generated colour
  roles + the 2023 surface container ladder, typescale, shape scale, elevation,
  state layers, motion. Legacy names (`--ivory`, `--navy`, `--blue`, `--step-*`,
  `--radius`, `--ease`) are **removed, not aliased**, so nothing can quietly
  keep using the old palette.
- `src/styles/global.css`: body, links, focus ring, buttons on MD3 roles.
  Buttons are now MD3 proper: `corner-full`, `label-large`, and a **state layer**
  (`::before` with `currentColor` at spec opacity) instead of hardcoded hover
  colours, so one rule covers every variant.
- `src/components/*.css`: all four migrated. No hex or rgba literals remain
  outside `tokens.css`; translucent tints use `color-mix()` against MD3 roles.
- `index.html`: `theme-color` `#FFF9F0` -> `#fdfcff`.
- `scripts/gen-md3-tokens.mjs`: **new**, regenerates the roles from the seed.
  Verified to reproduce exactly what is committed.

Visible consequences:
- Page surface is cool `#fdfcff`, not warm ivory.
- The CTA panel is `--md-sys-color-primary` `#1e5fa6`, notably darker than the
  old `--blue` `#73a9f5`. Correct MD3, but the biggest single visual change.
- Buttons are pill-shaped (`corner-full`) rather than 14px rounded.

Verified: `npm run typecheck` clean, `npm run build` clean (46 modules,
18.17 kB CSS), both servers serving the MD3 CSS, zero em dashes in built output.

### Environment gotchas found the hard way
- `npx playwright install chromium --with-deps` **needs sudo and fails here.**
  It still exits 0 through a pipe, so it can look like it worked. Use
  `npx playwright install chromium` (no `--with-deps`), and check
  `~/.cache/ms-playwright/` is non-empty afterwards.
- The repo's `scripts/*.mjs` launch `chromium.launch({ channel: 'chrome' })`,
  i.e. a real Google Chrome at `/opt/google/chrome/chrome`, which is not
  installed in this WSL. Bundled Chromium does not satisfy `channel: 'chrome'`.
  To run those scripts here, either install Chrome or run a copy with the
  channel line dropped. **Do not edit the repo's scripts just to make them pass.**
- **Vite HMR over the `/mnt/c` 9p mount does not reliably fire.** An already-open
  browser tab can keep showing stale CSS while the server is serving the new
  file. Confirm what is actually being served with
  `curl -s localhost:5173/src/styles/tokens.css | grep md-sys-color`
  before believing a change did not land. Hard-reload the tab.

## 2026-09-26 — Claude Code — web: new Horizon wordmark
Human supplied new logo artwork and confirmed the typeface is **Horizon**.

- `assets-source/wordmark.source.png` replaced with the supplied original
  (1627×763, ivory ground `#fff9ef`, ink `#70aaf9`).
- `scripts/extract-wordmark.mjs` + `scripts/_png.mjs` **new**: a dependency-free
  Node PNG codec and wordmark keyer. Needed because Pillow cannot be installed
  here, so `extract.py` is unrunnable on this machine.
- `src/assets/wordmark.png` regenerated: **1371×219**, aspect 6.260:1
  (was 1875×311, 6.029:1), uniform ink with anti-aliased alpha, tight crop.
- **Re-seeded MD3 from the new ink `#70aaf9`** (was `#73a9f5`). Only 4 of 29
  roles moved and all imperceptibly (`primary #1e5fa6 -> #155fa9`), but
  `tokens.css` documents the seed as sampled from the wordmark, so leaving it
  stale would be exactly the drift that broke `extract.py`. Generator and
  `tokens.css` verified back in sync.
- `--brand-phone-blue` renamed `--brand-wordmark-ink`, which is what it actually
  was. Neither is referenced in CSS; they are documentation tokens.
- `web/README.md` asset table, regeneration commands and "still wanted" updated.

**Flagged, not fixed: the new artwork is LOWER resolution than what it replaced**
(1371px vs 1875px of ink). The hero caps at 1560px, so it now upscales on wide
displays. Asked the human for an SVG or a larger export.

Headings are still **Archivo**. Horizon font files were not supplied and a
licensed font cannot be downloaded, so `--md-ref-typeface-brand` is unchanged.

Verified: typecheck clean, build clean, new asset in the bundle (11.64 kB).

## 2026-09-26 — Claude Code — session close
Session ended here. State at close:

- Branch **`landing-page-design`** at `1d3d35b`, two commits ahead of `main`
  (`142fb3c`). **Nothing pushed.** Working tree clean.
- `git config user.name/user.email` were unset on this machine and are now set
  **repo-locally only** (not `--global`) to
  `Charan Tej Peeriga <charan.peeriga@gmail.com>`, taken from the GitHub account
  and the session. Change them in this repo if wrong; commits can be amended.
- Dev server (:5173) and preview server (:4173) were stopped at session close.
  Restart with `cd web && npm run dev` after the PATH export.

Installed into `web/` this session, all still present:
`@material/web@2.5.0`, `@material/material-color-utilities@0.4.0`,
`material-symbols@0.47.5`. **`@material/web` is currently unused** because MD3
was adopted as tokens only. It is kept for when the site grows real UI; drop it
if that never happens.

Also downloaded but **non-functional**: Playwright's bundled Chromium in
`~/.cache/ms-playwright/`. It cannot launch without apt packages that need root.
See the Environment section of `00-start-here.md`.

### What the next agent should pick up
1. **Verify the hero.** `scripts/verify-reveal.mjs` has not run since MD3 or the
   new wordmark. Needs the apt libs first. This is the only unverified change.
2. Chase the **SVG wordmark** and the **Horizon `.woff2` files**. Both are
   blocked on the human, both are recorded in `web/README.md` under Still wanted.
3. The visual consequences of MD3 were never reviewed by a human in a browser
   with a confirmed hard reload. The CTA panel going from `#73a9f5` to `#155fa9`
   is the biggest change and the most likely thing to get revisited.

### Unresolved question worth raising
MD3's algorithmic neutrals replaced the brand ivory on the human's explicit
instruction, and that is the most distinctive thing the old palette had. If the
page ever feels colder or more generic than intended, **that is the cause and it
is a one-file fix**: MD3 allows overriding the neutral palette independently of
the seed. See the decision entry in `50-decisions.md`.

## 2026-09-26 — Claude Code — web: zoomed hands, Material components, hero backdrop
Branch `landing-page-design`. **Uncommitted** at time of writing.

- Hero: desktop phones 46vw to 60vw, `restOffset` 26 to 43.3, so the wrist crop
  stays off-screen at every beat while the contact point is unchanged. Phone
  ultrawide cap removed. Fixed a pre-existing ~115px left offset of the revealed
  wordmark (GSAP baked CSS translate into px; now `x: 0, xPercent: -50`).
- New `HeroBackdrop` (dot grid, MD3 shapes, glyphs), parallax on the timeline.
- `@material/web` now used: see the table in `11-material-design.md`. New
  `Principles` section, `BackToTop` FAB, step icons, overlap filter chips,
  elevated person cards, opener as a primary-container card, CTA chips.
- `.btn` CSS removed from global.css. `material-symbols` npm package unused.
- **Verified in a real headless browser** (1440x900, 390x844, 1024x768, and
  reduced motion): no console errors, no horizontal overflow, no em dashes,
  wordmark centred, chips single-select correctly, and a copy of
  `verify-reveal.mjs` reports ALL CHECKS PASS on both breakpoints.
- How the browser was made to work without root: see `00-start-here.md`.

## 2026-09-26 — Claude Code — web: wordmark reveal synced to the phones
- Human: the logo came out too fast after the bump. The mask now shares the
  phones' start, duration and ease (`partAt/partFor/partEase` in BumpHero.tsx);
  measured word-open vs phones-parted equal to 2 decimals at every sample.
  Copy moved to start at +60% of the reveal span.
- `scripts/verify-reveal.mjs`: mid-reveal / reveal SAMPLE POINTS moved
  0.70/0.78 to 0.76/0.84 to follow the new timing. Assertions unchanged.
  ALL CHECKS PASS both breakpoints.

## 2026-09-26 — Claude Code — web: slower reveal, phones end lower
- Scroll 320/240vh to 400/300vh; STAGE rescaled so the bump is unchanged in
  absolute scroll and the reveal (wordmark + parting phones) is 2x slower.
- Desktop `partY` 31 to 50: phones settle below the wordmark.
- verify-reveal.mjs HERO_VH and BEATS rescaled to match. ALL CHECKS PASS.

## 2026-09-26 — Claude Code — web: foreground parallax UI; master doc captured
- `HeroFloaters.tsx/.css`: four inert Material fragments on the hero sides,
  parallax via the scrubbed timeline. Registered `md-switch`, `md-text-button`.
  Desktop only. verify-reveal still ALL CHECKS PASS.
- Read the human's Google Doc "hackgt 13 master doc" into `60-master-doc.md`.
  **Eight conflicts with the repo raised with the human, none acted on.**

## 2026-09-26 — Claude Code — web: folk-style redesign below the hero
- Crawled folk.com with headless Chromium, measured tokens, rebuilt every
  section below the hero (see 10-web.md "Current page"). Iterated live with
  the human: statement 4 lines, steps simplified, closing back to solid blue
  with a huge logo (no glow, no gradient), footer giant logo removed, section
  rhythm -35%, principle cards tightened.
- Hero fragments: scattered and relatable, 2 removed, checkbox not switch,
  slide off sideways at the reveal's speed, +10% size.
- Added Moments and WalkBy sections. Removed md chips/fab/switch/icon-button
  /outlined-button registrations (unused).
- Verified: typecheck, build, verify-reveal ALL CHECKS PASS, no console errors,
  no overflow, no em dashes, reduced motion, pill switcher single-select.
- **Master doc questions 2 to 8 still open with the human.**

## 2026-09-26 — Claude Code — git
- Committed `5bf01bf` and pushed `landing-page-design` to origin (new remote branch, 3 commits ahead of main). No PR opened.

## 2026-09-26 — Claude Code — web: How it works decoration
- MD3 shape badges (clover, cookie) + faint outlines in the section margins, scrubbed drift (refreshPriority -1); arrow orbs between step cards (CSS ::after with the icon ligature). Shape generator moved to `src/shapes.ts`, shared with HeroBackdrop. Uncommitted.

## 2026-09-26 — Claude Code — web: constant-speed hero; shapes site-wide
- Hero timeline all linear, no recoil/hold; approach starts at 0.035 so in
  and out speeds match (measured). verify-reveal retimed, ALL CHECKS PASS.
- Badges removed; `Shapes` component adds margin shapes to all six folk
  sections. Uncommitted at time of writing.
- Removed the "where it stands" status line from Principles (human asked).
- Committed `6124dc3` "scrolling speed fixes + parallax background assets throughout site" and pushed.

## 2026-09-26 — Claude Code — ios-mockup: HTML stand-in for the iOS app
- Built `ios-mockup/` (new, untracked): 38 screens/states transcribed from
  every SwiftUI view, copy verbatim, fixtures from PreviewFixtures.swift.
  Clickable prototype + all-screens grid, iOS 26 / iOS 18 chrome toggle,
  `#screen-id` deep links. `tokens.css` = Theme.swift 1:1.
- Verified in headless Chromium: all screens render, no console errors,
  click-through and text input work.
- Not modelled: Testing tools screen, mic-denied / recording-failed cards,
  alerts and menus on the card step. Nothing committed.
- Committed `32de3f3` on new branch `ios-mockup-vis-charan` (from landing-page-design) and pushed to origin. No PR.

## 2026-09-26 — Claude Code — ios-mockup: Material 3 first pass
- Human asked for a first MD3 pass over every mockup page ("a lot of changes
  will be made"). Colour = web's generated scheme (seed #70aaf9); BumpColor
  names repointed at MD3 roles. MD3 typescale (Archivo headlines, Roboto Flex
  body). Components rebuilt to MD3 spec from tokens, NOT @material/web (no
  SwiftUI counterpart). Material Symbols subset. New default chrome "Material 3"
  (top app bar, nav bar, bottom sheet) beside the iOS 26/18 options.
- Gutter 20 -> 16 (MD3 compact margin). Surface is MD3 cool white, matching web.
- Verified: all screens render, no console errors, controls work, all icons resolve.

## 2026-09-26 — Claude Code — ios-mockup: restyled after the live site
- Human steered: M3 Expressive direction dropped; then "too far into folk";
  final rule: KEEP THE BRAND (wordmark ARTWORK, never a font), take heavy
  inspiration from web/ (read-only). Tokens = web's MD3 scheme + --folk-* card
  language; Archivo, sentence case (no lowercase, no rounded face).
- Every screen rewritten: backdrop, frosted cards, orbs, pill rows, bubbles +
  hero floaters (verbatim lines), questions as a chat, opener as your bubble.
- Human asked: drawn phones, not the hand photos; tutorial "see what you
  share" = the morphing badge alone, popping up and cycling interests, morph
  at 0.4x the site's speed (23s). No "message them" (human rejected it).
- web/'s wordmark.png copied into ios-mockup/assets. Not committed.
- Tutorial badge fixes (human): bigger (300px), centred with the title pushed
  down above the dots, interests vertically centred. Morph shrank mid-way
  because the turn was baked into the polygons (points cut chords); now the
  morph has no rotation and a separate `rotate` animation turns it, with
  shallower lobes (5/.1, 9/.07, 4/.14, 7/.08). A stray black line the human
  saw under the badge could NOT be reproduced in headless Chromium.

## 2026-09-26 — Claude Code — context written up
- Researched "can I preview iOS without a Mac" and Mac rentals (Scaleway /
  MacinCloud / AWS); human chose the free HTML route. Findings kept in
  31-ios-mockup.md so nobody re-researches them.
- Explored m3.material.io (M3 Expressive: shape library, shape morph, wavy
  progress, button groups, floating toolbar). Direction abandoned by the human.
- New area file `31-ios-mockup.md` holds the full state; 00-start-here, 30-ios,
  README (index) and 50-decisions updated to point at it.
- Mockup preview server: `python3 -m http.server 8000 -d ios-mockup` (a
  session-scoped background one was running on :8000).
- Still uncommitted: all mockup work after `32de3f3`.

## 2026-09-26 — Claude Code — Swift port of the mockup (UNBUILT)
- Ported ios-mockup's design into ios/ (Theme, Components rewritten with old
  signatures kept; new ScallopGeometry.swift; 12 views restyled, logic
  untouched; Archivo fonts + UIAppFonts; Wordmark imageset; floating tab bar).
- Verified off-Mac only: swiftc -parse on all 43 files clean; DesignTests
  11/11 pass on Linux (Swift 6.2 toolchain in ~/.local/swift, sysroot in
  ~/.local/lib/swift-sysroot, ncurses in ~/.local/lib/swift-deps).
- SwiftUI type-check harness abandoned at the human's request. Handoff for a
  Mac agent: ios/UWBBumpTest/SWIFT_PORT_HANDOFF.md. Not committed, not pushed.
- Committed `a38909d` (mockup restyle + unbuilt Swift port + handoff) and pushed `ios-mockup-vis-charan`. web/ changes left unstaged.

## 2026-09-26 — Codex — main merge and agent notes
- Fetched current `origin/main` (`b461240`). A direct merge had 16 conflicts
  in `.gitignore` and SwiftUI files. Restarted the merge with this branch's
  conflicting design hunks, kept its site-style SwiftUI views, and integrated
  main's automatic bump, relay, StreetPass, Live Activity and notifications.
- Preserved the four pre-existing uncommitted web changes. The merge remains
  local and uncommitted pending its final git step. The Swift files parse on
  Linux; an Xcode build and two-phone check are still required. Backend local
  tests pass, 47/47.
- Folded the added `agents.md` Mac server and Cloudflare quick-tunnel notes into
  `20-backend.md` and `30-ios.md`; removed that duplicate file. The current
  Debug and Release `BUMP_API_BASE_URL` values remain `http://localhost:8787`.
