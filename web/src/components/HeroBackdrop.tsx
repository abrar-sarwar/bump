import { PILL, scallop } from '../shapes'
import './HeroBackdrop.css'

/**
 * Very low-contrast background detail behind the hero: a fading dot grid, a
 * handful of shapes from the MD3 shape vocabulary, and a few conversation
 * glyphs. Purely decorative, so the whole layer is aria-hidden.
 *
 * It never moves on its own. BumpHero's scrubbed timeline gives it a slow
 * parallax (the layer drifts up, each shape turns a little), so it obeys the
 * same rules as everything else in the hero: scroll is the only driver, and
 * reduced motion leaves it perfectly still.
 */

type Shape = { key: string; d: string; style: 'fill' | 'line'; tone: 'primary' | 'secondary' | 'tertiary' }

// Order matters: BumpHero's parallax turns each shape by index.
const SHAPES: Shape[] = [
  { key: 'cookie', d: scallop(9, 0.1), style: 'fill', tone: 'primary' },
  { key: 'clover', d: scallop(4, 0.35), style: 'line', tone: 'primary' },
  { key: 'sunny', d: scallop(12, 0.06), style: 'line', tone: 'secondary' },
  { key: 'flower', d: scallop(6, 0.2), style: 'fill', tone: 'tertiary' },
  { key: 'dot', d: scallop(1, 0), style: 'fill', tone: 'secondary' },
  { key: 'pill', d: PILL, style: 'line', tone: 'primary' },
]

const GLYPHS = ['waving_hand', 'chat_bubble', 'favorite', 'handshake']

export default function HeroBackdrop() {
  return (
    <div className="hero__backdrop" aria-hidden="true">
      <div className="hero__dots" />
      {SHAPES.map((s) => (
        <svg
          key={s.key}
          className={`hero__shape hero__shape--${s.key} hero__shape--${s.style} hero__shape--${s.tone}`}
          viewBox={s.key === 'pill' ? '0 0 100 60' : '0 0 100 100'}
        >
          <path d={s.d} vectorEffect="non-scaling-stroke" />
        </svg>
      ))}
      {GLYPHS.map((g) => (
        <md-icon key={g} className={`hero__glyph hero__glyph--${g}`}>{g}</md-icon>
      ))}
    </div>
  )
}
