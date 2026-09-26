import './sections.css'

export default function IntroSection() {
  return (
    <section id="the-idea" className="section section--intro">
      <div className="shell intro__grid">
        <p className="eyebrow intro__eyebrow">The idea</p>
        <h2 className="intro__statement">
          You already have<br />something in common.
        </h2>
        <div className="intro__body">
          <p>
            BUMP helps you turn a first hello into a real conversation. Bring your
            phones together, confirm the connection, and find the interests you share.
          </p>
          <p className="intro__aside">
            Not a feed. Not a follow. One gesture, one person, one thing worth talking about.
          </p>
        </div>
      </div>
    </section>
  )
}
