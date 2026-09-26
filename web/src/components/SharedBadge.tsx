import { useLayoutEffect, useRef } from 'react'
import gsap from 'gsap'
import { ScrollTrigger } from 'gsap/ScrollTrigger'
import { scallop } from '../shapes'

gsap.registerPlugin(ScrollTrigger)

/**
 * "You both share this", in the manner of the animated shape on
 * m3.material.io/styles/shape: a pale circle with a darker rounded shape
 * inside that slowly turns and morphs through the MD3 shape set. The 'night'
 * tone (night hiking) is dark blue with twinkling white stars.
 *
 * Morphing works because every scallop() path has the same 360 points, so
 * GSAP can interpolate the `d` strings number by number. The shape turns
 * inside its own coordinate system; the text is HTML on top and never moves.
 *
 * Continuous, not scroll-driven: it plays only while on screen, and with
 * reduced motion it holds still on the first shape.
 */
const FORMS = [
  scallop(5, 0.14), // soft pentagon
  scallop(9, 0.1),  // cookie
  scallop(4, 0.24), // clover
  scallop(7, 0.12), // soft heptagon
]

export type BadgeTone = 'primary' | 'secondary' | 'tertiary' | 'night'

// Stars for the 'night' tone: [x, y, size] in the 100 x 100 box, kept inside
// the circle. Four-point sparkles for the bigger ones, dots for the rest.
// They stay out of the middle band (y 34 to 68) where the text sits, except
// right at the edges.
const STARS: [number, number, number][] = [
  [22, 24, 3.2], [74, 20, 2.4], [84, 72, 3], [26, 80, 2.2], [58, 88, 1.6],
  [11, 48, 1.4], [48, 10, 1.3], [90, 42, 1.2], [70, 84, 1.1], [36, 16, 1],
]
const sparkle = ([x, y, s]: [number, number, number]) =>
  `M${x} ${y - s}Q${x} ${y} ${x + s} ${y}Q${x} ${y} ${x} ${y + s}Q${x} ${y} ${x - s} ${y}Q${x} ${y} ${x} ${y - s}Z`

export default function SharedBadge({ interest, tone = 'primary' }: { interest: string; tone?: BadgeTone }) {
  const root = useRef<HTMLDivElement>(null)

  useLayoutEffect(() => {
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return
    const ctx = gsap.context(() => {
      const tl = gsap.timeline({
        repeat: -1,
        scrollTrigger: {
          trigger: root.current,
          toggleActions: 'play pause resume pause',
          refreshPriority: -1,
        },
      })
      // Morph through the forms and back to the first, holding each a beat.
      ;[...FORMS.slice(1), FORMS[0]].forEach((d) => {
        tl.to('.shared-badge__form', { attr: { d }, duration: 1.4, ease: 'sine.inOut' }, '+=0.9')
      })
      // Turn continuously for the whole loop, independent of the morphs.
      tl.to('.shared-badge__turn', {
        rotation: 360,
        svgOrigin: '50 50',
        duration: tl.duration(),
        ease: 'none',
      }, 0)
      // Stars twinkle out of step with each other (only visible on 'night').
      gsap.to('.shared-badge__star', {
        opacity: 0.25,
        duration: 1.3,
        ease: 'sine.inOut',
        stagger: { each: 0.35, repeat: -1, yoyo: true },
        scrollTrigger: {
          trigger: root.current,
          toggleActions: 'play pause resume pause',
          refreshPriority: -1,
        },
      })
    }, root)
    return () => ctx.revert()
  }, [])

  return (
    <div ref={root} className={`shared-badge shared-badge--${tone}`}>
      <svg className="shared-badge__art" viewBox="0 0 100 100" aria-hidden="true">
        <ellipse className="shared-badge__oval" cx="50" cy="50" rx="50" ry="50" />
        <g className="shared-badge__turn">
          <path className="shared-badge__form" d={FORMS[0]} transform="translate(50 50) scale(0.8) translate(-50 -50)" />
        </g>
        <g className="shared-badge__stars">
          {STARS.map((st, i) => st[2] >= 2
            ? <path key={i} className="shared-badge__star" d={sparkle(st)} />
            : <circle key={i} className="shared-badge__star" cx={st[0]} cy={st[1]} r={st[2] * 0.55} />)}
        </g>
      </svg>
      {/* aria-live so switching examples is announced, not silent */}
      <p className="shared-badge__text" aria-live="polite">
        <span className="shared-badge__kicker">You both share this</span>
        <span className="shared-badge__interest">{interest}</span>
      </p>
    </div>
  )
}
