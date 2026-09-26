# Material Design 3 — the primary design language for `web/`

Decided 2026-09-26. MD3 is the design language for the marketing site.
This file records **what is installed, what is true about it, and the traps.**

## What Google actually ships (researched, not assumed)

| Package | Version | What it is | Status |
|---|---|---|---|
| `@material/web` | **2.5.0** | Google's own MD3 components. Lit web components, Apache-2.0. | **Maintenance mode, pending new maintainers.** Stable and complete at 1.0+; every component was reviewed by M3 designers and a11y engineers. Not abandoned, not advancing. |
| `@material/material-color-utilities` | **0.4.0** | Google's official MD3 colour algorithms: HCT colour space, tonal palettes, scheme generation from a seed. This is what *generates* the `--md-sys-color-*` values. | Fine. The real workhorse for us. |
| `material-symbols` | **0.47.5** | The Material Symbols variable icon fonts + CSS. | Fine, actively updated. |

All three installed in `web/`. **0 vulnerabilities, 11 packages added.**
`@material/web` pulls `lit`, `tslib`, `@lit/context`. ~11 MB on disk, tree-shakeable
(a filled button + icon bundles to ~136 KB before minify/gzip).

### Things to know before relying on this

- **M3 Expressive (2025/2026) is not implemented on web.** The new spring motion
  system, the 35 shapes, shape morphing, the 15 updated components: Android and
  Wear only. `@material/web` went into maintenance *before* Expressive landed.
  If someone asks for "the new bouncy Material", the official web answer is no.
  Community bridges exist (e.g. `md3e-frontend`); none are Google's.
- **MUI (`@mui/material` v9.4.0) is NOT Google's.** It is a separate company's
  React library that implements Material Design. Actively developed, far more
  popular in React, but it is an interpretation, not the reference. We chose
  Google's own. Do not silently swap one for the other.

## Traps, already hit and solved

### 1. `material-color-utilities` will not run under raw Node
Its ESM build uses extensionless internal imports, so `node script.mjs` dies with
`ERR_MODULE_NOT_FOUND .../dynamiccolor/dynamic_color`. **It works fine under a
bundler** (Vite, esbuild, webpack) because bundlers resolve extensionless paths.
To run a one-off script against it, bundle first:

```bash
npx esbuild probe.mjs --bundle --platform=node --format=esm --outfile=/tmp/out.mjs && node /tmp/out.mjs
```

### 2. React 19 + custom elements needs a JSX augmentation, and the old pattern is wrong
React 19 renders web components correctly at runtime (props, attributes, events),
but TypeScript does not know the tags exist. **React 19 moved the JSX namespace
into the `react` module**, so the old `declare global { namespace JSX {...} }`
silently does nothing. This is the pattern that works (verified, `tsc` clean):

```ts
import type { MdFilledButton } from '@material/web/button/filled-button.js'
type CE<T> = React.DetailedHTMLProps<React.HTMLAttributes<T>, T> & { slot?: string }
declare module 'react' {          // <- 'react', not global
  namespace JSX {
    interface IntrinsicElements {
      'md-filled-button': CE<MdFilledButton>
    }
  }
}
```

Alternative if we end up using many components: `@lit/react`'s `createComponent()`
generates real React wrappers with typed props and events. Worth it past ~5 components.

### 3. Imports are per-component side-effect registrations
`import '@material/web/button/filled-button.js'` registers the element. There is
no barrel import worth using. Import exactly what a file renders.

## Our seed colour and what MD3 derives from it

Seed = **`#73a9f5`**, the existing brand blue from `tokens.css`.
In HCT that is **hue 259.4, chroma 48.2, tone 68.5**.

Generated light scheme (29 roles total). Key ones:

```
--md-sys-color-primary:               #1e5fa6
--md-sys-color-on-primary:            #ffffff
--md-sys-color-primary-container:     #d4e3ff
--md-sys-color-on-primary-container:  #001c3a
--md-sys-color-secondary:             #555f71
--md-sys-color-tertiary:              #6e5676
--md-sys-color-surface:               #fdfcff
--md-sys-color-on-surface:            #1a1c1e
--md-sys-color-surface-variant:       #e0e2ec
--md-sys-color-on-surface-variant:    #43474e
--md-sys-color-outline:               #74777f
--md-sys-color-outline-variant:       #c3c6cf
```

Primary tonal palette: `10 #001c3a · 20 #00315f · 30 #004786 · 40 #1e5fa6 ·
50 #3f78c1 · 60 #5b92dd · 70 #77adf9 · 80 #a6c8ff · 90 #d4e3ff · 95 #ebf1ff`

### Two findings that matter

1. **The brand blue is almost exactly primary tone 70.** `#73a9f5` vs the
   generated `#77adf9`. The existing palette was already sitting on an MD3 tone
   step. That is a strong sign the seed is right.
2. **MD3 wants to throw away the ivory.** The algorithm derives neutrals from the
   seed hue, so it produces a cool blue-white surface `#fdfcff` where the brand
   uses warm ivory `#fff9f0`. Straight MD3 would make the site colder and lose
   the single most distinctive thing about its palette.
   **Fix:** MD3 supports overriding the neutral palette independently of the
   seed. Keep ivory as the surface family, let MD3 own primary/secondary/tertiary
   and the on-* contrast pairs. Do not just paste the generated scheme in.

## How this sits against the existing design

The site is not a blank slate. It has a bespoke photographic hero, a hand-tuned
GSAP scroll sequence, Archivo standing in for Horizon, and a warm ivory palette
sampled from brand artwork. See `10-web.md` and `50-decisions.md`.

MD3 as a **token system** (colour roles, type scale, shape scale, elevation,
state layers, motion easing) maps cleanly onto the existing `tokens.css` and
would restyle the whole page coherently.

**Update 2026-09-26: components ARE now used** (human asked to "add a bunch of
stuff from the Material kit"). What is on the page, and where:

| Element | Where |
|---|---|
| `md-filled-button` | hero CTA, closing CTA |
| `md-outlined-button` | closing CTA |
| `md-filled-tonal-button` / `md-icon-button` | header GitHub (desktop / 561 to 860px) |
| `md-filter-chip` in `md-chip-set` | overlap example switcher (replaced the dots) |
| `md-assist-chip` | closing CTA, links to repo folders |
| `md-elevation` | person cards (elevated card) |
| `md-fab` small | BackToTop |
| `md-icon` | everywhere, Material Symbols **Rounded** |

Gotchas found:
- **Icon font is a Google Fonts SUBSET** (`icon_names=` in `index.html`). The
  `material-symbols` npm package's woff2 is 4 to 5 MB, too heavy, so it is
  installed but unused. A new icon must be added to the URL, alphabetically,
  or it renders as its ligature text. `--md-icon-font` is set in tokens.css.
- **Filter chips toggle themselves.** Used as single-select, clicking the
  chosen chip deselects it behind React. The handler sets
  `currentTarget.selected = true` before `setIndex`.
- **Inverting roles on the primary panel:** you cannot set
  `--md-sys-color-primary: var(--md-sys-color-on-primary)` and the reverse on
  the same element; that is a custom-property cycle and both go invalid. The
  section captures `--cta-primary` / `--cta-on-primary` first, children swap.
- Boolean attributes like `trailing-icon` are passed as `trailing-icon=""`.
  Never pass `false` to an attribute-only prop: lit reads the string "false"
  as present, i.e. true.
- Bundle cost: JS 119 KB to 144 KB gzip.

MD3 as a **component library** buys less here: the entire landing page has two
buttons and three dot controls. The value arrives if the site grows real UI.

**The hero is out of scope for MD3 either way.** Its geometry is tuned against
photograph silhouettes and its motion is scrubbed to scroll position. MD3 motion
tokens are for component state transitions, not for a scroll-driven scene.

## The app mockup and MD3 (2026-09-26)

`ios-mockup/` briefly had a plain MD3 pass (Roboto Flex, MD3 components and
chrome); the human called it "super generic". It now follows the live site
instead: the same generated colour scheme as this file, the site's card
language, Archivo, the wordmark artwork. MD3 survives there as the colour
roles, Material Symbols, the switch/checkbox, and a "Material 3" chrome option
kept only for comparison. See `31-ios-mockup.md`.

An M3 Expressive direction was also explored on m3.material.io and dropped.
If it is ever revisited: `SchemeVibrant` from material-color-utilities keeps
the brand blue; `SchemeExpressive` swings primary to green.
