import { useLayoutEffect, useRef } from 'react'
import gsap from 'gsap'
import { ScrollTrigger } from 'gsap/ScrollTrigger'
import { scallop } from '../shapes'
import { motifMarkup, themeFor } from '../interestThemes'

gsap.registerPlugin(ScrollTrigger)

/**
 * "You both share this", in the manner of the animated shape on
 * m3.material.io/styles/shape: a pale circle with a darker rounded shape
 * inside that slowly turns and morphs through the MD3 shape set.
 *
 * Colours and the small animated motif come from the app's interest themes
 * (src/interestThemes.ts, ported from ios-mockup/interest-themes.js): anime
 * gets Film, jazz piano Music, night hiking Night sky, and so on.
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

export default function SharedBadge({ interest }: { interest: string }) {
  const root = useRef<HTMLDivElement>(null)
  // The app's own theme for this interest: colours, motif and its animation.
  const theme = themeFor(interest)
  const motif = motifMarkup(theme.id)

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
    <div ref={root} className="shared-badge" data-theme={theme.id}>
      <svg className="shared-badge__art" viewBox="0 0 100 100" aria-hidden="true">
        <ellipse className="shared-badge__oval" cx="50" cy="50" rx="50" ry="50" />
        <g className="shared-badge__turn">
          <path className="shared-badge__form" d={FORMS[0]} transform="translate(50 50) scale(0.8) translate(-50 -50)" />
        </g>
      </svg>
      <svg
        className={`shared-badge__motif theme-motif${motif.night ? ' theme-motif--night' : ''}`}
        viewBox="0 0 100 100"
        aria-hidden="true"
        dangerouslySetInnerHTML={{ __html: motif.html }}
      />
      {/* aria-live so switching examples is announced, not silent */}
      <p className="shared-badge__text" aria-live="polite">
        <span className="shared-badge__kicker">You both share this</span>
        <span className="shared-badge__interest">{interest}</span>
      </p>
    </div>
  )
}
