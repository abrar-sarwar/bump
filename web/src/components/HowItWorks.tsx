import Shapes, { type ShapeSpec } from './Shapes'
import './sections.css'

// Deliberately short: one word and one line each. Wave is the first move:
// it's how you find out someone nearby is worth bumping.
const STEPS = [
  { icon: 'waving_hand', tone: 'tertiary', shape: 'flower', title: 'Wave', body: 'Someone nearby shares something with you. You get a heads-up.' },
  { icon: 'vibration', tone: 'primary', shape: 'cookie', title: 'Bump', body: 'Tap your phones together.' },
  { icon: 'how_to_reg', tone: 'secondary', shape: 'clover', title: 'Confirm', body: 'You both say it was really them.' },
  { icon: 'join_inner', tone: 'primary', shape: 'sunny', title: 'Connect', body: 'See what you share, and one thing to open with.' },
]

const SHAPES: ShapeSpec[] = [
  { shape: 'clover', at: { left: '7%', top: '10%' }, size: 124, turn: 18, drift: -70, mobile: true },
  { shape: 'sunny', at: { right: '12%', top: '6%' }, size: 190, turn: 24, drift: -40, tone: 'secondary' },
  { shape: 'pill', at: { left: '13%', bottom: '10%' }, size: 170, turn: -10, drift: -90 },
  { shape: 'cookie', at: { right: '8%', bottom: '8%' }, size: 108, fill: true, turn: -14, drift: -110, tone: 'tertiary', mobile: true },
]

export default function HowItWorks() {
  return (
    <section id="how-it-works" className="section folk-section">
      <Shapes set={SHAPES} />

      <div className="shell">
        <header className="folk-head">
          <p className="folk-eyebrow">How it works</p>
          <h2 className="folk-title">Wave, bump, confirm, connect.</h2>
        </header>

        <ol className="steps">
          {STEPS.map((s, i) => (
            <li key={s.title} className="folk-card step">
              <span className={`folk-orb folk-orb--${s.tone} md-shape md-shape--${s.shape}`} aria-hidden="true">
                <md-icon>{s.icon}</md-icon>
              </span>
              <div className="step__content">
                <h3 className="step__title">
                  <span className="sr-only">Step {i + 1}: </span>{s.title}
                </h3>
                <p className="step__body">{s.body}</p>
              </div>
            </li>
          ))}
        </ol>
      </div>
    </section>
  )
}
