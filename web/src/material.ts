/**
 * Google's Material Web components (@material/web), registered once. Used by
 * the hero (button, backdrop icons, foreground fragments); the sections below
 * the hero are folk-style and mostly use only md-icon.
 *
 * Each import is a side-effect registration of one custom element; import
 * exactly what the page renders. The components read our --md-sys-* tokens
 * from tokens.css directly, so they are themed by the same generated scheme
 * as the hand-built CSS with no extra wiring.
 *
 * Icons are Material Symbols Rounded, loaded from Google Fonts in index.html
 * as a SUBSET (icon_names=...). A new icon name must be added to that URL,
 * in alphabetical order, or it renders as its ligature text.
 */
import type React from 'react'
import '@material/web/button/filled-button.js'
import '@material/web/button/filled-tonal-button.js'
import '@material/web/button/text-button.js'
import '@material/web/checkbox/checkbox.js'
import '@material/web/elevation/elevation.js'
import '@material/web/icon/icon.js'

// React 19 moved the JSX namespace into the 'react' module, so the old
// `declare global { namespace JSX }` silently does nothing. See
// .agents/11-material-design.md. Attributes are passed through as-is, which
// is what lit expects (`trailing-icon=""`, `label="..."`, `href`, ...).
type MdElement = React.DetailedHTMLProps<React.HTMLAttributes<HTMLElement>, HTMLElement> & {
  [attribute: string]: unknown
}

declare module 'react' {
  namespace JSX {
    interface IntrinsicElements {
      'md-filled-button': MdElement
      'md-filled-tonal-button': MdElement
      'md-text-button': MdElement
      'md-elevation': MdElement
      'md-icon': MdElement
      'md-checkbox': MdElement
    }
  }
}
