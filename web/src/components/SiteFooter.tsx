import './sections.css'

export default function SiteFooter() {
  return (
    <footer className="footer">
      <div className="shell footer__inner">
        <p className="footer__note">BUMP, a HackGT project.</p>
        <nav aria-label="Footer">
          <ul className="footer__links">
            <li>
              <a href="https://github.com/abrar-sarwar/bump" target="_blank" rel="noreferrer">
                GitHub
              </a>
            </li>
            <li><a href="#top">Back to top</a></li>
          </ul>
        </nav>
      </div>
    </footer>
  )
}
