/*
 * screens.js: every screen and state of the app, transcribed from the SwiftUI
 * views. Copy is verbatim from the Swift source; change it here first, then
 * port. Each entry names the Swift file it mirrors.
 *
 * Sample data is PreviewFixtures.swift: obviously fictional people.
 */
(function () {
  const { esc, icon, text: T } = ui;

  // MARK: PreviewFixtures

  const ME = { name: "Jared", bio: "Building things at 2am.", interests: ["Jazz", "Baking", "Photography", "RPGs", "Coffee"] };
  const PARTNER = { name: "Sample Partner (demo)", bio: "Demo data. Not a real person." };
  const SAMPLE_INTRO = "Hi, I'm Sam. I play jazz piano and I've been getting into climbing. I work at a robotics lab. I'd love to meet people building hardware.";
  const REVEAL = {
    evidence: "Matched by motion + UWB",
    highlights: [
      { statement: "You're both into jazz.", entry: "Jazz", point: "How did each of you get into jazz?" },
      { statement: "You're both into photography.", entry: "Photography", point: "How did each of you get into photography?" },
    ],
    worthAsking: [
      { prompt: "One of you listed “Baking” and the other “Learn to bake bread”. Anything to swap notes on?", you: "Baking", them: "Learn to bake bread" },
      { prompt: "One of you is into coffee and the other espresso. Where do those overlap?", you: "Coffee", them: "Espresso" },
    ],
    opener: "What's one jazz record you never get tired of?",
    openerSource: "Suggested question",
  };

  // InterestCatalog.groups (Interest.swift)
  const CATALOG = [
    ["Music", ["Jazz", "Hip-hop", "Indie", "Electronic music", "K-pop", "R&B", "Live music", "Festivals", "Playing an instrument", "Making music", "Singing"]],
    ["Coffee", ["Espresso", "Pour-over", "Cold brew", "Lattes", "Café hopping", "Brewing coffee at home"]],
    ["Food & drink", ["Cooking", "Baking", "Trying new restaurants", "Spicy food", "Street food", "Brunch", "Tea", "Matcha", "Boba"]],
    ["Sports & fitness", ["Gym", "Running", "Climbing", "Basketball", "Soccer", "Tennis", "Yoga", "Martial arts", "Cycling", "Dancing"]],
    ["Gaming", ["RPGs", "Shooters", "Cozy games", "Esports", "Retro games", "Board games", "Chess", "Tabletop RPGs"]],
    ["Movies & TV", ["Movies", "Anime", "Horror", "Reality TV", "Documentaries", "YouTube"]],
    ["Collecting", ["Vinyl records", "Figures", "Trading cards", "Sneakers", "Rocks & minerals", "Coins", "LEGO", "Thrifting"]],
    ["Outdoors", ["Hiking", "Camping", "Beach days", "Surfing", "Fishing", "Plants", "Stargazing"]],
    ["Tech", ["Coding", "AI", "Startups", "Hardware", "Robotics", "3D printing", "Mechanical keyboards", "Game dev"]],
    ["Art & design", ["Drawing", "Painting", "Photography", "Graphic design", "Fashion", "Crafts", "Filmmaking"]],
    ["Books & stories", ["Fiction", "Sci-fi", "Fantasy", "Manga", "Comics", "Poetry", "Podcasts", "Writing"]],
    ["Travel", ["Road trips", "Backpacking", "Learning languages", "City trips", "Food trips"]],
  ];

  // MARK: Shared pieces

  /** OnboardingFlow.topBar */
  const onbTop = (step, back) => `<div class="h" style="padding:0 var(--Space-s);height:44px;flex:none">
      <button class="link c-navy" style="width:44px;height:44px;display:grid;place-items:center;${step === 0 ? "opacity:0;pointer-events:none" : ""}" aria-label="Back" data-go="${back || ""}">${icon.chevronLeft(19)}</button>
      <div class="spacer"></div>${ui.steps(step, 4)}<div class="spacer"></div><div style="width:44px"></div></div>`;

  /** OnboardingFlow step: top bar + Screen + BottomBar */
  const onb = (step, back, body, bottom = "") => `${onbTop(step, back)}${ui.screen(body)}${bottom ? ui.bottomBar(bottom) : ""}`;

  const titleBlock = (title, sub) => `<div class="v lead gap-s">${T("screenTitle", "navy", esc(title))}${T("body", "secondary", esc(sub))}</div>`;

  /** BumpScreen.title(_:_:) */
  const centerTitle = (heading, detail) => `<div class="v center gap-s" style="padding:0 var(--Space-m)">${T("screenTitle", "navy", esc(heading), "t-center")}${T("body", "secondary", esc(detail), "t-center")}</div>`;

  /** BumpScreen: NavigationStack with the wordmark in the principal slot */
  const bumpNav = () => ui.nav({ principal: ui.wordmark() });

  /** BumpScreen.nearbyPeople */
  const nearby = (names) => names.length ? `<div class="v center gap-s">${ui.pill(names.length === 1 ? "1 person nearby" : `${names.length} people nearby`, "good")}
      <div class="avatar-stack">${names.slice(0, 6).map((n) => ui.avatar(n, 36, { ring: true })).join("")}</div></div>` : "";

  /** BumpScreen.statusCard */
  const statusCard = (title, body, tone, busy, actions) => `<div class="v stretch gap-m">
      ${ui.card(`<div class="v lead gap-m"><div class="h gap-s">${busy ? ui.spinner() : ""}${ui.pill(title, tone, true)}</div>${T("body", "secondary", esc(body))}</div>`)}
      ${actions.map(([label, primary, go]) => ui.btn(label, primary ? "primary" : "secondary", { go })).join("")}</div>`;

  const bumpScreen = (inner, header = "") => bumpNav() + ui.screen(`<div class="v stretch gap-l">${header}${inner}</div>`);

  /** RevealView highlight card / ConnectionDetail */
  const highlightCard = (h, i, animate) => ui.card(`<div class="v lead gap-xs">
      ${T("bodyEmphasis", "navy", esc(h.statement))}
      ${T("caption", "secondary", `Both of you list “${esc(h.entry)}”`)}
      <div class="h top gap-s" style="padding-top:var(--Space-xs)"><span class="c-action" style="padding-top:3px">${icon.bubble()}</span>${T("body", "navy", esc(h.point))}</div>
    </div>`, { cls: animate ? "reveal-in" : "", style: animate ? `animation-delay:${i * 0.09}s` : "" });

  /** TalkingPointsSection */
  const talkingPoints = () => `<div class="v stretch gap-m"><div class="v stretch gap-s">${T("caption", "secondary", "Worth asking about")}
      ${REVEAL.worthAsking.map((p) => ui.card(`<div class="v lead gap-xs">${T("bodyEmphasis", "navy", esc(p.prompt))}${T("caption", "secondary", `You: “${esc(p.you)}” · Them: “${esc(p.them)}”`)}</div>`)).join("")}</div>
      ${T("caption", "secondary", "Suggested questions, built from both cards")}</div>`;

  /** TopicBrowser */
  const topicBrowser = (st, key) => {
    const sel = st[key];
    const opened = st.opened[key];
    const topics = ui.flow(CATALOG.map(([cat]) => ui.chip(cat, { selected: sel.has(cat), act: "toggleTopic", arg: `${key}|${cat}` })).join(""));
    const open = CATALOG.filter(([cat, kids]) => opened.has(cat) || sel.has(cat) || kids.some((k) => sel.has(k)));
    return `<div class="v stretch gap-m">${topics}${open.map(([cat, kids]) => `<div class="v lead gap-s" style="padding:var(--Space-m);background:var(--BumpColor-surface);border-radius:var(--Space-corner)">
        ${T("caption", "secondary", `${esc(cat)}: anything more specific?`)}
        ${ui.flow(kids.map((k) => ui.chip(k, { selected: sel.has(k), act: "toggleChip", arg: `${key}|${k}` })).join(""))}</div>`).join("")}</div>`;
  };

  // MARK: Screens

  const S = []; // registry
  const add = (group, id, title, swift, render, opts = {}) => S.push({ group, id, title, swift, render, ...opts });

  // ── Start ──
  add("Start", "welcome", "Welcome", "View/WelcomeView.swift", () => `
    <div class="v center gap-l" style="flex:1;padding-bottom:var(--safe-bottom)">
      <div style="flex:1;min-height:24px"></div>
      <div style="padding:0 var(--Space-gutter)">${ui.wordmark("hero")}</div>
      ${T("screenTitle", "navy", "Meet someone. Find your overlap.", "t-center\" style=\"padding:0 var(--Space-xl)")}
      <div style="padding:var(--Space-s) 0">${ui.phones(true)}</div>
      ${T("body", "secondary", "Tap phones with someone new. BUMP finds the specific things you actually have in common, and gives you something to say.", "t-center\" style=\"padding:0 var(--Space-xl)")}
      <div style="flex:1;min-height:16px"></div>
      <div class="fill-w" style="padding:0 var(--Space-gutter) var(--Space-l)">${ui.btn("Get started", "primary", { go: "onb-name" })}</div>
    </div>`);

  // ── Onboarding ──
  add("Onboarding", "onb-name", "1 · Name", "View/OnboardingFlow.swift · NameStep", (st) => onb(0, "", `
    <div class="v lead gap-l">${ui.wordmark()}
      ${T("screenTitle", "navy", "What should we call you?")}
      ${T("body", "secondary", "This is the name people see after you bump.")}
      <div class="fill-w">${ui.field({ label: "Your name", placeholder: "First name is fine", value: st.name, bind: "name" })}</div>
    </div>`, ui.btn("Continue", "primary", { go: "onb-consent", disabled: !st.name.trim() })));

  const introHead = titleBlock("Introduce yourself", "Say what you're into, what you've done, and what you're hoping to find. We'll turn it into a card you can edit.");
  const skipIntro = ui.link("Skip, I'll pick interests myself", "t-caption c-secondary\" style=\"padding-top:var(--Space-xs)", { go: "onb-card" });

  add("Onboarding", "onb-consent", "2 · Intro, consent", "View/OnboardingFlow.swift · CloudConsentCard", () => onb(1, "onb-name", `
    <div class="v stretch gap-l">${introHead}
      ${ui.card(`<div class="v stretch gap-m">
        <div class="h gap-s t-bodyEmphasis c-navy"><span style="display:flex;color:var(--BumpColor-action)">${icon.lockShield()}</span>Before anything leaves your phone</div>
        ${T("caption", "navy", "To transcribe your intro and suggest a card, BUMP sends your recording, anything you type here, and your answers to the BUMP server, which passes them to xAI's Grok.")}
        ${T("caption", "secondary", "The BUMP server doesn't store your audio or text. xAI's documentation says API requests are kept for up to 30 days for auditing. Later, if you and the person you bump both allow it, your shared interests are sent the same way to write talking points.")}
        ${ui.btn("Allow cloud processing", "primary", { go: "onb-record" })}
        ${ui.btn("Keep everything on this phone", "secondary", { go: "onb-typing" })}
        ${T("caption", "secondary", "On this phone you type instead of speak. You can change this any time in You.")}
      </div>`, { l: true })}
    </div>`));

  add("Onboarding", "onb-record", "2 · Intro, record", "View/OnboardingFlow.swift · recorderPanel .idle", () => onb(1, "onb-name", `
    <div class="v stretch gap-l">${introHead}
      <div class="v center gap-m">
        <button class="record-btn" aria-label="Start recording" data-go="onb-recording">${icon.mic()}</button>
        ${T("caption", "secondary", "Tap to record · up to 45 seconds")}
        ${ui.link("Type instead", "t-bodyEmphasis c-action", { go: "onb-typing-cloud" })}
      </div>
    </div>`, skipIntro));

  add("Onboarding", "onb-recording", "2 · Intro, recording", "View/OnboardingFlow.swift · recorderPanel .recording", () => onb(1, "onb-name", `
    <div class="v stretch gap-l">${introHead}
      <div class="v center gap-m">
        <button class="record-btn" aria-label="Stop recording" data-go="onb-transcribing"><span class="stop"></span></button>
        <div class="level"><i></i></div>
        ${T("bodyEmphasis", "navy", "0:31 left", "\" style=\"font-variant-numeric:tabular-nums")}
      </div>
    </div>`, skipIntro));

  add("Onboarding", "onb-transcribing", "2 · Intro, transcribing", "View/OnboardingFlow.swift · WorkingCard", () => onb(1, "onb-name", `
    <div class="v stretch gap-l">${introHead}
      <div data-auto="onb-transcript" data-delay="1600">${ui.workingCard("Transcribing…", "Turning your recording into text.", "onb-record")}</div>
    </div>`));

  add("Onboarding", "onb-transcript", "2 · Intro, transcript", "View/OnboardingFlow.swift · transcriptReview", (st) => onb(1, "onb-name", `
    <div class="v stretch gap-l">${introHead}
      <div class="v stretch gap-s">
        ${ui.sectionHeading("Here's what we heard", "Fix anything that's off before we draft your card. This text isn't saved or shared.")}
        ${ui.field({ label: "Transcript", value: st.transcript, bind: "transcript", lines: 4 })}
        <div class="h">${T("caption", "secondary", "Transcribed by xAI speech-to-text")}<div class="spacer"></div>${ui.link("Record again", "t-caption c-action", { go: "onb-record" })}</div>
      </div>
    </div>`, ui.btn("Draft my profile", "primary", { go: "onb-drafting", disabled: !st.transcript.trim() }) + skipIntro));

  add("Onboarding", "onb-typing", "2 · Intro, typing (on this phone)", "View/OnboardingFlow.swift · typingPanel", (st) => onb(1, "onb-name", `
    <div class="v stretch gap-l">${introHead}
      <div class="v stretch gap-s">
        ${ui.field({ label: "Your intro", placeholder: "I'm into…  I've been…  I'm hoping to…", value: st.typed, bind: "typed", lines: 4 })}
        <div class="h">${T("caption", "secondary", "Stays on this phone. Your phone suggests a card from this.")}</div>
      </div>
    </div>`, ui.btn("Draft my profile", "primary", { go: "onb-drafting", disabled: !st.typed.trim() }) + skipIntro));

  add("Onboarding", "onb-typing-cloud", "2 · Intro, typing (cloud)", "View/OnboardingFlow.swift · typingPanel", (st) => onb(1, "onb-name", `
    <div class="v stretch gap-l">${introHead}
      <div class="v stretch gap-s">
        ${ui.field({ label: "Your intro", placeholder: "I'm into…  I've been…  I'm hoping to…", value: st.typed, bind: "typed", lines: 4 })}
        <div class="h">${T("caption", "secondary", "Grok will suggest a card from this.")}<div class="spacer"></div>${ui.link("Record instead", "t-caption c-action", { go: "onb-record" })}</div>
      </div>
    </div>`, ui.btn("Draft my profile", "primary", { go: "onb-drafting", disabled: !st.typed.trim() }) + skipIntro));

  add("Onboarding", "onb-drafting", "2 · Intro, drafting", "View/OnboardingFlow.swift · WorkingCard", () => onb(1, "onb-name", `
    <div class="v stretch gap-l">${introHead}
      <div data-auto="onb-questions" data-delay="1600">${ui.workingCard("Drafting your profile…", "Grok is reading your intro.", "onb-transcript")}</div>
    </div>`));

  add("Onboarding", "onb-questions", "3 · Question", "View/OnboardingFlow.swift · QuestionsStep", (st) => onb(2, "onb-transcript", `
    <div class="v stretch gap-l">${titleBlock("A little more", "Up to three quick questions. Skip anything.")}
      <div class="v stretch gap-s">
        ${T("caption", "secondary", "Question 2 of up to 3")}
        ${ui.card(`<div class="v lead gap-s">${T("sectionTitle", "navy", "You mentioned climbing. Where do you usually go?")}${T("caption", "secondary", "Question from Grok")}</div>`)}
        ${ui.field({ label: "Your answer", placeholder: "A sentence is plenty", value: st.answer, bind: "answer", lines: 2 })}
      </div>
      <div class="v stretch gap-xs">
        <div class="h top gap-s c-secondary"><span style="padding-top:3px">${icon.check()}</span>${T("caption", "secondary", "What kind of hardware are you building?")}</div>
      </div>
    </div>`, ui.btn("Next", "primary", { go: "onb-card", disabled: !st.answer.trim() }) + `
    <div class="h t-caption c-secondary" style="padding-top:var(--Space-xs)">${ui.link("Skip question", "", { go: "onb-card" })}<div class="spacer"></div>${ui.link("Done with questions", "", { go: "onb-card" })}</div>`));

  const cardRow = (it) => `<div class="row">
      <button class="check ${it.on ? "on" : ""}" data-act="toggleItem" data-arg="${it.id}" aria-label="${it.on ? "Shared" : "Not shared"}: ${esc(it.text)}">${it.on ? icon.checkCircleFill() : icon.circle()}</button>
      <div class="v lead gap-2" style="flex:1;min-width:0;padding-top:5px">
        ${T("body", it.on ? "navy" : "secondary", esc(it.text), it.on ? "" : "struck")}
        ${it.evidence ? T("caption", "secondary", `From “${esc(it.evidence)}”`) : ""}
        ${T("caption2", "secondary", esc(it.origin))}
      </div>
      <button class="check" aria-label="More for ${esc(it.text)}">${icon.ellipsis()}</button>
    </div>`;

  const cardSection = (st, kind, title, empty) => {
    const items = st.items.filter((i) => i.kind === kind);
    return `<div class="v stretch gap-s">
      <div class="h">${T("sectionTitle", "navy", title)}<div class="spacer"></div><button class="link t-caption t-semibold c-action h gap-xs" aria-label="Add ${title.toLowerCase()}">${icon.plus(11)} Add</button></div>
      ${items.length ? `<div class="rows">${items.map(cardRow).join(`<div class="divider"></div>`)}</div>` : T("caption", "secondary", empty)}
      ${kind === "interest" ? `<button class="disclosure t-caption t-semibold ${st.browsing ? "open" : ""}" data-act="toggleBrowse">Browse interests ${icon.chevronRight(12)}</button>${st.browsing ? `<div style="padding-top:var(--Space-s)">${topicBrowser(st, "onbSelected")}</div>` : ""}` : ""}
    </div>`;
  };

  add("Onboarding", "onb-card", "4 · Your Bump card", "View/OnboardingFlow.swift · CardStep", (st) => {
    const canFinish = st.name.trim() && st.items.some((i) => i.on);
    return onb(3, "onb-questions", `
    <div class="v stretch gap-l">${titleBlock("Your Bump card", "Confirmed partners receive this card. Keep what's right, fix what isn't, and uncheck anything you'd rather not share.")}
      <div class="h top gap-m">${ui.photoAvatar(st.name, 64)}${ui.field({ label: "Name", placeholder: "Your name", value: st.name, bind: "name" })}</div>
      <div class="v stretch gap-xs">
        ${ui.field({ label: "Short bio (optional)", placeholder: "One line about you", value: st.bio, bind: "bio", lines: 1 })}
        ${T("caption", "secondary", "Suggested by Grok from your intro. Edit freely.")}
      </div>
      ${cardSection(st, "interest", "Interests", "Nothing yet. Add your own or browse below.")}
      ${cardSection(st, "experience", "Experiences", "Anything you've done, built, studied or worked on.")}
      ${cardSection(st, "goal", "Goals", "What you're hoping to find or do. Optional.")}
      ${T("caption", "secondary", "Only your name, photo, bio and the checked items are shared, and only with someone you've both confirmed after a bump. Your recording, transcript and answers are never saved or shared.")}
    </div>`, ui.btn("Start bumping", "primary", { go: "tutorial-0", disabled: !canFinish }) +
      (canFinish ? "" : T("caption", "secondary", "Add your name and check at least one thing to continue.")));
  });

  // ── Tutorial ──
  const TUTORIAL = [
    ["Find someone to meet", "You both open BUMP and tap Start bumping. No codes, no accounts. BUMP finds the phones around you.", "open"],
    ["Tap your phones together", "A gentle tap, back to back. That's how BUMP knows who you just met, and nobody else.", "tap"],
    ["Both say yes", "You each confirm who you bumped. Nothing is shared until you both do.", "confirm"],
    ["See what you share", "Your cards swap, and BUMP shows what you have in common plus a few things to talk about.", "share"],
  ];
  const tutorialArt = (art) => {
    if (art === "open") return ui.pulse(ui.phones(false));
    if (art === "tap") return ui.phones(true);
    if (art === "confirm") return `<div class="h gap-xl">${[["brand"], ["illustrationWarm"]].map(([c]) => `<div class="confirm-badge" style="background:var(--BumpColor-${c})"><span>${icon.check(22)}</span></div>`).join("")}</div>`;
    return `<div class="v center gap-s"><div class="avatar-stack" style="gap:0">${ui.avatar("You", 64)}<div style="margin-left:-12px">${ui.avatar("Them", 64, { warm: true })}</div></div>
      ${ui.flow(ui.chip("Climbing", { selected: true }) + ui.chip("Cold brew", { selected: true }) + ui.chip("Collecting"), "width:260px")}</div>`;
  };
  TUTORIAL.forEach(([title, body, art], i) => {
    const last = i === TUTORIAL.length - 1;
    add("Tutorial", `tutorial-${i}`, `${i + 1} · ${title}`, "View/BumpTutorial.swift", () => `
      <div class="h" style="padding:var(--Space-m) var(--Space-gutter) 0;flex:none"><div class="spacer"></div>
        ${ui.link("Skip", "t-bodyEmphasis c-secondary\" style=\"" + (last ? "opacity:0" : ""), { go: "bump-home" })}</div>
      <div class="v center gap-l" style="flex:1">
        <div style="flex:1;min-height:16px"></div>
        <div style="height:220px;display:grid;place-items:center;width:100%">${tutorialArt(art)}</div>
        <div class="v center gap-s" style="padding:0 var(--Space-xl)">${T("screenTitle", "navy", title, "t-center")}${T("body", "secondary", body, "t-center")}</div>
        <div style="flex:1"></div>
      </div>
      <div class="v center" style="padding-bottom:var(--Space-l)">${ui.steps(i, 4)}</div>
      <div style="padding:0 var(--Space-gutter) calc(var(--Space-l) + var(--safe-bottom))">${ui.btn(last ? "Let's bump" : "Next", "primary", { go: last ? "bump-home" : `tutorial-${i + 1}` })}</div>`);
  });

  // ── Bump ──
  const home = () => bumpScreen(`<div class="v center gap-l">
      <div style="padding-top:var(--Space-l)" class="fill-w">${ui.phones(true)}</div>
      <div class="v center gap-s" style="padding:0 var(--Space-m)">${T("screenTitle", "navy", "Meet someone new", "t-center")}${T("body", "secondary", "Tap phones with the person in front of you and see what you have in common.", "t-center")}</div>
      <div class="fill-w" style="padding-top:var(--Space-s)">${ui.btn("Start bumping", "primary", { go: "bump-looking" })}</div>
      ${ui.card(`<div class="v stretch gap-m">
        <div class="h">${T("bodyEmphasis", "navy", "How it works")}<div class="spacer"></div>${ui.link("Watch the tour", "t-caption t-semibold c-action", { go: "tutorial-0" })}</div>
        ${[["1", "You both tap Start bumping"], ["2", "Gently tap your phones together"], ["3", "Both confirm, then see what you share"]]
          .map(([n, t]) => `<div class="h gap-m"><span class="num">${n}</span>${T("body", "navy", t)}</div>`).join("")}
      </div>`)}
      ${ui.link("Have an event code?", "t-caption t-semibold c-secondary", { go: "bump-eventcode" })}
    </div>`);

  add("Bump", "bump-home", "Home", "View/BumpScreen.swift · roomSetup", home, { tabs: "bump" });

  add("Bump", "bump-eventcode", "Event code (sheet)", "View/BumpScreen.swift · eventCodeSheet", (st) => home(), {
    tabs: "bump",
    sheet: (st) => ({
      size: "medium", grabber: true,
      html: ui.nav({ title: "Event code", lead: ui.navText("Close", { go: "bump-home" }) }) + ui.screen(`<div class="v stretch gap-l">
        ${ui.sectionHeading("Join a specific event", "Only needed at big events. Everyone using the same code ends up together. A room holds up to 8 phones.")}
        ${ui.field({ label: "Event code", placeholder: "hackgt", value: st.code, bind: "code" })}
        ${ui.btn("Join this event", "primary", { go: "bump-event-ready", disabled: !st.code.trim() })}
        ${ui.btn("Host it on this phone", "secondary", { go: "bump-event-ready", disabled: !st.code.trim() })}
        <div class="v stretch gap-s">${T("caption", "secondary", "Events nearby")}${ui.flow(ui.chip("hackgt", { act: "joinEvent", arg: "hackgt" }) + ui.chip("hackgt-2", { act: "joinEvent", arg: "hackgt-2" }))}</div>
      </div>`),
    }),
  });

  add("Bump", "bump-looking", "Looking for people", "View/BumpScreen.swift · notReadyState", () => bumpScreen(`<div class="v center gap-l" data-auto="bump-ready" data-delay="2200">
      ${ui.pulse(ui.phones(false))}
      ${centerTitle("Looking for people nearby…", "Ask the person you want to meet to open BUMP and tap Start bumping.")}
      <div class="fill-w">${ui.btn("Stop bumping", "secondary", { go: "bump-home" })}</div>
    </div>`), { tabs: "bump" });

  add("Bump", "bump-ready", "Ready: tap phones", "View/BumpScreen.swift · readyState", () => bumpScreen(`<div class="v center gap-l">
      ${ui.pulse(ui.phones(true))}
      ${centerTitle("Tap your phones together", "A gentle tap, back to back, with the person you want to meet. BUMP is listening.")}
      ${nearby([PARTNER.name])}
      <div class="fill-w">${ui.btn("Stop bumping", "secondary", { go: "bump-home" })}</div>
      ${ui.link("Simulate a bump →", "t-caption c-secondary mock-only", { go: "bump-checking" })}
    </div>`), { tabs: "bump" });

  add("Bump", "bump-event-ready", "Event: ready when you are", "View/BumpScreen.swift · notReadyState + header", (st) => bumpScreen(`<div class="v center gap-l">
      ${ui.pulse(ui.phones(false))}
      ${centerTitle("Ready when you are", "Tap below, then gently tap phones with the person you want to meet.")}
      <div class="fill-w">${ui.btn("Ready to bump", "primary", { go: "bump-ready" })}</div>
      ${nearby([PARTNER.name, "Second Sample (demo)", "Third Sample (demo)"])}
      <div class="fill-w">${ui.btn("Leave event", "secondary", { go: "bump-home" })}</div>
    </div>`, `<div class="h">${ui.pill(`In “${st.code || "hackgt"}”`, "good")}<div class="spacer"></div>${T("caption", "secondary", "3 of 8 phones")}</div>`), { tabs: "bump" });

  add("Bump", "bump-checking", "Checking (felt a bump)", "View/BumpScreen.swift · .checking", () => `<div data-auto="bump-confirm" data-delay="1600" style="display:contents">${bumpScreen(statusCard("Felt that. Finding who you bumped…", "Hold still for a moment.", "active", true, [["Cancel", false, "bump-ready"]]))}</div>`, { tabs: "bump" });

  const confirm = (manual) => () => bumpScreen(`<div class="v center gap-l">
      <div style="padding-top:var(--Space-m)">${ui.avatar(PARTNER.name, 96)}</div>
      <div class="v center gap-s">${T("body", "secondary", "Did you bump with")}${T("screenTitle", "navy", esc(PARTNER.name), "t-center")}</div>
      ${manual ? ui.pill("You picked them manually", "warn") : ui.pill("Your phones were touching", "good")}
      <div class="v stretch gap-s fill-w">${ui.btn("Confirm & share interests", "primary", { go: "bump-waiting" })}${ui.btn("Not this person", "secondary", { go: "bump-ready" })}</div>
      ${T("caption", "secondary", "Your interests are only shared after you both confirm.", "t-center")}
    </div>`);
  add("Bump", "bump-confirm", "Confirm partner", "View/ConfirmPartnerView.swift", confirm(false), { tabs: "bump" });
  add("Bump", "bump-confirm-manual", "Confirm partner (manual pick)", "View/ConfirmPartnerView.swift", confirm(true), { tabs: "bump" });

  add("Bump", "bump-waiting", "Waiting for them", "View/BumpScreen.swift · .waitingForPartner", () => `<div data-auto="bump-exchanging" data-delay="1800" style="display:contents">${bumpScreen(statusCard("Waiting for them to confirm", "They need to tap confirm on their phone too.", "active", true, [["Cancel", false, "bump-ready"]]))}</div>`, { tabs: "bump" });

  add("Bump", "bump-exchanging", "Swapping interests", "View/BumpScreen.swift · .exchanging", () => `<div data-auto="reveal" data-delay="1400" style="display:contents">${bumpScreen(statusCard("Swapping interests", "Only the two of you see each other's profiles.", "active", true, []))}</div>`, { tabs: "bump" });

  add("Bump", "bump-timedout", "Error: nobody bumped back", "View/BumpScreen.swift · .timedOut", () => bumpScreen(statusCard("Nobody bumped back", "Make sure they're in the same event and tapped ready too.", "warn", false, [["Try again", true, "bump-ready"], ["Pick someone instead", false, "bump-picker"]])), { tabs: "bump" });

  add("Bump", "bump-ambiguous", "Error: several bumps at once", "View/BumpScreen.swift · .ambiguous", () => bumpScreen(statusCard("A few people bumped at once", "3 bumps landed at almost the same moment, so BUMP can't tell who was yours. Try again with a little space, or pick them from the room.", "warn", false, [["Try again", true, "bump-ready"], ["Pick someone instead", false, "bump-picker"]])), { tabs: "bump" });

  add("Bump", "bump-retry", "Error: didn't connect", "View/BumpScreen.swift · .needsRetry", () => bumpScreen(statusCard("Didn't connect", "Sample Partner (demo) didn't confirm in time.", "warn", false, [["Try again", true, "bump-ready"], ["Stop bumping", false, "bump-home"]])), { tabs: "bump" });

  add("Bump", "bump-unsupported", "Error: can't use sensors", "View/BumpScreen.swift · .unavailable", () => bumpScreen(statusCard("Can't use the sensors", "This iPhone isn't reporting motion data, so BUMP can't feel a bump. You can still connect by picking someone from the room.", "bad", false, [["Pick someone instead", true, "bump-picker"], ["Stop bumping", false, "bump-home"]])), { tabs: "bump" });

  add("Bump", "bump-picker", "Pick someone (sheet)", "View/BumpScreen.swift · manualPicker", () => bumpScreen(statusCard("Nobody bumped back", "Make sure they're in the same event and tapped ready too.", "warn", false, [["Try again", true, "bump-ready"], ["Pick someone instead", false, "bump-picker"]])), {
    tabs: "bump",
    sheet: () => ({
      size: "large",
      html: ui.nav({ title: "Pick someone", lead: ui.navText("Close", { go: "bump-timedout" }) }) + ui.screen(`<div class="v stretch gap-l">
        ${ui.sectionHeading("Pick the person", "BUMP couldn't tell who you bumped, so you're choosing manually. This gets saved as a manual pick, not a detected bump.")}
        ${[PARTNER.name, "Second Sample (demo)", "Third Sample (demo)"].map((n) => `<button class="link h gap-m" data-go="bump-confirm-manual" style="padding:var(--Space-m);background:var(--BumpColor-surface);border-radius:var(--Space-corner)">${ui.avatar(n, 40)}${T("bodyEmphasis", "navy", esc(n))}</button>`).join("")}
      </div>`),
    }),
  });

  // ── Reveal ──
  const reveal = (overlap) => () => ui.screen(`<div class="v stretch gap-l">
      <div class="h gap-m" style="padding-top:var(--Space-l)">${ui.avatar(ME.name, 52)}${ui.avatar(PARTNER.name, 52, { warm: true })}
        <div class="v lead gap-2">${T("bodyEmphasis", "navy", `${ME.name} + ${esc(PARTNER.name)}`)}${T("caption", "secondary", REVEAL.evidence)}</div></div>
      ${T("screenTitle", "navy", overlap ? "You have more in common than you think." : "Nice to meet you.")}
      ${overlap ? `<div class="v stretch gap-s">${T("caption", "secondary", "Specific things you share")}
          ${REVEAL.highlights.map((h, i) => highlightCard(h, i, true)).join("")}
          ${T("caption", "secondary", "Ranked by how specific they are, not by how rare they are. We don't have data on how common an interest is, so we don't claim to.")}</div>`
        : ui.card(T("body", "navy", "Your lists don't overlap yet, which is its own kind of interesting."))}
      ${overlap ? talkingPoints() : ""}
      <div class="v stretch gap-s">${T("caption", "secondary", "Something to talk about")}
        ${ui.card(`<div class="v lead gap-s">${T("sectionTitle", "navy", esc(overlap ? REVEAL.opener : "You two haven't listed anything in common yet. What's something you're into that most people have never tried?"))}${T("caption", "secondary", REVEAL.openerSource)}</div>`, { cls: "reveal-in", style: "animation-delay:.3s" })}</div>
      <div class="v stretch gap-s safe-bottom" style="padding-top:var(--Space-s)">${ui.btn("Save connection", "primary", { go: "conn-list" })}${ui.btn("Bump again", "secondary", { go: "bump-ready" })}</div>
    </div>`);
  add("Reveal", "reveal", "Reveal", "View/RevealView.swift", reveal(true));
  add("Reveal", "reveal-none", "Reveal (no overlap)", "View/RevealView.swift", reveal(false));

  // ── Connections ──
  add("Connections", "conn-empty", "Empty", "View/ConnectionsScreen.swift · emptyState", () => `${ui.nav()}<div class="nav-large">Connections</div>
    <div class="v center gap-m" style="flex:1">
      <div style="flex:1"></div>${ui.phones(false)}
      ${T("screenTitle", "navy", "Nobody yet")}
      ${T("body", "secondary", "The people you bump show up here, with what you have in common and the question you started on.", "t-center\" style=\"padding:0 var(--Space-xl)")}
      <div style="flex:2"></div>
    </div>`, { tabs: "connections" });

  add("Connections", "conn-list", "List", "View/ConnectionsScreen.swift · list", () => `${ui.nav()}<div class="nav-large">Connections</div>
    <div class="scroll"><div class="list">
      ${[[PARTNER.name, "Sep 25, 2026 · Jazz, Photography", "conn-detail"], ["Second Sample (demo)", "Sep 23, 2026 · demo · no shared interests yet", "conn-detail"]]
        .map(([n, s, go]) => `<div class="list-row" data-go="${go}">${ui.avatar(n, 44)}<div class="v lead gap-2" style="padding:var(--Space-xs) 0;min-width:0">${T("bodyEmphasis", "navy", esc(n))}${T("caption", "secondary", esc(s))}</div><span class="chev">${icon.chevronRight(13)}</span></div>`).join("")}
    </div></div>`, { tabs: "connections" });

  add("Connections", "conn-detail", "Detail", "View/ConnectionsScreen.swift · ConnectionDetail", () => ui.nav({ lead: ui.navBack("Connections", { go: "conn-list" }) }) + ui.screen(`<div class="v stretch gap-l">
      <div class="h gap-m">${ui.avatar(PARTNER.name, 64)}<div class="v lead gap-2">${T("screenTitle", "navy", esc(PARTNER.name))}${T("caption", "secondary", "Sep 25, 2026 at 8:14 PM · demo")}</div></div>
      ${ui.pill(REVEAL.evidence, "good", true)}
      ${ui.card(T("body", "navy", esc(PARTNER.bio)))}
      ${ui.sectionHeading("Specific things you share")}
      ${REVEAL.highlights.map((h, i) => highlightCard(h, i, false)).join("")}
      ${talkingPoints()}
      ${ui.sectionHeading("Something to talk about")}
      ${ui.card(`<div class="v lead gap-s">${T("sectionTitle", "navy", esc(REVEAL.opener))}${T("caption", "secondary", REVEAL.openerSource)}</div>`)}
      <div style="padding-top:var(--Space-m)">${ui.btn("Delete connection", "secondary", { go: "conn-empty" })}</div>
    </div>`), { tabs: "connections" });

  // ── You ──
  const permRow = (title, value, tone) => `<div class="h top gap-s"><span class="dot tone-${tone}" style="margin-top:6px"></span><div class="v lead gap-2">${T("bodyEmphasis", "navy", title)}${T("caption", "secondary", value)}</div></div>`;
  add("You", "you", "You", "View/YouScreen.swift", (st) => ui.nav({ title: "You" }) + ui.screen(`<div class="v stretch gap-l">
      <div class="h gap-m">${ui.photoAvatar(ME.name, 64)}<div class="v lead gap-2">${T("screenTitle", "navy", ME.name)}${T("caption", "secondary", `${ME.interests.length} interests`)}</div></div>
      ${ui.card(T("body", "navy", esc(ME.bio)))}
      ${ui.flow(ME.interests.map((i) => ui.chip(i)).join(""))}
      ${ui.btn("Edit profile", "primary", { go: "you-edit" })}
      ${ui.sectionHeading("Cloud processing", "Voice transcription, profile drafting and Grok talking points go through the BUMP server to xAI. Talking points use Grok only when you AND the person you bump both allow it.")}
      ${ui.card(`<div class="h gap-s"><div class="v lead gap-2" style="flex:1">${T("bodyEmphasis", "navy", "Allow cloud processing")}${T("caption", "secondary", st.cloud ? "On. The BUMP server is reachable and Grok is ready." : "Off. Nothing goes to the BUMP server or xAI, and you type instead of speak.")}</div>${ui.toggle(st.cloud, "toggleCloud")}</div>`)}
      ${ui.sectionHeading("Permissions & help")}
      ${ui.card(`<div class="v stretch gap-s">${permRow("Motion", "Available", "good")}<div class="divider divider--full"></div>${permRow("Ultra-wideband", "Distance and direction", "good")}<div class="divider divider--full"></div>${permRow("Nearby Interaction permission", "OK", "good")}<div class="divider divider--full"></div>${permRow("On-device AI", "On-device Apple Intelligence is ready.", "good")}</div>`)}
      ${T("caption", "secondary", "BUMP needs Local Network and Nearby Interaction access to find the phone next to you. Your card goes only to a partner you've both confirmed, directly between the two phones. There's no account. With cloud processing off, nothing goes to the BUMP server or xAI.")}
      ${ui.btn("Open iPhone Settings", "secondary")}
      ${ui.btn("Testing tools", "secondary")}
    </div>`), { tabs: "you" });

  add("You", "you-edit", "Edit profile", "View/ProfileEditor.swift", (st) => ui.nav({ title: "Edit profile", lead: ui.navBack("You", { go: "you" }) }) + ui.screen(`<div class="v stretch gap-l">
      <div class="h top gap-m">${ui.photoAvatar(ME.name, 64)}${ui.field({ label: "Display name", placeholder: "What should people call you?", value: ME.name })}</div>
      ${ui.field({ label: "Short bio (optional)", placeholder: "One line about you", value: ME.bio, lines: 1 })}
      <div class="v stretch gap-s">${ui.sectionHeading("What are you into?", "Start with a topic, then pick anything more specific. “Cold brew” starts a better conversation than “Coffee”.")}${topicBrowser(st, "editSelected")}</div>
      <div class="v stretch gap-s">${ui.field({ label: "Something else?", placeholder: "Add your own" })}${ui.btn("Add interest", "secondary", { disabled: true })}</div>
      <div class="v stretch gap-s">${T("caption", "secondary", `Your interests (${st.editSelected.size})`)}
        ${ui.flow([...st.editSelected].map((i) => ui.chip(`${i}  ✕`, { selected: true, act: "toggleChip", arg: `editSelected|${i}` })).join(""))}</div>
      <div class="v stretch gap-s">${ui.sectionHeading("Experiences & goals", "Shared with confirmed partners, like your interests.")}
        <div class="segmented">${["Experience", "Goal"].map((k) => `<button class="${st.detailKind === k ? "on" : ""}" data-act="detailKind" data-arg="${k}">${k}</button>`).join("")}</div>
        ${ui.field({ label: "Add one", placeholder: st.detailKind === "Goal" ? "e.g. Find a climbing partner" : "e.g. Built a weather station" })}
        ${ui.btn("Add", "secondary", { disabled: true })}</div>
      ${ui.btn("Save", "primary", { go: "you" })}
    </div>`), { tabs: "you" });

  window.SCREENS = S;
  window.FIXTURES = { ME, CATALOG };
})();
