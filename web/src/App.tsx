import SiteHeader from './components/SiteHeader'
import BumpHero from './components/BumpHero'
import IntroSection from './components/IntroSection'
import Problem from './components/Problem'
import Moments from './components/Moments'
import HowItWorks from './components/HowItWorks'
import SharedInterestsPreview from './components/SharedInterestsPreview'
import Wave from './components/Wave'
import Principles from './components/Principles'
import TechStack from './components/TechStack'
import ClosingCTA from './components/ClosingCTA'
import BackToTop from './components/BackToTop'
import SiteFooter from './components/SiteFooter'

export default function App() {
  return (
    <>
      <span id="top" />
      <SiteHeader />
      <main id="main">
        <BumpHero />
        <IntroSection />
        <Problem />
        <Moments />
        <HowItWorks />
        <Wave />
        <SharedInterestsPreview />
        <Principles />
        <TechStack />
        <ClosingCTA />
      </main>
      <SiteFooter />
      <BackToTop />
    </>
  )
}
