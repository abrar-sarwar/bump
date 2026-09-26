# web/ — the BUMP marketing site

React 19 + TypeScript + Vite 7. **GSAP + ScrollTrigger is the only animation
library.** No WebGL, no Tailwind, no CSS-in-JS. **Components are Google's
Material Web (`@material/web`)**, registered in `src/material.ts`; everything
else is plain CSS files imported by the component that owns them.

```bash
cd web && npm run dev     # http://localhost:5173
```

## File map

```
web/
├── index.html                   fonts, meta, theme-color, favicon
├── vite.config.ts               react plugin, port 5173
├── src/
│   ├── main.tsx                 createRoot + StrictMode + global.css + material
│   ├── material.ts              registers the md-* elements + their JSX types
│   ├── App.tsx                  section order lives here
│   ├── styles/
│   │   ├── tokens.css           ← ALL colour / type / space tokens
│   │   └── global.css           reset, body, headings, .btn, .eyebrow, .sr-only
│   ├── assets/wordmark.png      1371×219 Horizon artwork, generated (see caveat)
│   └── components/
│       ├── SiteHeader.tsx/.css  fixed-ish absolute header, skip link, 3 anchors
│       ├── BumpHero.tsx/.css    ← the pinned GSAP scroll sequence
│       ├── HeroBackdrop.tsx/.css  faint dot grid + MD3 shapes + glyphs behind the hero
│       ├── IntroSection.tsx     #the-idea
│       ├── HowItWorks.tsx       #how-it-works, 3 steps from a STEPS array
│       ├── SharedInterestsPreview.tsx  #the-overlap, interactive example switcher
│       ├── Principles.tsx       #whats-inside, six sourced claim cards + status line
│       ├── ClosingCTA.tsx       blue panel, wordmark, two real links
│       ├── SiteFooter.tsx
│       ├── BackToTop.tsx/.css   md-fab, shown once the hero leaves the viewport
│       └── sections.css         ← every section below the hero (338 lines)
├── public/assets/               phone-blue/orange .png + @1600 variants
├── public/favicon.svg
├── assets-source/               UNTOUCHED originals + extract.py
└── scripts/                     shots.mjs · robustness.mjs · verify-reveal.mjs
```

Page order (`App.tsx`): Header → Hero → Intro → HowItWorks → Overlap →
Principles → CTA → Footer, plus the BackToTop FAB.

## Design tokens (`src/styles/tokens.css`)

Sampled from the brand artwork, **not guessed**. Do not introduce a new colour
without a reason recorded in `50-decisions.md`.

| Token | Value | Use |
|---|---|---|
| `--ivory` | `#fff9f0` | page background |
| `--ivory-deep` | `#f7efe2` | the steps section band |
| `--blue` | `#73a9f5` | brand blue: wordmark, large shapes, the CTA panel |
| `--blue-ink` | `#2f6fd0` | AA-contrast blue for buttons and links on ivory |
| `--navy` | `#183555` | primary text |
| `--navy-soft` | `#5a7290` | secondary text, ~4.9:1 on ivory |
| `--hairline` | `#e6ddcd` | rules and borders |
| `--orange` | `#f0955a` | **from the phone photo only. Never UI chrome.** |

Layout: `--shell` = `min(1280px, 100% - 2*gutter)`, `--gutter` = `clamp(20px, 5vw, 64px)`.
Type scale: `--step-0` … `--step-4`, all fluid `clamp()`.
Space: `--space-s/m/l/xl` plus `--space-section` = `clamp(96px, 14vw, 200px)`.
Shape/motion: `--radius: 14px`, `--ease: cubic-bezier(0.22, 0.61, 0.36, 1)`.

**Headings** are Archivo (Google Fonts, variable weight 400..900 + width 75..125),
`font-weight: 800`, `line-height: 1.02`, `letter-spacing: -0.025em`. Archivo is a
stand-in chosen to sit close to the real **Horizon** brand face, which is not
licensed here. If Horizon `.woff2` files ever arrive, drop them in and swap a
`--font-display` stack.

## The breakpoint

**860px** is the one real breakpoint (`max-width: 860px` = "mobile"). A second
one at **560px** tightens the header nav and collapses the step grid.
1700px+ caps hero artwork so photographs do not stretch on ultrawide.

Desktop and mobile hero are **separate compositions, not one scaled down**.

## The hero scroll sequence — read before editing `BumpHero.tsx`

One pinned scene, one scrubbed GSAP timeline. Normal scrolling drives it.
Nothing hijacks the wheel, nothing snaps, and it reverses exactly on scroll-up
because every beat is a tween on a scrubbed timeline.

**Beats** — `STAGE`, as a fraction of section scroll:

| key | value | what |
|---|---|---|
| `cueOut` | 0.08 | "Scroll to bump" fades |
| `approachIn` | 0.12 | phones start closing |
| `contact` | 0.40 | edges meet, the contact mark blooms |
| `recoilOut` | 0.496 | recoil settles |
| `revealIn` | 0.528 | wordmark opens out of the meeting point |
| `settled` | 0.912 | composition holds before release |

**Scroll length**: 400vh desktop, 300vh mobile (2nd arg to `build(...)`).
Raised from 320/240 on 2026-09-26 so the reveal could be slowed without
touching the bump: beats up to `revealIn` were scaled by 0.8 so they sit at the
same absolute scroll distance, and the reveal got 2x the scroll (~135vh desktop).
**If you change a scroll length, rescale STAGE, and HERO_VH + the BEATS in
`scripts/verify-reveal.mjs`.**

### Five things that will break if you are careless

1. **`tl.set({}, {}, 1)` at the end of the timeline is load-bearing.** The STAGE
   numbers are fractions of the whole scroll, so the timeline must be exactly 1
   unit long. Delete that line and the timeline ends at `settled` (0.90), every
   beat lands ~10% late, and the reveal never finishes.
2. **The hero wordmark must not exist on screen before the phones bump.** It
   starts `clip-path: inset(0% 50% 0% 50%)` — a zero-width sliver at the exact
   meeting point — and `revealIn` opens the mask outward, so the word *grows
   from the contact point*. The closed state is set in **`BumpHero.css` as well
   as JS**, so it can never flash before GSAP initialises. Keep both.
3. **Mask, never `scaleX`.** Masking keeps the letterforms undistorted at every
   frame. `markFrom` (0.9 / 0.92) is a *uniform* scale kept near 1 for the same
   reason.
4. **The phone images are photographs, so the phone body is not centred in its
   own image.** Measured from the source art: the **blue** phone case spans
   63.8%–99.8% of its image width (leading edge = right); the **orange** spans
   ~0.2%–48% (leading edge = left). This is why the numbers are asymmetric and
   why `transform-origin` differs (20% / 80%). Do not "fix" the asymmetry.
5. **Transforms only during the timeline.** Never animate width/height/top/left.
   Viewport units are resolved to pixels inside `build()` and recomputed on
   refresh via `invalidateOnRefresh: true`.

### Desktop vs mobile composition

| knob | DESKTOP | MOBILE |
|---|---|---|
| phone width (CSS) | **60vw** | 82vw |
| `restOffset` (% of own width off-screen) | **43.3** | 34 |
| `travel` (inward, vw on x / vh on y) | 19.3 | 7.4 |
| `drift` | 0 | 2.5 |
| `axis` | `x` | `y` |
| `partX` / `partY` | 15 / **50** | 19 / 31 |
| `markReveal` (vw) | 76 | 90 |
| `markFrom` | 0.9 | 0.92 |

**Desktop phones are 60vw so the cropped wrist never shows** (it was 46vw and
the cut wrist sat ~7vw inside each edge at contact). The image's wrist edge is
at `-restOffset% * width + travel` = -26vw at rest and -6.7vw at contact.
restOffset was re-derived so the leading phone edges land exactly where they did
at 46vw (blue rests at 33.9vw, meets at 53.2vw). **Change width and restOffset
together, or the contact point moves.** Phones are no longer capped on
ultrawide for the same reason; only the wordmark is.

The wordmark is centred with GSAP `xPercent: -50` and an explicit `x: 0`.
GSAP folds the CSS `translate: -50%` into a pixel `x` measured at the CSS
width (92vw), which after the resize to `markReveal` left it ~115px off centre.
That bug predated MD3 and is fixed; do not drop the `x: 0`.

**Foreground UI fragments** (`HeroFloaters.tsx`, desktop only, hidden on
mobile and in reduced motion): real md components, inert and aria-hidden, each
a moment from the app (Ready to bump switch, Maya profile card, "Did you bump
with Dev?", Start bumping FAB). Each rises by its `data-depth` vh across the
whole pin (8 / 18 / 14 / 22). The bottom two are capped so they settle just
under the wordmark; raise their depth and they land on the B and the P.

The backdrop gets a slow parallax on the same scrubbed timeline (layer drifts
up 7vh, shapes turn by index). Transforms only, so it obeys the motion rules.

Desktop `partY` is 50 (was 31) so the phones finish below the wordmark
instead of covering the bottom of B and P.

Desktop has room for a side-by-side meeting near centre. Mobile does not: at
82vw each the phones already overlap horizontally, so they close along **y** —
blue descends from upper-left, orange rises from lower-right, meeting corner to
corner. During the reveal they part back along that same axis so the tagline and
CTA get a clean band between them.

Reveal order (changed 2026-09-26): the wordmark mask and the phones parting
are **one motion**: same start (`revealIn + 12%` of the reveal span), same
duration (88%), same ease (`power1.inOut`), via `partAt` / `partFor` /
`partEase`. The word's edges stay tucked behind the phones as they pull apart.
Keep the three shared; giving the mask its own ease makes it race ahead again.
Supporting line and CTA follow at `+60%`, landing on `settled`.

### Reduced motion

`prefers-reduced-motion: reduce` **skips the timeline entirely** — no pin, no
scrub, `useLayoutEffect` returns early. The hero becomes a static stacked
composition in normal flow with the wordmark, both phones, tagline and CTA all
present and readable (see the media block at the bottom of `BumpHero.css`).
**Any hero change must be checked in this mode too.**

### Why `imagesReady`

The effect waits for both phone images (`onLoad`/`onError` both count) before
measuring, so ScrollTrigger never pins against a layout about to shift.
`document.fonts?.ready.then(() => ScrollTrigger.refresh())` handles the same
problem for text metrics. `ctx.revert()` on cleanup also undoes the pin, which
is what makes it safe across StrictMode double-mounts.

## The sections below the hero

All in `sections.css`. `.section` is just `padding-block: var(--space-section)`.

- **Intro** (`#the-idea`) — 7fr/5fr grid, `align-items: end`, collapses to one
  column at 860. `.intro__aside` has a 2px `--blue` left rule.
- **HowItWorks** (`#how-it-works`) — `--ivory-deep` band. An `<ol>` with hairline
  top and per-item bottom borders. Big `--blue` step numbers at `font-stretch:
  112%`. Content column capped at `62ch`. Single column under 560px.
  Copy lives in the `STEPS` array at the top of the file.
- **SharedInterestsPreview** (`#the-overlap`) — 5fr/6fr grid. White `.person`
  cards, chips, the shared chip inverted to `--blue-ink`. Dot switcher is real
  `<button aria-pressed>`, and `.overlap__shared` is `aria-live="polite"` so
  switching examples is announced. **`EXAMPLES` is the single source of truth
  for both the highlighted interest and the opener, so they cannot drift.**
  `VALID` filters out any example whose `shared` is missing from either profile.
- **Principles** (`#whats-inside`) — surface-container-low band, MD3 outlined
  cards with icons in tonal containers cycling primary/secondary/tertiary, and a
  "Where it stands" status line. **Every card is a claim about the app; each
  must be sourced from the READMEs.** The status numbers (96 of 100, unproven
  on two phones) must be updated if the iOS status changes.
- **ClosingCTA** — full primary panel, white text. md-filled / md-outlined
  buttons and three md-assist-chips to the repo's ios/backend/web folders. The wordmark PNG is recoloured
  to ivory with `filter: brightness(0) invert(1) opacity(0.96)`. Focus rings go
  white inside this panel.
- **Footer** — hairline top, note left, links right.

## Accessibility bar already met — keep it

- Real `<h1 class="sr-only">` in the hero; the wordmark artwork is `aria-hidden`
  decorative (`alt=""`) everywhere, with an `.sr-only` label in `Wordmark.tsx`.
- Skip link, `:focus-visible` 3px `--blue-ink` outline with offset.
- `overflow-x: clip` on body. **No horizontal overflow at any size** is a
  verified property, not an aspiration.
- No console errors at any size. Also verified.

## Verification scripts

Need a running server and the installed Google Chrome (Playwright).

```bash
npm run preview &
node scripts/shots.mjs http://localhost:4173        # captures every beat -> shots/
node scripts/robustness.mjs http://localhost:4173   # behavioural checks
node scripts/verify-reveal.mjs http://localhost:4173
```

`verify-reveal.mjs` asserts the wordmark timing **numerically** on both
breakpoints: unmasked fraction is 0.000 at load, approach, pre-contact, contact
and recoil; ~0.13 mid-reveal (0.66) and ~0.78 at reveal (0.80); 1.000 when settled; back to 0.000 after scrolling
up past the reveal. It also **fails if any em dash reaches rendered copy.**

Already verified once: all beats both breakpoints · all four sections ·
reduced-motion full page · pin length recomputed across resize and the 860px
boundary (3780 → 2940 → 2720 → 3780) · scroll-to-top restores the rest pose ·
fast-scroll burst · all three anchors land · reload partway down · no dead links.

## Known limitations (documented, not bugs to "fix" blindly)

- Contact is tuned by eye against the silhouettes at 1440×900 and 390×844.
  Other aspect ratios land close but not pixel-perfect. `travel` is the knob.
- Reloading partway down returns to the top rather than restoring position.
  **Deliberate** — restored mid-pin scroll is the usual source of broken pins.
- 700–860px uses the mobile composition at a width where desktop would also
  work. The breakpoint is a judgement call, not a measurement.
- `wordmark.png` is **1371×219**, crisp to ~1370 CSS px. It is displayed up to
  92vw with an ultrawide cap of 1560px, so **it is already upscaled on wide
  displays.** The artwork before 2026-09-26 was 1875px wide, so this is a
  resolution step down: the supplied source (1627×763) has less pixel data in
  the letters. **An SVG export is the single highest-value asset fix available.**

## The wordmark pipeline

`assets-source/wordmark.source.png` (the untouched original) ->
`node scripts/extract-wordmark.mjs` -> `src/assets/wordmark.png`.

**`assets-source/extract.py` does NOT produce the committed wordmark**, despite
having a line for it. It writes 2400px into `public/assets/` with hard alpha;
the real asset is in `src/assets/` with anti-aliased alpha. That drift predates
2026-09-26. `extract.py` also needs Pillow, which **cannot be installed on this
machine** (no root, and `python3 -m venv` needs `python3-venv` via apt), so the
wordmark generator was written in Node instead and needs nothing but Node.

How the keying works: the source is two flat colours, so for every edge pixel
`pixel = alpha * INK + (1 - alpha) * GROUND`, and alpha is recovered by
projecting `(pixel - GROUND)` onto `(INK - GROUND)`. That gives smooth edges
rather than a threshold's stair-steps, which matters at 92vw. Output RGB is the
pure ink everywhere, so the CTA panel can still invert it to ivory. Neither
colour is hardcoded: GROUND is sampled from a corner, INK is the most common
non-ground colour.

**The tight crop is load-bearing.** The hero reveals the wordmark with a
centre-out `clip-path` mask, so any padding baked into the image would offset
the reveal from the point where the phones actually meet.

## Open wants

1. **A vector or higher-resolution wordmark** (see the ceiling above).
2. **The Horizon webfont.** The logo typeface is confirmed as Horizon. The logo
   itself is artwork so it is pixel-accurate without the font, but headings are
   still Archivo. Drop licensed `.woff2` files in and point
   `--md-ref-typeface-brand` at them.
3. **Real product screenshots** from the iOS app for HowItWorks and the overlap
   section, which currently use typography and example data instead.

## Current page, 2026-09-26 (supersedes the section notes above where they differ)

Order: Header (folk pill nav) → Hero (MD3, unchanged motion) → IntroSection
(#the-idea, scroll-revealed statement) → Moments (#made-for, 8 relatable
pill rows, labelled examples) → HowItWorks (bump, confirm, connect; 3 short
cards) → SharedInterestsPreview (pill tabs, folk cards, chat-bubble bento;
EXAMPLES / VALID unchanged) → WalkBy (#walk-by, in-the-works feature) →
Principles (#whats-inside, pastel bento) → ClosingCTA (solid MD3 primary,
huge white wordmark, minimal) → Footer (folk columns, no giant logo) →
BackToTop (dark folk button).

- Styles for all of the above: `sections.css` (rewritten), tokens `--folk-*`.
- **Intro word reveal needs `refreshPriority: -1`.** Its trigger is created
  before the hero's pin (hero waits for images) but sits below it, so without
  it the trigger measures the page without the 3600px pin spacer and the
  reveal finishes before you ever see it. Hero also calls
  `ScrollTrigger.refresh()` after building.
- Hero fragments (`HeroFloaters.tsx`): 6, scattered, each `data-side`. They
  slide off sideways starting at `cueOut*0.5`, at the reveal's own
  duration/ease (`partFor`/`partEase`, now declared once at the top of
  `build()`). Scaled 10% on the INNER element; the outer one is GSAP's.
- Icon font subset now also has biotech, celebration, directions_walk, home,
  lock, music_note, restaurant, school, terminal, work.

## Hero timing, 2026-09-26 (supersedes the STAGE table above)

`cueOut 0.08 · approachIn 0.035 · contact 0.40 · revealIn 0.412 · settled
0.912`, scrub 0.9. **Everything is linear** and there is no recoil and no
dead zone: the phones close, touch for 0.012, and part. Measured at 1440x900:
~33px of phone movement per 144px scrolled, in AND out. The old power1.in
approach + eased recoil + ~400px hold + power1.inOut parting made it crawl
at the bump and rush away. If you add an ease or a gap, re-measure.
verify-reveal beats retimed (touch 0.405 hidden, mid 0.60, reveal 0.80) and
it waits 1400ms per beat because of the longer scrub.

## Section shapes (`Shapes.tsx`)
Every folk section renders `<Shapes set={SHAPES} />` first: outline or very
faint MD3 shapes (cookie, clover, sunny, flower, circle, pill) in its margins,
scrubbed drift + turn, refreshPriority -1. No icons or tonal badges (the
human removed those). `mobile: true` keeps a shape under 860px. Generator in
`src/shapes.ts`, shared with HeroBackdrop.
