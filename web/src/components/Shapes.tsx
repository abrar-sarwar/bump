import { useLayoutEffect, useRef } from 'react'
import gsap from 'gsap'
import { ScrollTrigger } from 'gsap/ScrollTrigger'
import { PILL, scallop } from '../shapes'
import './Shapes.css'

gsap.registerPlugin(ScrollTrigger)

/**
 * Quiet MD3 shapes in a section's empty margins, for visual continuity down
 * the page. Outlines and very faint fills only: no icons, no tonal badges.
 * Each drifts a little as its section scrolls past (scrubbed, so it reverses
 * exactly); reduced motion leaves them still. Decorative: aria-hidden.
 *
 * Positions are % of the section. Keep them in the side margins and the
 * padding bands, clear of the content column.
 */
const PATHS = {
  cookie: scallop(9, 0.1),
  clover: scallop(4, 0.35),
  sunny: scallop(12, 0.06),
  flower: scallop(6, 0.2),
  circle: scallop(1, 0),
  pill: PILL,
}

export type ShapeSpec = {
  shape: keyof typeof PATHS
  /** CSS positions within the section, e.g. { left: '5%', top: '20%' } */
  at: { left?: string; right?: string; top?: string; bottom?: string }
  /** width in px at a 1440px viewport; scales with the viewport */
  size: number
  /** faint fill instead of a hairline outline */
  fill?: boolean
  tone?: 'primary' | 'secondary' | 'tertiary'
  /** rotation across the section's pass, degrees */
  turn?: number
  /** vertical drift across the section's pass, px (negative rises) */
  drift?: number
  /** also show under 860px (default: desktop only) */
  mobile?: boolean
}

export default function Shapes({ set }: { set: ShapeSpec[] }) {
  const root = useRef<HTMLDivElement>(null)

  useLayoutEffect(() => {
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return
    const section = root.current?.parentElement
    if (!section) return
    const ctx = gsap.context(() => {
      gsap.utils.toArray<HTMLElement>('.shape').forEach((el, i) => {
        const s = set[i]
        const drift = s.drift ?? -60
        gsap.fromTo(el,
          { y: -drift / 2, rotation: 0 },
          {
            y: drift / 2,
            rotation: s.turn ?? 12,
            ease: 'none',
            scrollTrigger: {
              trigger: section,
              start: 'top bottom',
              end: 'bottom top',
              scrub: 0.5,
              // Below the hero's pin: measure after its spacer exists.
              refreshPriority: -1,
            },
          },
        )
      })
    }, root)
    return () => ctx.revert()
  }, [set])

  return (
    <div ref={root} className="shapes" aria-hidden="true">
      {set.map((s, i) => (
        <svg
          key={i}
          className={[
            'shape',
            s.fill ? 'shape--fill' : 'shape--line',
            `shape--${s.tone ?? 'primary'}`,
            s.mobile ? 'shape--mobile' : '',
          ].join(' ')}
          viewBox={s.shape === 'pill' ? '0 0 100 60' : '0 0 100 100'}
          style={{ ...s.at, ['--size' as string]: String(s.size) }}
        >
          <path d={PATHS[s.shape]} vectorEffect="non-scaling-stroke" />
        </svg>
      ))}
    </div>
  )
}
