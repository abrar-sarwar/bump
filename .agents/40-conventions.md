# Conventions — voice, copy, design, code

## Voice

Plain, concrete, slightly understated. Short sentences. The product's whole
pitch is *specificity*, so the writing should be specific too.

- Good: "Two strangers. One specific thing." / "Three moves. About four seconds."
- Bad: "Revolutionising how humans connect." / "Seamlessly leverage proximity."

Never oversell. The README says "Unproven on two physical phones" in bold. Match
that honesty in marketing copy: claim only what is true today.

## Copy rules (enforced)

1. **No em dashes anywhere in shipped web copy.** Headings, body, buttons,
   `<title>`, `alt`, and `.sr-only` text included. Rewrite with periods, commas
   or colons. Do not swap in en dashes either. `scripts/verify-reveal.mjs` fails
   if one reaches rendered copy.
2. **Only real destinations.** In-page anchors (`#the-idea`, `#how-it-works`,
   `#the-overlap`, `#top`, `#main`) and `https://github.com/abrar-sarwar/bump`.
   No App Store badge, no waitlist form, no "coming soon" link that goes nowhere.
3. **Fictional example data must be labelled fictional** and must be internally
   consistent (see the `VALID` guard in `SharedInterestsPreview.tsx`).
4. Curly apostrophes are used in body copy (`person’s`, `What’s`). Stay
   consistent with the surrounding file.

## Design rules

- **Tokens or nothing.** New colours, sizes and spacing go in
  `src/styles/tokens.css`. No hex literals in component CSS except the handful
  of intentional one-offs already there (button hovers, chip grey, rgba tints).
- `--orange` comes from the phone photograph. **It is not UI chrome.** Do not
  use it for buttons, links or text.
- `--blue` is for large shapes and the CTA panel. `--blue-ink` is the one that
  passes AA on ivory, so it is what buttons and links use.
- Fluid everything: `clamp()` for type and space, never a fixed px ladder.
- **One breakpoint that matters: 860px.** A minor one at 560px. Add a third only
  with a reason recorded in `50-decisions.md`.
- Desktop and mobile hero are **different compositions**, not one scaled.

## Motion rules

- GSAP + ScrollTrigger only. No second animation library.
- Never hijack the wheel. Never snap. Scroll position is the only driver.
- Every beat is a tween on a **scrubbed** timeline, which is what makes
  scroll-up reverse exactly. Keep it that way.
- Animate **transforms and clip-path only**. Never width/height/top/left during
  a timeline.
- `prefers-reduced-motion: reduce` must produce a complete, readable, static
  page. Every hero change gets checked in this mode.

## Accessibility bar

Currently met. Treat as a floor, not a target.

- Real heading hierarchy; artwork is decorative (`alt=""`, `aria-hidden`) with
  `.sr-only` text carrying the meaning.
- Skip link. Visible `:focus-visible` ring everywhere, recoloured to white on
  the blue CTA panel.
- Interactive things are real `<button>` / `<a>`, with `aria-pressed` and
  `aria-live` where state changes silently.
- No horizontal overflow at any viewport size. No console errors.

## Code style

- TypeScript, function components, no default-export barrels.
- CSS lives in a file next to the component that owns it and is imported by it.
  Shared section styles go in `sections.css`, global primitives in `global.css`.
- BEM-ish class names: `block__element--modifier` (`hero__phone--blue`).
- Comments explain **why**, especially where a number was measured rather than
  chosen. The hero is full of these. Preserve them; they are the reason the
  animation can be safely retuned.
- Backend is **zero-dependency on purpose.** Do not add an npm package to
  `backend/` without a recorded decision.
