import './sections.css'

/**
 * The real stack, as two scrolling rows. Every item is verified against the
 * repo (imports, project settings, package.json), and says what it does in
 * BUMP rather than what it is in general. Don't add anything the code
 * doesn't use.
 */
type Tech = { name: string; what: string; icon: string }

const APP: Tech[] = [
  { name: 'Swift + SwiftUI', what: 'native iOS 17+ app', icon: 'phone_iphone' },
  { name: 'Core Motion', what: 'accelerometer spike gate detects the tap', icon: 'vibration' },
  { name: 'Nearby Interaction', what: 'one NISession per peer, Ultra Wideband distance', icon: 'radar' },
  { name: 'Room relay', what: 'passes messages between phones in a room, stores nothing', icon: 'sync_alt' },
  { name: 'Foundation Models', what: 'on-device talking points when the server is off', icon: 'memory' },
  { name: 'ActivityKit + WidgetKit', what: 'Live Activity for bump status', icon: 'widgets' },
  { name: 'AVFoundation', what: 'records the spoken intro, up to 45s', icon: 'mic' },
  { name: 'UserNotifications', what: 'Wave heads-up if the app isn’t open', icon: 'notifications' },
]

const SERVER_AND_WEB: Tech[] = [
  { name: 'Node.js 20', what: 'bump-api, zero npm dependencies', icon: 'dns' },
  { name: 'xAI Grok', what: 'speech to text and structured-output drafting', icon: 'auto_awesome' },
  { name: 'node:test', what: 'mocked end-to-end API tests, no network', icon: 'rule' },
  { name: 'React 19 + TypeScript', what: 'this site', icon: 'web' },
  { name: 'Vite', what: 'dev server and build', icon: 'bolt' },
  { name: 'GSAP ScrollTrigger', what: 'the scroll-scrubbed bump', icon: 'animation' },
  { name: 'Material Web', what: 'Google’s MD3 components', icon: 'palette' },
  { name: 'Material Color Utilities', what: 'MD3 palette generated from the logo blue', icon: 'colorize' },
]

function Row({ items, reverse = false }: { items: Tech[]; reverse?: boolean }) {
  // The list is rendered twice so the loop is seamless; the copy is hidden
  // from assistive tech.
  const cells = (hidden: boolean) => items.map((t) => (
    <li key={t.name + hidden} className="folk-chip stack__item" aria-hidden={hidden || undefined}>
      <span className="folk-orb folk-orb--sm folk-orb--primary" aria-hidden="true">
        <md-icon>{t.icon}</md-icon>
      </span>
      <span className="folk-chip__text">
        <strong>{t.name}</strong>
        <span>{t.what}</span>
      </span>
    </li>
  ))
  return (
    <div className={`stack__row${reverse ? ' stack__row--reverse' : ''}`}>
      <ul className="stack__track">{cells(false)}{cells(true)}</ul>
    </div>
  )
}

export default function TechStack() {
  return (
    <section id="stack" className="section folk-section stack">
      <div className="shell">
        <header className="folk-head">
          <p className="folk-eyebrow">Under the hood</p>
          <h2 className="folk-title">What BUMP is built on.</h2>
        </header>
      </div>
      <Row items={APP} />
      <Row items={SERVER_AND_WEB} reverse />
    </section>
  )
}
