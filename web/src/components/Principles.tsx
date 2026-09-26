import './sections.css'

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

export default function Principles() {
  return (
    <section id="whats-inside" className="section folk-section">
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

        <p className="folk-chip principles__status">
          <span className="folk-orb folk-orb--sm folk-orb--tertiary" aria-hidden="true">
            <md-icon>science</md-icon>
          </span>
          <span>
            <strong>Where it stands.</strong> The iOS app builds clean and 96 of 100 unit
            tests pass, with 4 skipped. It has not yet been proven on two physical phones.
          </span>
        </p>
      </div>
    </section>
  )
}
