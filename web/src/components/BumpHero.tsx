import { useLayoutEffect, useRef, useState } from 'react'
import gsap from 'gsap'
import { ScrollTrigger } from 'gsap/ScrollTrigger'
import wordmark from '../assets/wordmark.png'
import './BumpHero.css'

gsap.registerPlugin(ScrollTrigger)

/**
 * The opening scroll sequence.
 *
 * One pinned scene, one scrub timeline. Scroll progress drives the visual
 * timeline — we never hijack the wheel, never snap, and the whole thing plays
 * backwards correctly because every step is a tween on a scrubbed timeline.
 *
 * TUNING — everything worth adjusting lives in STAGE and LAYOUT below.
 *   STAGE   when each beat happens, as a fraction of scroll through the section
 *   LAYOUT  where the phones start and where their edges meet, per breakpoint
 *
 * Geometry note: these are photographs, so the phone body is not centred in its
 * own image. Measured from the source art:
 *   blue   phone case spans 63.8%–99.8% of its image width (leading edge = right)
 *   orange phone case spans  0.2%–48%   of its image width (leading edge = left)
 * That is why contact is expressed as "how far past centre the image edge goes"
 * rather than by nudging whole-image bounds together.
 */

const STAGE = {
  cueOut: 0.10,      // the "scroll to bump" cue fades away
  approachIn: 0.15,  // phones start closing
  contact: 0.50,     // edges meet
  recoilOut: 0.62,   // recoil settles, reveal begins
  revealIn: 0.66,    // wordmark takes focus, copy arrives
  settled: 0.90,     // composition holds before release
}

type Layout = {
  /** where each image sits at rest, as % of its own width pushed off-screen */
  restOffset: number
  /** inward travel along the approach axis, in vw (x) or vh (y) */
  travel: number
  /** secondary drift on the other axis, same units as its own viewport side */
  drift: number
  /**
   * Which way the phones close.
   *  'x' — desktop: wide frame, the phones meet side by side near centre.
   *  'y' — mobile: the frame is too narrow for a side-by-side meeting, so the
   *        phones are already horizontally overlapped and close VERTICALLY,
   *        blue descending from upper-left, orange rising from lower-right.
   */
  axis: 'x' | 'y'
  /** how far the phones part, and drop, during the logo reveal */
  partX: number
  partY: number
  /** wordmark width at rest / at reveal, in vw */
  markRest: number
  markReveal: number
}

const DESKTOP: Layout = {
  restOffset: 26, travel: 19.3, drift: 0, axis: 'x',
  partX: 15, partY: 31, markRest: 92, markReveal: 76,
}

const MOBILE: Layout = {
  // Recomposed, not shrunk: bigger phones, a vertical meeting, and the
  // wordmark reading across the middle rather than hiding behind the photos.
  restOffset: 34, travel: 7.4, drift: 2.5, axis: 'y',
  partX: 19, partY: 31, markRest: 94, markReveal: 90,
}

export default function BumpHero() {
  const root = useRef<HTMLDivElement>(null)
  const [imagesReady, setImagesReady] = useState(0)

  // Wait for the phone images AND fonts before measuring, so ScrollTrigger
  // never pins against a layout that is about to shift.
  const onImgLoad = () => setImagesReady((n) => n + 1)

  useLayoutEffect(() => {
    if (imagesReady < 2) return

    const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches
    if (reduced) return // static composition; see BumpHero.css

    const ctx = gsap.context(() => {
      const mm = gsap.matchMedia()

      const build = (L: Layout, scrollVh: number) => () => {
        const q = gsap.utils.selector(root)
        const blue = q('.hero__phone--blue')
        const orange = q('.hero__phone--orange')
        const mark = q('.hero__mark')
        const spark = q('.hero__spark')

        // ScrollTrigger's `end` and GSAP's relative tweens want PIXELS, not
        // viewport units, so everything is resolved here and recomputed on
        // refresh (resize / mobile chrome collapse) via invalidateOnRefresh.
        const vw = () => window.innerWidth / 100
        const vh = () => window.innerHeight / 100
        const along = L.axis === 'x' ? L.travel * vw() : L.travel * vh()
        const across = L.axis === 'x' ? L.drift * vh() : L.drift * vw()
        // Blue closes in the positive direction, orange in the negative one.
        const inward = (sign: number) =>
          L.axis === 'x'
            ? { x: sign * along, y: sign * across }
            : { x: sign * across, y: sign * along }

        // Rest pose.
        gsap.set(blue, { xPercent: -L.restOffset, yPercent: -50, rotation: -3, x: 0, y: 0 })
        gsap.set(orange, { xPercent: L.restOffset, yPercent: -50, rotation: 3, x: 0, y: 0 })
        gsap.set(mark, { width: `${L.markRest}vw`, yPercent: -50, opacity: 1 })
        gsap.set(spark, { scale: 0.4, opacity: 0 })

        const tl = gsap.timeline({
          defaults: { ease: 'none' },
          scrollTrigger: {
            trigger: root.current,
            start: 'top top',
            end: () => '+=' + window.innerHeight * (scrollVh / 100),
            pin: '.hero__stage',
            pinSpacing: true,
            scrub: 0.6,
            invalidateOnRefresh: true,
          },
        })

        // ---- cue out
        tl.to('.hero__cue', { opacity: 0, y: 14, duration: STAGE.cueOut }, 0)

        // ---- the approach (translate + a little rotation, never a zoom)
        const approach = STAGE.contact - STAGE.approachIn
        const blueIn = inward(1)
        const orangeIn = inward(-1)
        tl.to(blue, {
          ...blueIn, rotation: 1.5,
          duration: approach, ease: 'power1.in',
        }, STAGE.approachIn)
        tl.to(orange, {
          ...orangeIn, rotation: -1.5,
          duration: approach, ease: 'power1.in',
        }, STAGE.approachIn)
        tl.to(mark, { opacity: 0.55, duration: approach }, STAGE.approachIn)

        // ---- contact: a short, readable beat, then a restrained recoil
        const beat = STAGE.recoilOut - STAGE.contact
        const recoil = L.axis === 'x' ? 1.6 * vw() : 1.6 * vh()
        const back = (p: { x: number; y: number }, sign: number) =>
          L.axis === 'x' ? { x: p.x - sign * recoil, y: p.y } : { x: p.x, y: p.y - sign * recoil }
        const blueRest = back(blueIn, 1)
        const orangeRest = back(orangeIn, -1)
        tl.to(spark, { opacity: 1, scale: 1, duration: beat * 0.28 }, STAGE.contact)
        tl.to(blue, { ...blueRest, rotation: -0.5, duration: beat * 0.5, ease: 'power2.out' }, STAGE.contact + beat * 0.2)
        tl.to(orange, { ...orangeRest, rotation: 0.5, duration: beat * 0.5, ease: 'power2.out' }, STAGE.contact + beat * 0.2)
        tl.to(spark, { opacity: 0, scale: 1.5, duration: beat * 0.5 }, STAGE.contact + beat * 0.35)

        // ---- the reveal: the SAME wordmark becomes the focal point
        const reveal = STAGE.settled - STAGE.revealIn
        // Part outwards, clearing the centre for the wordmark and the copy.
        // Desktop: both sink toward the lower outside corners.
        // Mobile: they separate back along the axis they closed on — blue up,
        // orange down — so the tagline and button get a clean band between them.
        const partX = L.partX * vw()
        const partY = L.partY * vh()
        const blueOut = L.axis === 'x'
          ? { x: blueRest.x - partX, y: blueRest.y + partY }
          : { x: blueRest.x - partX, y: blueRest.y - partY }
        const orangeOut = { x: orangeRest.x + partX, y: orangeRest.y + partY }
        tl.to(blue, {
          ...blueOut, rotation: -9,
          duration: reveal, ease: 'power1.inOut',
        }, STAGE.revealIn)
        tl.to(orange, {
          ...orangeOut, rotation: 9,
          duration: reveal, ease: 'power1.inOut',
        }, STAGE.revealIn)
        tl.to(mark, {
          width: `${L.markReveal}vw`, opacity: 1,
          duration: reveal, ease: 'power1.inOut',
        }, STAGE.revealIn)
        tl.fromTo('.hero__reveal',
          { opacity: 0, y: 24 },
          { opacity: 1, y: 0, duration: reveal * 0.6, ease: 'power2.out' },
          STAGE.revealIn + reveal * 0.35,
        )

        // The STAGE numbers are fractions of the WHOLE scroll, so the timeline
        // has to be exactly 1 unit long. Without this it ends at `settled`
        // (0.90) and every beat lands ~10% late — the reveal never finishes.
        tl.set({}, {}, 1)
      }

      mm.add('(min-width: 861px)', build(DESKTOP, 320))
      mm.add('(max-width: 860px)', build(MOBILE, 240))
    }, root)

    // Fonts can change the cue/reveal text metrics after first paint.
    document.fonts?.ready.then(() => ScrollTrigger.refresh())

    return () => ctx.revert() // also undoes the pin; safe across StrictMode remounts
  }, [imagesReady])

  return (
    <section ref={root} className="hero" aria-labelledby="hero-heading">
      <div className="hero__stage">
        {/* The real heading for assistive tech and SEO; the artwork is decorative. */}
        <h1 id="hero-heading" className="sr-only">
          BUMP — meet someone, find your overlap
        </h1>

        <img className="hero__mark" src={wordmark} alt="" aria-hidden="true" />

        <div className="hero__spark" aria-hidden="true" />

        <img
          className="hero__phone hero__phone--blue"
          src="/assets/phone-blue.png"
          srcSet="/assets/phone-blue.png 1100w, /assets/phone-blue@1600.png 1600w"
          sizes="46vw"
          width={1100}
          height={506}
          alt=""
          aria-hidden="true"
          onLoad={onImgLoad}
          onError={onImgLoad}
        />
        <img
          className="hero__phone hero__phone--orange"
          src="/assets/phone-orange.png"
          srcSet="/assets/phone-orange.png 1100w, /assets/phone-orange@1600.png 1600w"
          sizes="46vw"
          width={1100}
          height={604}
          alt=""
          aria-hidden="true"
          onLoad={onImgLoad}
          onError={onImgLoad}
        />

        <p className="hero__cue" aria-hidden="true">
          <span className="hero__cue-line" />
          Scroll to bump
        </p>

        <div className="hero__reveal">
          <p className="hero__tagline">A small gesture. A real connection.</p>
          <a className="btn btn--primary" href="#how-it-works">See how it works</a>
        </div>
      </div>
    </section>
  )
}
