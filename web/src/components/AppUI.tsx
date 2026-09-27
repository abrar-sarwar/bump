import './AppUI.css'

/**
 * Pieces of the iOS app's ACTUAL UI, for the site to show. Each mirrors a
 * real SwiftUI view, with its real copy:
 *
 *   WaveNotice   StreetPassNotifier.notify (the Wave notification)
 *   WaveCard     View/StreetPassSheet.swift (the Wave pass card)
 *   StatusPill   Design/Components.swift StatusPill (Bump tab status)
 *   ConfirmCard  View/ConfirmPartnerView.swift
 *   RevealRow    View/RevealView.swift ("You + Partner", shared chips)
 *
 * Styling follows ios-mockup/components.css (the app's design contract):
 * Archivo, sentence case, flat white cards with a hairline, flat tonal
 * discs, status pills with a coloured dot. Decorative copies: every use is
 * aria-hidden by the caller, or inside an aria-hidden layer.
 *
 * The example people are the site's own fictional data. Maya and Rosa both
 * list photography and night hiking (see SharedInterestsPreview), so a Wave
 * card between them honestly shows one in the clear and one blurred. Rosa is
 * the one who walks by. Change the examples there and here together.
 */

export function StatusPill({ text, tone = 'good' }: { text: string; tone?: 'good' | 'active' }) {
  return (
    <span className="app-pill">
      <span className={`app-pill__dot app-pill__dot--${tone}`} />
      {text}
    </span>
  )
}

function Avatar({ letter, warm = false, size = 'm' }: { letter: string; warm?: boolean; size?: 'm' | 'l' }) {
  return <span className={`app-avatar app-avatar--${size}${warm ? ' app-avatar--warm' : ''}`}>{letter}</span>
}

/** The notification Wave sends if the app isn't open at that moment. */
export function WaveNotice() {
  return (
    <div className="app-ui app-notice">
      <span className="app-notice__tile"><md-icon>waving_hand</md-icon></span>
      <div className="app-notice__text">
        <p className="app-notice__meta"><strong>BUMP</strong> now</p>
        <p className="app-notice__title">hey, this person just walked by you. bump them?</p>
        <p className="app-notice__body">You’re both into photography.</p>
      </div>
    </div>
  )
}

/** The Wave pass card: avatar with radar rings, one interest in the clear,
 *  the rest blurred, and the two actions. */
export function WaveCard() {
  return (
    <div className="app-ui app-card app-wave">
      <div className="app-wave__hero">
        <span className="app-wave__ring" />
        <span className="app-wave__ring app-wave__ring--2" />
        <Avatar letter="R" warm size="l" />
      </div>
      <div className="app-wave__who">
        <p className="app-wave__name">Rosa</p>
        <p className="app-wave__sub">just walked by you</p>
      </div>
      <div className="app-wave__common">
        <StatusPill text="You’re both into photography." />
        <span className="app-pill app-pill--blur"><span className="app-pill__dot app-pill__dot--good" />You’re both into night hiking.</span>
        <p className="app-wave__hint">bump to see the rest</p>
      </div>
      <div className="app-wave__actions">
        <span className="app-btn app-btn--primary">Bump them</span>
        <span className="app-btn app-btn--text">Not now</span>
      </div>
    </div>
  )
}

/** "Did you bump with Rosa?", compact. */
export function ConfirmCard() {
  return (
    <div className="app-ui app-card app-confirm">
      <div className="app-confirm__head">
        <Avatar letter="R" warm />
        <div>
          <p className="app-eyebrow">Did you bump with</p>
          <p className="app-confirm__name">Rosa</p>
        </div>
      </div>
      <StatusPill text="Matched thru BUMP" />
      <span className="app-btn app-btn--primary">
        Confirm &amp; share interests <md-icon>check</md-icon>
      </span>
      <span className="app-btn app-btn--text">Not this person</span>
    </div>
  )
}

/** "Maya + Rosa" with the shared chips, as on the reveal screen. */
export function RevealRow() {
  return (
    <div className="app-ui app-card app-reveal">
      <p className="app-reveal__title">Maya + Rosa</p>
      <div className="app-reveal__chips">
        <span className="app-chip"><md-icon>check</md-icon>Photography</span>
        <span className="app-chip"><md-icon>check</md-icon>Night hiking</span>
      </div>
    </div>
  )
}
