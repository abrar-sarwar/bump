import { useLayoutEffect, useRef, useState } from 'react'
import gsap from 'gsap'
import { ScrollTrigger } from 'gsap/ScrollTrigger'
import wordmark from '../assets/wordmark.png'
import HeroBackdrop from './HeroBackdrop'
import HeroFloaters from './HeroFloaters'
import './BumpHero.css'

gsap.registerPlugin(ScrollTrigger)

/**
 * The opening scroll sequence.
 *
 * One pinned scene, one scrub timeline. Scroll progress drives the visual
 * timeline. We never hijack the wheel, never snap, and the whole thing plays
 * backwards correctly because every step is a tween on a scrubbed timeline.
 *
 * TUNING: everything worth adjusting lives in STAGE and LAYOUT below.
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

// Scroll lengths are 400vh desktop / 300vh mobile. Everything up to revealIn
// sits at the same ABSOLUTE scroll distance it had at 320 / 240 (fractions
// scaled by 0.8); the extra length all went to the reveal, so the wordmark
// and the parting phones take twice as much scrolling as they used to.
const STAGE = {
  cueOut: 0.08,      // the "scroll to bump" cue fades away
  approachIn: 0.12,  // phones start closing
  contact: 0.40,     // edges meet
  recoilOut: 0.496,  // recoil settles, reveal begins
  revealIn: 0.528,   // wordmark takes focus, copy arrives
  settled: 0.912,    // composition holds before release
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
   *  'x' is desktop: wide frame, the phones meet side by side near centre.
   *  'y' is mobile: the frame is too narrow for a side-by-side meeting, so the
   *        phones are already horizontally overlapped and close VERTICALLY,
   *        blue descending from upper-left, orange rising from lower-right.
   */
  axis: 'x' | 'y'
  /** how far the phones part, and drop, during the logo reveal */
  partX: number
  partY: number
  /** wordmark width once revealed, in vw. It has no "rest" size: the hero
   *  wordmark does not exist on screen until the phones have bumped. */
  markReveal: number
  /** uniform scale the wordmark starts at before it opens out. Kept close to 1
   *  so the letterforms never look squashed: the width comes from the mask. */
  markFrom: number
}

const DESKTOP: Layout = {
  // The photos are 60vw wide so the cropped wrist of each arm stays past the
  // viewport edge for the whole sequence, including contact. restOffset was
  // re-derived with it so the leading phone edges sit exactly where they did
  // at 46vw: blue rests at 33.9vw and meets at 53.2vw, and the image's left
  // (wrist) edge is at -26vw at rest and -6.7vw at contact, never on screen.
  restOffset: 43.3, travel: 19.3, drift: 0, axis: 'x',
  partX: 15, partY: 50, markReveal: 76, markFrom: 0.9,
}

const MOBILE: Layout = {
  // Recomposed, not shrunk: bigger phones, a vertical meeting, and the
  // wordmark reading across the middle rather than hiding behind the photos.
  restOffset: 34, travel: 7.4, drift: 2.5, axis: 'y',
  partX: 19, partY: 31, markReveal: 90, markFrom: 0.92,
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
        // Hidden from the very first frame. Width is fixed at its final size
        // and only `scale` animates, so the bloom is a transform, not a layout
        // change. CSS already sets opacity: 0 so it cannot flash before GSAP runs.
        gsap.set(mark, {
          // Centre with xPercent, and zero x explicitly. GSAP folds the CSS
          // `translate: -50%` into a PIXEL x the first time it touches the
          // transform, measured at the CSS width (92vw); after this resize to
          // markReveal that stale offset put the word ~115px left of centre,
          // i.e. not opening from the point where the phones met.
          width: `${L.markReveal}vw`, x: 0, xPercent: -50, yPercent: -50,
          // Fully opaque but masked to a zero-width sliver at the centre, which
          // is exactly where the phones meet. The reveal opens that mask
          // outwards, so the WORD grows from the contact point instead of
          // fading in. Masking rather than scaleX keeps the letterforms
          // undistorted at every frame.
          opacity: 1,
          clipPath: 'inset(0% 50% 0% 50%)',
          scale: L.markFrom,
        })
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

        // ---- background parallax, across the whole scroll. Slow and linear,
        // so it reads as depth rather than as something happening.
        tl.to(q('.hero__backdrop'), { y: () => -7 * vh(), duration: 1 }, 0)
        tl.to(q('.hero__shape'), {
          rotation: (i: number) => [28, -22, 34, -18, 0, 16][i] ?? 0,
          duration: 1,
        }, 0)
        // The reveal's one shared motion: the wordmark opening and the phones
        // parting use this start, duration and ease (see "the reveal" below),
        // and the foreground fragments slide off at the same speed.
        const reveal = STAGE.settled - STAGE.revealIn
        const partAt = STAGE.revealIn + reveal * 0.12
        const partFor = reveal * 0.88
        const partEase = 'power1.inOut'

        // Foreground UI fragments: from just after the cue fades, each slides
        // sideways off its own edge at the reveal's speed, a small stagger
        // between them. Distances come from untransformed layout
        // (offsetLeft/Width) so a refresh mid-scroll measures correctly.
        q('.hero__float').forEach((el: HTMLElement, i: number) => {
          const out = () => el.dataset.side === 'left'
            ? -(el.offsetLeft + el.offsetWidth * 1.1 + 80)
            : window.innerWidth - el.offsetLeft + 80
          tl.to(el, {
            x: out,
            rotation: `+=${Number(el.dataset.turn) * 3}`,
            duration: partFor,
            ease: partEase,
          }, STAGE.cueOut * 0.5 + i * 0.012)
        })

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
        // Part outwards, clearing the centre for the wordmark and the copy.
        // Desktop: both sink toward the lower outside corners.
        // Mobile: they separate back along the axis they closed on: blue up,
        // orange down, so the tagline and button get a clean band between them.
        const partX = L.partX * vw()
        const partY = L.partY * vh()
        // 1 + 2. The phones move aside and the wordmark opens out of the
        //    meeting point AS they part: one start, one duration, one ease, so
        //    the mask's edges track the phones instead of racing ahead of them.
        //    (It used to open over 0.6 of this span with power2.out and was
        //    fully open while the phones had barely started moving.)
        //    This starts after STAGE.revealIn, so strictly after the recoil
        //    and the contact mark have finished.
        const blueOut = L.axis === 'x'
          ? { x: blueRest.x - partX, y: blueRest.y + partY }
          : { x: blueRest.x - partX, y: blueRest.y - partY }
        const orangeOut = { x: orangeRest.x + partX, y: orangeRest.y + partY }
        tl.to(blue, {
          ...blueOut, rotation: -9,
          duration: partFor, ease: partEase,
        }, partAt)
        tl.to(orange, {
          ...orangeOut, rotation: 9,
          duration: partFor, ease: partEase,
        }, partAt)
        tl.fromTo(mark,
          { clipPath: 'inset(0% 50% 0% 50%)', scale: L.markFrom },
          {
            clipPath: 'inset(0% 0% 0% 0%)', scale: 1,
            duration: partFor, ease: partEase,
          },
          partAt,
        )

        // 3. then the supporting line and the CTA
        tl.fromTo('.hero__reveal',
          { opacity: 0, y: 24 },
          // Starts once the word is past halfway open, lands with `settled`.
          { opacity: 1, y: 0, duration: reveal * 0.4, ease: 'power2.out' },
          STAGE.revealIn + reveal * 0.6,
        )

        // The STAGE numbers are fractions of the WHOLE scroll, so the timeline
        // has to be exactly 1 unit long. Without this it ends at `settled`
        // (0.90) and every beat lands ~10% late, and the reveal never finishes.
        tl.set({}, {}, 1)
      }

      mm.add('(min-width: 861px)', build(DESKTOP, 400))
      mm.add('(max-width: 860px)', build(MOBILE, 300))
    }, root)

    // The pin adds ~3x the viewport height of spacer above everything below
    // the hero. Any ScrollTrigger created earlier (the intro's word reveal)
    // measured the page without it, so re-measure now that it exists.
    ScrollTrigger.refresh()

    // Fonts can change the cue/reveal text metrics after first paint.
    document.fonts?.ready.then(() => ScrollTrigger.refresh())

    return () => ctx.revert() // also undoes the pin; safe across StrictMode remounts
  }, [imagesReady])

  return (
    <section ref={root} className="hero" aria-labelledby="hero-heading">
      <div className="hero__stage">
        {/* The real heading for assistive tech and SEO; the artwork is decorative. */}
        <h1 id="hero-heading" className="sr-only">
          BUMP. Meet someone, find your overlap.
        </h1>

        <HeroBackdrop />

        <img className="hero__mark" src={wordmark} alt="" aria-hidden="true" />

        <div className="hero__spark" aria-hidden="true" />

        <img
          className="hero__phone hero__phone--blue"
          src="/assets/phone-blue.png"
          srcSet="/assets/phone-blue.png 1100w, /assets/phone-blue@1600.png 1600w"
          sizes="(max-width: 860px) 82vw, 60vw"
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
          sizes="(max-width: 860px) 82vw, 60vw"
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

        <HeroFloaters />

        <div className="hero__reveal">
          <p className="hero__tagline">A small gesture. A real connection.</p>
          <md-filled-button href="#how-it-works" trailing-icon="">
            See how it works
            <md-icon slot="icon">arrow_downward</md-icon>
          </md-filled-button>
        </div>
      </div>
    </section>
  )
}
