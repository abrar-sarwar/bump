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

/** A closed outline whose radius dips `depth` between `lobes` bumps, in a
 *  100 x 100 box. lobes 9 / depth 0.1 is MD3's "cookie", 4 / 0.35 its
 *  "clover", 12 / 0.06 its "sunny". depth 0 is a circle. */
function scallop(lobes: number, depth: number, steps = 360) {
  let d = ''
  for (let i = 0; i < steps; i++) {
    const t = (i / steps) * Math.PI * 2
    const r = 50 * (1 - (depth * (1 - Math.cos(lobes * t))) / 2)
    d += `${i ? 'L' : 'M'}${(50 + r * Math.cos(t)).toFixed(2)} ${(50 + r * Math.sin(t)).toFixed(2)}`
  }
  return d + 'Z'
}

type Shape = { key: string; d: string; style: 'fill' | 'line'; tone: 'primary' | 'secondary' | 'tertiary' }

// Order matters: BumpHero's parallax turns each shape by index.
const SHAPES: Shape[] = [
  { key: 'cookie', d: scallop(9, 0.1), style: 'fill', tone: 'primary' },
  { key: 'clover', d: scallop(4, 0.35), style: 'line', tone: 'primary' },
  { key: 'sunny', d: scallop(12, 0.06), style: 'line', tone: 'secondary' },
  { key: 'flower', d: scallop(6, 0.2), style: 'fill', tone: 'tertiary' },
  { key: 'dot', d: scallop(1, 0), style: 'fill', tone: 'secondary' },
  { key: 'pill', d: 'M30 5h40a25 25 0 0 1 0 50H30a25 25 0 0 1 0-50Z', style: 'line', tone: 'primary' },
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
