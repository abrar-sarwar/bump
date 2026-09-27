# HackGT 13 master doc — the team's product intent

Source: Google Doc **"hackgt 13 master doc"** in the human's Drive.
https://docs.google.com/document/d/1aCkeknKKKiMR597b3e7gNnjD0QBogilSUifu6FqAhQY/edit
Read on 2026-09-26. The doc is the team's **plan and draft copy**; the repo is
**what is built**. Where they disagree, see "Conflicts" below: those are OPEN
and must be raised with the human, not resolved by an agent.

## What the doc says BUMP is

"An app to facilitate conversations between like-minded individuals."

Design references (Canva, not yet opened by any agent; needs Canva auth):
- Landing page: https://canva.link/8i2zgvtyj9b88ja
- UI bits: https://canva.link/2x02iuyqbh0wn00

### Three phases: Pre, During, Post

**Onboarding (Pre).** Grok is the main tool. User speaks an elevator pitch
into the mic; Grok fills in the profile; user can edit anything; user answers
a series of questions for interests.
- *"StreetPass"*: if a user is within Ultra Wideband distance, they get a
  notification: "hey this person just walked by you, bump them?"
- Stretch: optionally import profile/social data to enrich the profile
  ("find out if this is plausible").

**Bump -> Interests (During).** After the bump, Grok analyses and compares
interests and generates **2 to 4** points of mutual interest, which act as
conversation starters.
- Stretch: a richer connection "description" highlighting more abstract
  similarities (traits, tendencies).

**Rate Chat (Post).** When users leave each other's proximity they are
prompted to rate the interaction privately. Users can browse past connections
and their historical mutual interests.

## Draft landing page copy (doc says "QA please")

Verbatim, including its all-lowercase style:

- **short briefing:** "the social shortcut to finding your people."
- **what it does, expanded:** "bump makes meeting people easy. tap your phone,
  bump compares interests, experiences, goals, and things you both care about.
  you get the common ground instantly. shared interests come first. deeper
  connections come next. conversation starters help you turn the match into an
  actual conversation. less guessing. less small talk. more reasons to talk."
- **stretch / streetpass info:** "streetpass makes discovery more passive. when
  someone comes within ultrawide band range, bump can send a notification like
  'hey, this person just walked by you. bump them?' you only see a small teaser
  first. at most one mutual interest. just enough context to make the
  interaction feel worth starting. the full connection unlocks when you
  actually bump."
- **why bump?:** "meeting people is easy. knowing what to say is harder. bump
  removes the awkward search for common ground. it gives both people something
  real to talk about from the start."
  The author is considering putting the research below in a **dropdown**, and
  notes it "gotta include real research/citations":
  "research supports the idea. people tend to feel more positively toward
  others who share their attitudes and interests. one 2022 study found shared
  likes were especially strong signals of interpersonal liking. connection
  matters beyond the conversation too. the u.s. surgeon general identifies
  social connection as an important part of health and well-being, and
  recommends creating more opportunities for meaningful interaction and
  belonging. bump does not try to replace real connection. it helps start it"

## Cited research (as listed in the doc)

Why people avoid talking to strangers
- Epley & Schroeder (2014), "Mistakenly Seeking Solitude," *JEP: General*. https://doi.org/10.1037/a0037323
- Sandstrom & Boothby (2021), "Why do people avoid talking to strangers? A mini meta-analysis...," *Self and Identity*. https://doi.org/10.1080/15298868.2020.1816568

Why rare shared interests matter (doc: "your AI rarity scoring")
- Alves (2018), "Sharing Rare Attitudes Attracts," *PSPB*. https://journals.sagepub.com/doi/abs/10.1177/0146167218766861
- Vélez et al. (2019), "The rare preference effect," *Cognition*. https://www.sciencedirect.com/science/article/abs/pii/S0010027719301672

Why the "you both enjoyed it" reveal works
- Boothby, Cooney, Sandstrom & Clark (2018), "The Liking Gap in Conversations," *Psychological Science*. https://doi.org/10.1177/0956797618783714

Why even small connections help students
- Sandstrom & Dunn (2014), "Social Interactions and Well-Being: The Surprising Power of Weak Ties," *PSPB*. https://journals.sagepub.com/doi/abs/10.1177/0146167214529799

## Conflicts with the repo — OPEN, raised with the human 2026-09-26

Do not resolve these in code or copy until the human answers. Record the
answer in `50-decisions.md` and strike the item here.

1. **[PARTLY RESOLVED 2026-09-26]** Human: it goes on the site as in the
   works, name TBD. See decisions. The UWB technical caveat below still stands
   and has not been discussed. **StreetPass vs "never scans the room".** The doc wants passive UWB
   discovery of passers-by. The live site says "BUMP never scans the room for
   strangers" (HowItWorks step 1 note), and the iOS app has no such feature.
   Also technical: Nearby Interaction UWB ranging needs a session with an
   already-known peer (discovery tokens exchanged first), so "someone walked
   by" detection of strangers is not what UWB alone provides.
2. **Rarity vs specificity.** The doc cites rarity research for "your AI
   rarity scoring". The site says BUMP ranks "by how specific it is, not by how
   rare, because we don't have data on how common an interest is", which
   matches the iOS code today.
3. **2 to 4 points vs up to 3.** The doc says 2 to 4 mutual points generated
   by Grok. The app shows up to three shared interests, matched on the phone
   (InterestMatcher); Grok writes the talking points, not the matching.
4. **Rate Chat is not built.** No private rating flow exists in `ios/`.
   Saved connections do exist.
5. **Two unsourced research claims in the draft copy.** "one 2022 study found
   shared likes..." has no 2022 study in the citation list, and the U.S.
   Surgeon General claim has no citation (likely the 2023 advisory "Our
   Epidemic of Loneliness and Isolation", but unconfirmed). House rule: no
   unsourced claims ship.
6. **Voice and tagline.** Draft copy is all lowercase with the line "the
   social shortcut to finding your people." The site uses sentence case,
   uppercase BUMP, and "Meet someone. Find your overlap." Which is canonical?
7. **Scope of matching.** Draft copy says BUMP compares "interests,
   experiences, goals, and things you both care about" and "deeper connections
   come next". The app compares interests only today.
8. **Canva designs.** The doc links a Canva landing page and UI bits. Is the
   Canva landing page the target the site should match, or a reference?
