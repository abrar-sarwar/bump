import './sections.css'

const STEPS = [
  {
    n: '01',
    title: 'Bump',
    body: 'Both of you open BUMP and tap ready. Bring your phones together — a gentle tap, back to back.',
    note: 'Nothing happens until both people are ready. BUMP never scans the room for strangers.',
  },
  {
    n: '02',
    title: 'Confirm',
    body: 'Each phone shows the other person’s name. You both confirm it was really them.',
    note: 'Your interests stay on your phone until both of you say yes.',
  },
  {
    n: '03',
    title: 'Find your overlap',
    body: 'The specific things you share appear on both phones, with one question to start on.',
    note: 'Only what is genuinely in both profiles. Nothing invented.',
  },
]

export default function HowItWorks() {
  return (
    <section id="how-it-works" className="section section--steps">
      <div className="shell">
        <p className="eyebrow">How it works</p>
        <h2 className="steps__heading">Three moves.<br />About four seconds.</h2>

        <ol className="steps">
          {STEPS.map((s) => (
            <li key={s.n} className="step">
              <span className="step__n" aria-hidden="true">{s.n}</span>
              <div className="step__content">
                <h3 className="step__title">
                  <span className="sr-only">Step {s.n}: </span>{s.title}
                </h3>
                <p className="step__body">{s.body}</p>
                <p className="step__note">{s.note}</p>
              </div>
            </li>
          ))}
        </ol>
      </div>
    </section>
  )
}
