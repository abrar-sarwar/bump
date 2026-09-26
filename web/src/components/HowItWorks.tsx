import './sections.css'

// Deliberately short: one word and one line each.
const STEPS = [
  { icon: 'vibration', tone: 'primary', title: 'Bump', body: 'Tap your phones together.' },
  { icon: 'how_to_reg', tone: 'secondary', title: 'Confirm', body: 'You both say it was really them.' },
  { icon: 'join_inner', tone: 'tertiary', title: 'Connect', body: 'See what you share, and one thing to open with.' },
]

export default function HowItWorks() {
  return (
    <section id="how-it-works" className="section folk-section">
      <div className="shell">
        <header className="folk-head">
          <p className="folk-eyebrow">How it works</p>
          <h2 className="folk-title">Bump, confirm, connect.</h2>
        </header>

        <ol className="steps">
          {STEPS.map((s, i) => (
            <li key={s.title} className="folk-card step">
              <span className={`folk-orb folk-orb--${s.tone}`} aria-hidden="true">
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
