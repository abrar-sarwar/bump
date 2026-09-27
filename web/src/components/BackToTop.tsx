import { useEffect, useState } from 'react'
import './BackToTop.css'

/**
 * A dark folk-style button that appears once the hero has scrolled away. The
 * hero is a long pinned scene, so getting back to the top is otherwise a lot
 * of scrolling. Focus goes to the brand link so keyboard users land somewhere.
 */
export default function BackToTop() {
  const [shown, setShown] = useState(false)

  useEffect(() => {
    const hero = document.querySelector('.hero')
    if (!hero) return
    const io = new IntersectionObserver(([e]) => setShown(!e.isIntersecting))
    io.observe(hero)
    return () => io.disconnect()
  }, [])

  const toTop = () => {
    const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches
    window.scrollTo({ top: 0, behavior: reduced ? 'auto' : 'smooth' })
    document.querySelector<HTMLElement>('.header__brand')?.focus({ preventScroll: true })
  }

  return (
    <button
      type="button"
      className={shown ? 'to-top to-top--shown' : 'to-top'}
      aria-label="Back to top"
      inert={shown ? undefined : true}
      onClick={toTop}
    >
      <md-icon aria-hidden="true">arrow_upward</md-icon>
    </button>
  )
}
