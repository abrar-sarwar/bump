import type React from 'react'
import Shapes, { type ShapeSpec } from './Shapes'
import './sections.css'

/**
 * The problem, and the research behind how BUMP works.
 *
 * Every number and finding here comes from a cited source; the citations are
 * the team's list in the HackGT master doc (.agents/60-master-doc.md). Keep
 * each summary to what the paper actually found. The site does NOT claim
 * BUMP scores rarity: it ranks by specificity (see SharedInterestsPreview).
 * The rarity papers are cited for why a specific overlap beats a broad one.
 */
const STATS = [
  {
    icon: 'groups',
    label: 'worldwide',
    tone: 'primary',
    figure: '1 in 6',
    line: 'people experience loneliness and struggle with social interaction.',
    cite: <>World Health Organization. (2025). <i>From loneliness to social connection.</i> Report of the WHO Commission on Social Connection.</>,
  },
  {
    icon: 'waving_hand',
    label: 'the first hello',
    tone: 'tertiary',
    figure: '60%',
    line: 'of adults are scared to approach others to start a conversation.',
    cite: <>Sandstrom, G. M., &amp; Boothby, E. J. (2021). Why do people avoid talking to strangers? <i>Self and Identity, 20</i>(1), 47–71.</>,
  },
]

type Paper = { cite: React.ReactNode; href: string }
const REASONS: { icon: string; shape: string; question: string; finding: string; papers: Paper[] }[] = [
  {
    icon: 'sentiment_worried',
    shape: 'cookie',
    question: 'Why people don’t say hi',
    finding: 'People expect talking to a stranger to go worse than it does. When they actually do it, it’s more pleasant than staying quiet.',
    papers: [
      { cite: <>Epley &amp; Schroeder (2014). Mistakenly seeking solitude. <i>Journal of Experimental Psychology: General.</i></>, href: 'https://doi.org/10.1037/a0037323' },
      { cite: <>Sandstrom &amp; Boothby (2021). Why do people avoid talking to strangers? <i>Self and Identity.</i></>, href: 'https://doi.org/10.1080/15298868.2020.1816568' },
    ],
  },
  {
    icon: 'diamond',
    shape: 'clover',
    question: 'Why specific beats broad',
    finding: 'Sharing something uncommon draws people together more than sharing something everyone likes. “We both like music” says little.',
    papers: [
      { cite: <>Alves (2018). Sharing rare attitudes attracts. <i>Personality and Social Psychology Bulletin.</i></>, href: 'https://journals.sagepub.com/doi/abs/10.1177/0146167218766861' },
      { cite: <>Vélez et al. (2019). The rare preference effect. <i>Cognition.</i></>, href: 'https://www.sciencedirect.com/science/article/abs/pii/S0010027719301672' },
    ],
  },
  {
    icon: 'favorite',
    shape: 'flower',
    question: 'Why the reveal matters',
    finding: 'After a conversation, people underestimate how much the other person liked them. Seeing real common ground helps close that gap.',
    papers: [
      { cite: <>Boothby, Cooney, Sandstrom &amp; Clark (2018). The liking gap in conversations. <i>Psychological Science.</i></>, href: 'https://doi.org/10.1177/0956797618783714' },
    ],
  },
  {
    icon: 'school',
    shape: 'sunny',
    question: 'Why small connections count',
    finding: 'Everyday interactions with acquaintances, not just close friends, are linked to feeling happier and more connected, including for students.',
    papers: [
      { cite: <>Sandstrom &amp; Dunn (2014). Social interactions and well-being: the surprising power of weak ties. <i>Personality and Social Psychology Bulletin.</i></>, href: 'https://journals.sagepub.com/doi/abs/10.1177/0146167214529799' },
    ],
  },
]

const SHAPES: ShapeSpec[] = [
  { shape: 'sunny', at: { left: '3%', top: '3%' }, size: 150, turn: 18, drift: -60, mobile: true },
  { shape: 'flower', at: { right: '4%', top: '4%' }, size: 140, fill: true, turn: -14, drift: -80 },
  { shape: 'pill', at: { left: '6%', bottom: '4%' }, size: 140, turn: 10, drift: -50, tone: 'secondary' },
]

export default function Problem() {
  return (
    <section id="the-problem" className="section folk-section problem">
      <Shapes set={SHAPES} />
      <div className="shell">
        <header className="folk-head">
          <p className="folk-eyebrow">The problem</p>
          <h2 className="folk-title">Proximity does not guarantee connection.</h2>
        </header>

        <div className="problem__stats">
          {STATS.map((s) => (
            <figure key={s.figure} className={`problem__stat problem__stat--${s.tone}`}>
              <p className="folk-bento__label">
                <md-icon aria-hidden="true">{s.icon}</md-icon>
                {s.label}
              </p>
              <p className="problem__figure">{s.figure}</p>
              <p className="problem__line">{s.line}</p>
              <figcaption className="problem__cite">{s.cite}</figcaption>
            </figure>
          ))}
        </div>

        <h3 className="problem__why">The research behind how BUMP works</h3>
        <ul className="problem__reasons">
          {REASONS.map((r) => (
            <li key={r.question} className="folk-card problem__reason">
              <span className={`folk-orb folk-orb--sm folk-orb--primary md-shape md-shape--${r.shape}`} aria-hidden="true">
                <md-icon>{r.icon}</md-icon>
              </span>
              <h4 className="problem__q">{r.question}</h4>
              <p className="problem__finding">{r.finding}</p>
              <ul className="problem__papers">
                {r.papers.map((p) => (
                  <li key={p.href}>
                    <a href={p.href} target="_blank" rel="noreferrer">{p.cite}</a>
                  </li>
                ))}
              </ul>
            </li>
          ))}
        </ul>
      </div>
    </section>
  )
}
