import Wordmark from './Wordmark'
import './sections.css'

const REPO = 'https://github.com/abrar-sarwar/bump'

/**
 * The closing panel: the original solid blue, stripped to the wordmark, one
 * line and one action.
 * Real destinations only: an in-page anchor and the actual repository.
 */
export default function ClosingCTA() {
  return (
    <section className="section closing">
      <div className="shell closing__inner">
        <h2 className="sr-only">Make the first move with BUMP.</h2>
        <Wordmark className="closing__mark" label="BUMP" />
        <p className="closing__line" aria-hidden="true">Make the first move.</p>
        <div className="closing__actions">
          <md-filled-button href="#how-it-works">See how it works</md-filled-button>
          <a className="closing__link" href={REPO} target="_blank" rel="noreferrer">
            Read the code <span aria-hidden="true">→</span>
          </a>
        </div>
      </div>
    </section>
  )
}
