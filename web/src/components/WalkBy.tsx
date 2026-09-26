import './sections.css'
import Shapes, { type ShapeSpec } from './Shapes'

/**
 * The "StreetPass" idea from the team's master doc (.agents/60-master-doc.md):
 * when someone nearby walks past, BUMP can nudge you with a teaser of at most
 * one shared interest; the full connection only unlocks when you actually
 * bump.
 *
 * NOT BUILT YET. The human confirmed on 2026-09-26 that the team is going to
 * try it and wants it on the site, and that the name will change. So it is
 * labelled "in the works", uses the placeholder name below, and claims
 * nothing beyond what the doc describes. Change NAME in one place.
 */
const NAME = 'walk-by'

// Margin shapes for this section (see Shapes.tsx).
const SHAPES: ShapeSpec[] = [
  { shape: 'pill', at: { left: '1%', top: '8%' }, size: 130, turn: 14, drift: -60 },
  { shape: 'clover', at: { right: '1.5%', bottom: '4%' }, size: 120, fill: true, turn: -18, drift: -90, tone: 'tertiary', mobile: true },
]

export default function WalkBy() {
  return (
    <section id="walk-by" className="section folk-section">
      <Shapes set={SHAPES} />
      <div className="shell">
        <div className="folk-bento folk-bento--lilac walkby">
          <div className="walkby__copy">
            <p className="folk-bento__label">
              <md-icon aria-hidden="true">directions_walk</md-icon>
              In the works: {NAME}
            </p>
            <h2 className="walkby__title">The people you almost met.</h2>
            <p className="walkby__body">
              Someone who shares something with you just walked past. BUMP gives you a
              heads up, and a teaser of at most one thing you have in common. Just
              enough to make saying hi feel worth it. Everything else unlocks when you
              actually bump.
            </p>
            <p className="walkby__status">Not in the app yet. We’re building it.</p>
          </div>

          {/* An illustrative lock-screen moment. Dev and 35mm photography are
              the same fictional example as the overlap section. */}
          <div className="walkby__phone" aria-hidden="true">
            <div className="walkby__notice">
              <span className="walkby__app"><md-icon>vibration</md-icon></span>
              <div>
                <p className="walkby__meta"><strong>bump</strong> now</p>
                <p className="walkby__msg">someone just walked by you. bump them?</p>
              </div>
            </div>
            <div className="walkby__teaser">
              <md-icon>join_inner</md-icon>
              <span><span className="walkby__faint">1 thing in common</span> 35mm photography</span>
            </div>
            <div className="walkby__locked">
              <md-icon>lock</md-icon>
              <span>the rest unlocks when you bump</span>
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}
