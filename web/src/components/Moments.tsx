import './sections.css'
import Shapes, { type ShapeSpec } from './Shapes'

/**
 * folk's "try these" grid, for BUMP: the specific moments where you'd
 * usually say nothing. Each pairs a situation people recognise with the kind
 * of overlap that could come out of it.
 *
 * These are EXAMPLES, labelled as such below the grid. They describe the kind
 * of thing BUMP shows, not a claim about anyone's result: the overlap is only
 * ever what both people actually put in their profiles.
 */
const MOMENTS = [
  { icon: 'school', tone: 'primary', who: 'the person you sit next to every lecture', turns: 'you both climb' },
  { icon: 'terminal', tone: 'tertiary', who: 'your hackathon team at 2am', turns: 'you all hate writing css' },
  { icon: 'celebration', tone: 'secondary', who: 'the mixer where everyone asks your major', turns: 'skip to the thing you both love' },
  { icon: 'work', tone: 'primary', who: 'the new hire at the next desk', turns: 'you both watch f1' },
  { icon: 'music_note', tone: 'tertiary', who: 'the stranger in your favourite band’s shirt', turns: 'you both saw them live' },
  { icon: 'restaurant', tone: 'secondary', who: 'the person in line at the same food truck', turns: 'you both rank ramen spots' },
  { icon: 'biotech', tone: 'primary', who: 'the lab partner you’ve never really talked to', turns: 'you both play chess' },
  { icon: 'home', tone: 'tertiary', who: 'your roommate’s friend you keep running into', turns: 'you both bake sourdough' },
]

// Margin shapes for this section (see Shapes.tsx).
const SHAPES: ShapeSpec[] = [
  { shape: 'sunny', at: { right: '3%', top: '4%' }, size: 130, turn: 20, drift: -50, tone: 'secondary' },
  { shape: 'clover', at: { left: '2%', top: '8%' }, size: 110, fill: true, turn: -16, drift: -70 },
]

// Flat MD3 shapes for the icon containers, cycled so no two neighbours match.
const SHAPE_CYCLE = ['cookie', 'clover', 'sunny', 'flower', 'pentagon']

export default function Moments() {
  return (
    <section id="made-for" className="section folk-section moments">
      <Shapes set={SHAPES} />
      <div className="shell">
        <header className="folk-head">
          <p className="folk-eyebrow">Made for</p>
          <h2 className="folk-title">Every “we should talk” you never followed up on.</h2>
        </header>

        <ul className="moments__grid">
          {MOMENTS.map((m, i) => (
            <li key={m.who} className="folk-chip moment">
              <span className={`folk-orb folk-orb--sm folk-orb--${m.tone} md-shape md-shape--${SHAPE_CYCLE[i % SHAPE_CYCLE.length]}`} aria-hidden="true">
                <md-icon>{m.icon}</md-icon>
              </span>
              <span className="folk-chip__text">
                <strong>{m.who}</strong>
                <span><span className="folk-chip__with">turns out</span> {m.turns}</span>
              </span>
            </li>
          ))}
        </ul>

        <p className="moments__note">
          Examples. Your overlap is only ever what you both actually put in your profiles.
        </p>
      </div>
    </section>
  )
}
