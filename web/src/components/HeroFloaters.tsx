import type React from 'react'
import './HeroFloaters.css'

/**
 * Foreground fragments on the hero, scattered like stickers on a desk: the
 * little moments of meeting someone, in the voice people actually text in.
 * Dev and 35mm photography are the fictional example from the overlap
 * section, so the story is consistent down the page.
 *
 * Decoration only: the layer is aria-hidden and inert.
 *
 * Placement is deliberately irregular (no two share a line), checked against
 * the phones' rest pose so nothing covers the point where they will meet.
 *
 * Motion: as the phones close in, BumpHero slides each one sideways off the
 * edge it sits nearest (data-side), a little tilt added (data-turn), each
 * starting a beat after the last. By contact they are gone, so the bump and
 * the logo reveal play on a clean stage. Scrubbed, so they return on scroll-up.
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
  {
    key: 'lecture', side: 'left', turn: -2,
    style: { left: '3vw', top: '13vh', rotate: '-4deg' },
    body: <p className="float-bubble">we’ve sat next to each other in lecture all semester</p>,
  },
  {
    key: 'ready', side: 'left', turn: 3,
    style: { left: '17vw', top: '31vh', rotate: '3deg' },
    body: (
      <div className="float-card float-card--row">
        <md-elevation />
        <md-checkbox checked />
        <span>ready to bump</span>
        <md-icon>vibration</md-icon>
      </div>
    ),
  },
  {
    key: 'film', side: 'right', turn: 4,
    style: { right: '15vw', top: '17vh', rotate: '5deg' },
    body: <p className="float-bubble float-bubble--me">wait you shoot 35mm too??</p>,
  },
  {
    key: 'confirm', side: 'right', turn: -2,
    style: { right: '2vw', top: '37vh', rotate: '-3deg' },
    body: (
      <div className="float-card float-card--confirm">
        <md-elevation />
        <strong>did you bump with dev?</strong>
        <div className="float-card__actions">
          <md-text-button>not them</md-text-button>
          <md-filled-tonal-button>confirm</md-filled-tonal-button>
        </div>
      </div>
    ),
  },
  {
    key: 'major', side: 'left', turn: 2,
    style: { left: '1.5vw', top: '71vh', rotate: '2deg' },
    body: (
      <p className="float-bubble float-bubble--narrow">
        3 hours at this mixer and i’ve asked “what’s your major” 11 times
      </p>
    ),
  },
  {
    key: 'match', side: 'right', turn: 3,
    style: { right: '4vw', top: '75vh', rotate: '4deg' },
    body: (
      <div className="float-card float-card--toast">
        <md-elevation />
        <span className="float-card__orb"><md-icon>join_inner</md-icon></span>
        <span>
          <strong>you and dev both</strong>
          <span className="float-card__sub">35mm photography</span>
        </span>
      </div>
    ),
  },
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
