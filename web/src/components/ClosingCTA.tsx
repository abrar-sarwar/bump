import Wordmark from './Wordmark'
import './sections.css'

const REPO = 'https://github.com/abrar-sarwar/bump'

export default function ClosingCTA() {
  return (
    <section className="section section--cta">
      <div className="shell cta__inner">
        <h2 className="cta__heading">Make the first move.</h2>
        <Wordmark className="cta__mark" label="BUMP" />
        <p className="cta__line">
          BUMP is being built at HackGT. The iOS app runs entirely between nearby
          phones. No account, no server, no cloud.
        </p>
        <div className="cta__actions">
          {/* Real destinations only: an in-page anchor and the actual repository.
              No download badge, no fake waitlist, no invented link. */}
          <a className="btn btn--on-blue" href="#how-it-works">See how it works</a>
          <a className="btn cta__ghost" href={REPO} target="_blank" rel="noreferrer">
            Read the code on GitHub
          </a>
        </div>
      </div>
    </section>
  )
}
