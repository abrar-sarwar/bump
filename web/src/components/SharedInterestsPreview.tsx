import { useState } from 'react'
import './sections.css'

/**
 * An ILLUSTRATIVE preview of what appears after two people connect.
 *
 * These are fictional example people. Every claimed overlap is present in both
 * example profiles below. The data is the single source of truth for the
 * highlighted interest and the opener, so the two can never drift apart. This
 * is not a live match and nothing here calls a model.
 */
type Example = {
  a: { name: string; interests: string[] }
  b: { name: string; interests: string[] }
  /** must appear in BOTH interest lists */
  shared: string
  opener: string
}

const EXAMPLES: Example[] = [
  {
    a: { name: 'Maya', interests: ['35mm photography', 'Night hiking', 'Ramen'] },
    b: { name: 'Dev', interests: ['Chess', '35mm photography', 'Baking sourdough'] },
    shared: '35mm photography',
    opener: 'What’s on the roll in your camera right now?',
  },
  {
    a: { name: 'Priya', interests: ['Jazz piano', 'Birding', 'Typography'] },
    b: { name: 'Theo', interests: ['Speedrunning', 'Jazz piano', 'Mechanical keyboards'] },
    shared: 'Jazz piano',
    opener: 'What’s one standard you never get tired of playing?',
  },
  {
    a: { name: 'Sam', interests: ['Board games', 'Night hiking', 'Collecting vinyl'] },
    b: { name: 'Rosa', interests: ['Night hiking', '35mm photography', 'Ramen'] },
    shared: 'Night hiking',
    opener: 'Where do you go when you want the trail to yourself?',
  },
]

// Guard the promise above: an example whose "shared" value is missing from
// either profile would be a fabricated overlap, so we refuse to render it.
const VALID = EXAMPLES.filter(
  (e) => e.a.interests.includes(e.shared) && e.b.interests.includes(e.shared),
)

function initials(name: string) {
  return name.slice(0, 1).toUpperCase()
}

export default function SharedInterestsPreview() {
  const [index, setIndex] = useState(0)
  const ex = VALID[index]

  return (
    <section id="the-overlap" className="section section--overlap">
      <div className="shell">
        <p className="eyebrow">The moment</p>
        <h2 className="overlap__heading">
          Two strangers.<br />One specific thing.
        </h2>

        <div className="overlap__layout">
          <div className="overlap__people">
            {[ex.a, ex.b].map((person, i) => (
              <article className="person" key={person.name}>
                <div className={`person__avatar person__avatar--${i === 0 ? 'blue' : 'orange'}`} aria-hidden="true">
                  {initials(person.name)}
                </div>
                <h3 className="person__name">{person.name}</h3>
                <ul className="person__interests">
                  {person.interests.map((interest) => (
                    <li
                      key={interest}
                      className={interest === ex.shared ? 'chip chip--shared' : 'chip'}
                    >
                      {interest}
                      {interest === ex.shared && <span className="sr-only">, shared interest</span>}
                    </li>
                  ))}
                </ul>
              </article>
            ))}
          </div>

          <div className="overlap__result">
            <p className="eyebrow">Something to talk about</p>
            {/* aria-live so switching examples is announced, not silent */}
            <p className="overlap__shared" aria-live="polite">
              You’re both into {ex.shared.toLowerCase()}.
            </p>
            <blockquote className="overlap__opener">{ex.opener}</blockquote>
            <p className="overlap__evidence">
              Both profiles list “{ex.shared}”. BUMP only ever shows what’s genuinely in
              both, and ranks by how specific it is, not by how rare, because we don’t
              have data on how common an interest is.
            </p>

            <div className="overlap__switch">
              <span className="overlap__switch-label" id="overlap-switch-label">Another example</span>
              <div className="overlap__dots" role="group" aria-labelledby="overlap-switch-label">
                {VALID.map((e, i) => (
                  <button
                    key={e.shared}
                    type="button"
                    className={i === index ? 'dot dot--on' : 'dot'}
                    aria-pressed={i === index}
                    onClick={() => setIndex(i)}
                  >
                    <span className="sr-only">
                      Example {i + 1}: {e.a.name} and {e.b.name}, {e.shared}
                    </span>
                  </button>
                ))}
              </div>
            </div>
          </div>
        </div>

        <p className="overlap__disclaimer">
          Illustrative preview with fictional people. Not a live match.
        </p>
      </div>
    </section>
  )
}
