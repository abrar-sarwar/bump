import Wordmark from './Wordmark'
import './SiteHeader.css'

const REPO = 'https://github.com/abrar-sarwar/bump'

export default function SiteHeader() {
  return (
    <header className="header">
      <a className="header__skip" href="#main">Skip to content</a>
      <div className="header__inner shell">
        <a className="header__brand" href="#top" aria-label="BUMP, back to top">
          <Wordmark className="header__mark" />
        </a>
        {/* folk's nav: one frosted pill holding the links and a dark action. */}
        <nav className="header__pill" aria-label="Primary">
          <ul className="header__nav">
            <li><a href="#the-idea">The idea</a></li>
            <li><a href="#how-it-works">How it works</a></li>
            <li><a href="#wave">Wave</a></li>
            <li><a href="#the-overlap">The overlap</a></li>
          </ul>
          <a className="header__repo" href={REPO} target="_blank" rel="noreferrer">GitHub</a>
        </nav>
      </div>
    </header>
  )
}
