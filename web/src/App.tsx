import SiteHeader from './components/SiteHeader'
import BumpHero from './components/BumpHero'
import IntroSection from './components/IntroSection'
import HowItWorks from './components/HowItWorks'
import SharedInterestsPreview from './components/SharedInterestsPreview'
import ClosingCTA from './components/ClosingCTA'
import SiteFooter from './components/SiteFooter'

export default function App() {
  return (
    <>
      <span id="top" />
      <SiteHeader />
      <main id="main">
        <BumpHero />
        <IntroSection />
        <HowItWorks />
        <SharedInterestsPreview />
        <ClosingCTA />
      </main>
      <SiteFooter />
    </>
  )
}
