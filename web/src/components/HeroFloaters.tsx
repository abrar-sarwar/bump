import type React from 'react'
import { ConfirmCard, RevealRow, StatusPill, WaveCard, WaveNotice } from './AppUI'
import './HeroFloaters.css'

/**
 * Foreground fragments on the hero: real screens from the app, in order of
 * the flow. Wave tells you someone walked by, you're ready, you bump,
 * confirm, and see what you share. All copy is the app's own (see AppUI.tsx).
 *
 * Decoration only: the layer is aria-hidden and inert.
 *
 * Placement is irregular (no two share a line) and clear of the point where
 * the phones meet. Motion: as the phones close in, BumpHero slides each one
 * sideways off the edge it sits nearest (data-side), turning a little
 * (data-turn). Scrubbed, so they return on scroll-up.
 */
type Floater = {
  key: string
  /** which screen edge it leaves by when the phones close in */
  side: 'left' | 'right'
  turn: number
  style: React.CSSProperties
  body: React.ReactNode
}

const FLOATERS: Floater[] = [
  { key: 'notice', side: 'left', turn: -2, style: { left: '3vw', top: '12vh', rotate: '-3deg' }, body: <WaveNotice /> },
  { key: 'ready', side: 'left', turn: 3, style: { left: '17vw', top: '37vh', rotate: '2deg' }, body: <span className="app-ui"><StatusPill text="Ready to bump" tone="active" /></span> },
  { key: 'confirm', side: 'left', turn: 2, style: { left: '3vw', top: '55vh', rotate: '-2deg' }, body: <ConfirmCard /> },
  { key: 'wave', side: 'right', turn: 3, style: { right: '3vw', top: '24vh', rotate: '3deg' }, body: <WaveCard /> },
  { key: 'reveal', side: 'right', turn: -3, style: { right: '6vw', top: '75vh', rotate: '-2deg' }, body: <RevealRow /> },
]

export default function HeroFloaters() {
  return (
    <div className="hero__floaters" aria-hidden="true" inert>
      {FLOATERS.map((f) => (
        <div
          key={f.key}
          className={`hero__float hero__float--${f.key}`}
          data-side={f.side}
          data-turn={f.turn}
          style={f.style}
        >
          {f.body}
        </div>
      ))}
    </div>
  )
}
