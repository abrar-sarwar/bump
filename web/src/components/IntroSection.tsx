import { useLayoutEffect, useRef } from 'react'
import gsap from 'gsap'
import { ScrollTrigger } from 'gsap/ScrollTrigger'
import './sections.css'
import Shapes, { type ShapeSpec } from './Shapes'

gsap.registerPlugin(ScrollTrigger)

// The statement, split so each word can be revealed by scroll. `orbs` marks
// where the inline icon orbs sit, the way folk sets app icons into its line.
const BEFORE = 'You already have something in common. BUMP'
const AFTER = 'finds it, so a first hello turns into a real conversation.'

const ORBS = [
  { icon: 'vibration', tone: 'primary' },
  { icon: 'handshake', tone: 'secondary' },
  { icon: 'chat_bubble', tone: 'tertiary' },
]

const words = (s: string) => s.split(' ').map((w, i) => (
  <span className="statement__word" key={i}>{w} </span>
))

// Margin shapes for this section (see Shapes.tsx).
const SHAPES: ShapeSpec[] = [
  { shape: 'cookie', at: { left: '4%', top: '18%' }, size: 170, turn: 16, drift: -80, mobile: true },
  { shape: 'flower', at: { right: '5%', top: '34%' }, size: 200, fill: true, turn: -20, drift: -120, tone: 'tertiary' },
  { shape: 'circle', at: { left: '15%', bottom: '14%' }, size: 64, fill: true, drift: -60, tone: 'secondary' },
  { shape: 'pill', at: { right: '13%', bottom: '10%' }, size: 150, turn: 12, drift: -50, mobile: true },
]

export default function IntroSection() {
  const root = useRef<HTMLElement>(null)

  // Words start faint and darken as the statement scrolls through the
  // viewport, scrubbed so it reverses on scroll-up. Reduced motion: the CSS
  // default is fully dark and this never runs.
  useLayoutEffect(() => {
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return
    const ctx = gsap.context(() => {
      gsap.fromTo('.statement__word, .statement__orbs',
        { opacity: 0.16 },
        {
          opacity: 1,
          ease: 'none',
          stagger: 0.12,
          scrollTrigger: {
            trigger: '.statement__text',
            start: 'top 82%',
            end: 'bottom 45%',
            scrub: 0.4,
            // Created before the hero's pin (the hero waits for its images),
            // but sits below it, so it must be measured AFTER the pin spacer
            // exists. Lower priority = refreshed later.
            refreshPriority: -1,
          },
        },
      )
    }, root)
    return () => ctx.revert()
  }, [])

  return (
    <section ref={root} id="the-idea" className="section folk-section statement">
      <Shapes set={SHAPES} />
      <div className="shell">
        <p className="folk-eyebrow">The idea</p>
        <h2 className="statement__text">
          {words(BEFORE)}
          <span className="statement__orbs" aria-hidden="true">
            {ORBS.map((o) => (
              <span key={o.icon} className={`folk-orb folk-orb--${o.tone}`}>
                <md-icon>{o.icon}</md-icon>
              </span>
            ))}
          </span>{' '}
          {words(AFTER)}
        </h2>
        <p className="statement__aside">
          Not a feed. Not a follow. One gesture, one person, one thing worth talking about.
        </p>
      </div>
    </section>
  )
}
