import { useState } from 'react'
import './sections.css'
import Shapes, { type ShapeSpec } from './Shapes'
import SharedBadge from './SharedBadge'

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
    a: { name: 'Maya', interests: ['Anime', 'Photography', 'Night hiking'] },
    b: { name: 'Dev', interests: ['Chess', 'Anime', 'Baking sourdough'] },
    shared: 'Anime',
    opener: 'What are you watching this season?',
  },
  {
    a: { name: 'Priya', interests: ['Jazz piano', 'Birding', 'Typography'] },
    b: { name: 'Theo', interests: ['Speedrunning', 'Jazz piano', 'Mechanical keyboards'] },
    shared: 'Jazz piano',
    opener: 'What’s one standard you never get tired of playing?',
  },
  {
    a: { name: 'Sam', interests: ['Board games', 'Night hiking', 'Collecting vinyl'] },
    b: { name: 'Rosa', interests: ['Night hiking', 'Astronomy', 'Photography'] },
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

// Margin shapes for this section (see Shapes.tsx).
const SHAPES: ShapeSpec[] = [
  { shape: 'flower', at: { left: '5%', top: '5%' }, size: 150, turn: 18, drift: -70, mobile: true },
  { shape: 'circle', at: { right: '7%', top: '9%' }, size: 90, fill: true, drift: -90, tone: 'tertiary' },
  { shape: 'cookie', at: { right: '3%', bottom: '6%' }, size: 130, turn: -14, drift: -60, tone: 'secondary' },
]

export default function SharedInterestsPreview() {
  const [index, setIndex] = useState(0)
  const ex = VALID[index]

  return (
    <section id="the-overlap" className="section folk-section">
      <Shapes set={SHAPES} />
      <div className="shell">
        <header className="folk-head">
          <p className="folk-eyebrow">The moment</p>
          <h2 className="folk-title">Two strangers. One specific thing.</h2>
        </header>

        {/* folk's pill tabs, as a single-select of real buttons. aria-pressed
            says which example is showing; the result below is aria-live. */}
        <div className="folk-pills" role="group" aria-label="Choose an example">
          {VALID.map((e, i) => (
            <button
              key={e.shared}
              type="button"
              className={i === index ? 'folk-pill folk-pill--on' : 'folk-pill'}
              aria-pressed={i === index}
              onClick={() => setIndex(i)}
            >
              {e.a.name} and {e.b.name}
            </button>
          ))}
        </div>

        <div className="overlap__layout">
          <div className="overlap__people">
            {[ex.a, ex.b].map((person, i) => (
              <article className="folk-card person" key={person.name}>
                <span className={`folk-orb folk-orb--lg person__avatar person__avatar--${i === 0 ? 'blue' : 'orange'}`} aria-hidden="true">
                  {initials(person.name)}
                </span>
                <div className="person__content">
                  <h3 className="person__name">{person.name}</h3>
                  <p className="person__by">fictional example</p>
                  <ul className="person__interests">
                    {person.interests.map((interest) => (
                      <li
                        key={interest}
                        className={interest === ex.shared ? 'tag tag--shared' : 'tag'}
                      >
                        {interest === ex.shared && <md-icon aria-hidden="true">check</md-icon>}
                        {interest}
                        {interest === ex.shared && <span className="sr-only">, shared interest</span>}
                      </li>
                    ))}
                  </ul>
                </div>
              </article>
            ))}
          </div>

          <div className="folk-bento folk-bento--sky overlap__result">
            <p className="folk-bento__label">
              <md-icon aria-hidden="true">chat_bubble</md-icon>
              Something to talk about
            </p>
            <div className="overlap__pair">
              <SharedBadge interest={ex.shared} />
              {/* Your reply: the opener, as something you'd actually say. */}
              <blockquote className="overlap__reply">
                <span className="overlap__reply-who">You</span>
                “{ex.opener}”
              </blockquote>
            </div>
          </div>
        </div>

        <p className="overlap__evidence">
          Both profiles list “{ex.shared}”. BUMP only ever shows what’s genuinely in
          both, and ranks by how specific it is, not by how rare, because we don’t
          have data on how common an interest is.
        </p>
        <p className="overlap__disclaimer">
          Illustrative preview with fictional people. Not a live match.
        </p>
      </div>
    </section>
  )
}
