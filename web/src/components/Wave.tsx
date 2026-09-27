import { WaveCard, WaveNotice } from './AppUI'
import Shapes, { type ShapeSpec } from './Shapes'
import './sections.css'

/**
 * Wave: the first move in the flow. Built in the iOS app (code name
 * StreetPass: Service/StreetPass/, View/StreetPassSheet.swift, spec in
 * docs/superpowers/specs/2026-09-26-streetpass-design.md).
 *
 * Every claim below is true of that code today:
 * - triggers at ~0.5m (StreetPassConfig.proximityThreshold), after 3
 *   consecutive readings, measured with Ultra Wideband;
 * - only while BUMP is open (NI ranging can't run in the background);
 * - one shared interest in the clear, up to two more blurred
 *   (StreetPassEncounter.maxTeased), none invented;
 * - "Bump them" goes into the normal bump and confirm flow;
 * - won't re-fire for the same person until they walk away (hysteresis +
 *   30s cooldown); encounters are kept in memory only.
 * Do not add a claim here that the code doesn't back.
 */
const FACTS = [
  { icon: 'straighten', text: 'Within about half a metre' },
  { icon: 'radar', text: 'Ultra Wideband distance, not location' },
  { icon: 'visibility_off', text: 'One thing in the clear, the rest blurred' },
  { icon: 'phone_iphone', text: 'Works while BUMP is open' },
]

const SHAPES: ShapeSpec[] = [
  { shape: 'pill', at: { left: '1%', top: '8%' }, size: 130, turn: 14, drift: -60 },
  { shape: 'clover', at: { right: '1.5%', bottom: '4%' }, size: 120, fill: true, turn: -18, drift: -90, tone: 'tertiary', mobile: true },
]

export default function Wave() {
  return (
    <section id="wave" className="section folk-section">
      <Shapes set={SHAPES} />
      <div className="shell">
        <div className="folk-bento folk-bento--lilac wave">
          <div className="wave__copy">
            <p className="folk-bento__label">
              <span className="folk-orb folk-orb--sm folk-orb--tertiary md-shape md-shape--flower" aria-hidden="true">
                <md-icon>waving_hand</md-icon>
              </span>
              Wave
            </p>
            <h2 className="wave__title">The people you almost met.</h2>
            <p className="wave__body">
              Walk past someone who also has BUMP open and you both get a heads-up: who
              they are, and one thing you genuinely have in common. If there’s more, it
              stays blurred. Bump to see the rest.
            </p>
            <ul className="wave__facts">
              {FACTS.map((f) => (
                <li key={f.text}>
                  <md-icon aria-hidden="true">{f.icon}</md-icon>
                  {f.text}
                </li>
              ))}
            </ul>
          </div>

          {/* The app's own Wave notification and pass card. Decorative:
              the copy above says everything they show. */}
          <div className="wave__demo" aria-hidden="true">
            <WaveNotice />
            <WaveCard />
          </div>
        </div>
      </div>
    </section>
  )
}
