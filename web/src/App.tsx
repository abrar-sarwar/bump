import SiteHeader from './components/SiteHeader'
import BumpHero from './components/BumpHero'
import IntroSection from './components/IntroSection'
import Moments from './components/Moments'
import HowItWorks from './components/HowItWorks'
import SharedInterestsPreview from './components/SharedInterestsPreview'
import Wave from './components/Wave'
import Principles from './components/Principles'
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
        <Moments />
        <HowItWorks />
        <Wave />
        <SharedInterestsPreview />
        <Principles />
        <ClosingCTA />
      </main>
      <SiteFooter />
      <BackToTop />
    </>
  )
}
