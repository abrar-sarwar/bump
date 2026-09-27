import Wordmark from './Wordmark'
import './sections.css'

const REPO = 'https://github.com/abrar-sarwar/bump'

export default function SiteFooter() {
  return (
    <footer className="folk-section footer">
      <div className="shell footer__top">
        <div className="footer__brand">
          <Wordmark className="footer__logo" />
          <p>Meet someone. Find your overlap.</p>
          <p className="footer__faint">A HackGT project.</p>
        </div>
        <nav className="footer__cols" aria-label="Footer">
          <div>
            <h2 className="footer__head">Site</h2>
            <ul>
              <li><a href="#the-idea">The idea</a></li>
              <li><a href="#how-it-works">How it works</a></li>
              <li><a href="#wave">Wave</a></li>
              <li><a href="#the-overlap">The overlap</a></li>
              <li><a href="#whats-inside">What’s inside</a></li>
            </ul>
          </div>
          <div>
            <h2 className="footer__head">Code</h2>
            <ul>
              <li><a href={REPO} target="_blank" rel="noreferrer">GitHub</a></li>
              <li><a href={`${REPO}/tree/main/ios`} target="_blank" rel="noreferrer">iOS app</a></li>
              <li><a href={`${REPO}/tree/main/backend`} target="_blank" rel="noreferrer">Server</a></li>
              <li><a href={`${REPO}/tree/main/web`} target="_blank" rel="noreferrer">This site</a></li>
            </ul>
          </div>
          <div>
            <h2 className="footer__head">Page</h2>
            <ul>
              <li><a href="#top">Back to top</a></li>
            </ul>
          </div>
        </nav>
      </div>
      <p className="footer__legal">BUMP, a HackGT project.</p>
    </footer>
  )
}
