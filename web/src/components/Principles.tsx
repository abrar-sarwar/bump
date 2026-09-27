import './sections.css'
import Shapes, { type ShapeSpec } from './Shapes'

/**
 * What BUMP does and does not do, as MD3 cards.
 *
 * Every line here is a claim about the app, so every line must be true of the
 * code today. Sources: the top-level README, ios/README.md and
 * backend/CONTRACT.md. Do not add a card without a source.
 */
const PRINCIPLES = [
  {
    icon: 'person_off',
    label: 'account',
    title: 'No account',
    body: 'Nothing to sign up for. You make a profile on your phone and approve it before anyone sees it.',
  },
  {
    icon: 'sync_alt',
    label: 'nearby',
    title: 'Phone to phone',
    body: 'Bumping, confirming and swapping interests happen directly between the two phones in the room.',
  },
  {
    icon: 'rule',
    label: 'pairing',
    title: 'It won’t guess',
    body: 'If several people bump at once and BUMP can’t tell who tapped whom, it says so and lets you pick.',
  },
  {
    icon: 'mic',
    label: 'onboarding',
    title: 'Talk, or type',
    body: 'Introduce yourself out loud for up to 45 seconds, or type it. You edit the card it drafts.',
  },
  {
    icon: 'cloud_off',
    label: 'privacy',
    title: 'Server optional',
    body: 'Voice and smarter suggestions use the BUMP server, only if you allow it. Without it, the app uses on-phone suggestions and tells you.',
  },
  {
    icon: 'radar',
    label: 'distance',
    title: 'Ultra Wideband',
    body: 'On iPhones that have it, measured distance helps confirm which phone you actually tapped.',
  },
]

const WASHES = ['mint', 'peach', 'lilac', 'sky', 'lilac', 'mint']

// Margin shapes for this section (see Shapes.tsx).
const SHAPES: ShapeSpec[] = [
  { shape: 'sunny', at: { left: '4%', top: '3%' }, size: 150, turn: 22, drift: -60, mobile: true },
  { shape: 'flower', at: { right: '5%', top: '4%' }, size: 130, fill: true, turn: -16, drift: -90 },
  { shape: 'pill', at: { right: '10%', bottom: '2%' }, size: 140, turn: 10, drift: -50, tone: 'secondary' },
]

export default function Principles() {
  return (
    <section id="whats-inside" className="section folk-section">
      <Shapes set={SHAPES} />
      <div className="shell">
        <header className="folk-head">
          <p className="folk-eyebrow">What’s inside</p>
          <h2 className="folk-title">Small on purpose.</h2>
        </header>

        <ul className="principles">
          {PRINCIPLES.map((p, i) => (
            <li key={p.title} className={`folk-bento folk-bento--${WASHES[i]} principle`}>
              <p className="folk-bento__label">
                <md-icon aria-hidden="true">{p.icon}</md-icon>
                {p.label}
              </p>
              <div className="principle__foot">
                <h3 className="folk-bento__title">{p.title}.</h3>
                <p className="principle__body">{p.body}</p>
              </div>
            </li>
          ))}
        </ul>
      </div>
    </section>
  )
}
