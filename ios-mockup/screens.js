/*
 * screens.js: every screen and state of the app, in the marketing site's
 * language (localhost:5173): the wordmark artwork, the hero's photographs and
 * backdrop, frosted cards, orbs, pill rows, tags, bubbles, the shared badge.
 *
 * Copy is verbatim from the Swift views unless a comment says otherwise. Each
 * entry names the Swift file it mirrors. Sample data is PreviewFixtures.swift.
 */
(function () {
  const { esc, icon, text: T } = ui;

  // MARK: PreviewFixtures

  const ME = { name: "Jared", bio: "Building things at 2am.", interests: ["Jazz", "Baking", "Photography", "RPGs", "Coffee"] };
  const PARTNER = { name: "Sample Partner (demo)", bio: "Demo data. Not a real person." };
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

  // Decorative chat bubbles, verbatim from the site's hero floaters
  // (web/src/components/HeroFloaters.tsx). Fictional, aria-hidden.
  const LECTURE = "we’ve sat next to each other in lecture all semester";
  const FILM = "wait you shoot 35mm too??";
  const MIXER = "3 hours at this mixer and i’ve asked “what’s your major” 11 times";

  /** OnboardingFlow.topBar: frosted square back button + segmented progress */
  const onbTop = (step, back) => `<div class="h gap-m" style="padding:8px var(--Space-gutter);height:56px;flex:none">
      <button class="sq-btn state" style="${step === 0 ? "visibility:hidden" : ""}" aria-label="Back" data-go="${back || ""}">${icon.chevronLeft(20)}</button>
      ${ui.progress(step, 4)}</div>`;

  const onb = (step, back, body, bottom = "", backdrop) =>
    `${onbTop(step, back)}${ui.screen(body, { backdrop })}${bottom ? ui.bottomBar(bottom) : ""}`;

  /** Eyebrow + title + subtitle, left aligned */
  const titleBlock = (eyebrow, title, sub) => `<div class="v lead gap-s">${eyebrow ? ui.eyebrow(eyebrow) : ""}${T("screenTitle", "navy", esc(title))}${sub ? T("body", "secondary", esc(sub)) : ""}</div>`;
  /** BumpScreen.title(_:_:), centred */
  const centerTitle = (heading, detail) => `<div class="v center gap-s" style="padding:0 var(--Space-s)">${T("screenTitle", "navy", esc(heading), "t-center")}${T("body", "secondary", esc(detail), "t-center")}</div>`;

  const bumpNav = () => ui.nav({ principal: ui.wordmark() });
  const bumpScreen = (inner, { header = "", backdrop = "hero" } = {}) =>
    bumpNav() + ui.screen(`<div class="v stretch gap-l">${header}${inner}</div>`, { backdrop });

  /** BumpScreen.nearbyPeople: a pill row, avatars leading */
  const nearby = (names) => names.length ? ui.row({
    lead: `<span class="avatar-stack">${names.slice(0, 3).map((n, i) => ui.avatar(n, 40, { warm: i % 2 === 0 })).join("")}</span>`,
    title: names.length === 1 ? "1 person nearby" : `${names.length} people nearby`,
    trail: `<span class="dot tone-good" style="margin-right:6px"></span>`,
  }) : "";

  /** BumpScreen.statusCard, busy: an orb in pulse rings, a toast, the actions */
  const busyState = (glyph, title, body, actions = []) => bumpScreen(`<div class="v stretch gap-l">
      <div style="padding-top:var(--Space-xl)">${ui.pulse(ui.orb(glyph, { size: 96 }))}</div>
      ${ui.toast({ glyph, title: esc(title), body: esc(body), trail: ui.spinner() })}
      ${actions.map(([l, p, go]) => ui.btn(l, p ? "primary" : "secondary", { go })).join("")}</div>`);

  /** BumpScreen.statusCard, stopped: a peach bento with an icon label */
  const stopState = (glyph, title, body, actions) => bumpScreen(`<div class="v stretch gap-m" style="padding-top:var(--Space-l)">
      ${ui.bento("peach", "", "", `<div class="v lead gap-m">${ui.orb(glyph, { size: 52, tone: "orange" })}${T("screenTitle", "navy", esc(title))}${T("body", "secondary", esc(body))}</div>`)}
      <div class="v stretch gap-s" style="padding-top:var(--Space-s)">${actions.map(([l, p, go]) => ui.btn(l, p ? "primary" : "secondary", { go })).join("")}</div></div>`);

  /** A shared highlight as a pill row (RevealView / ConnectionDetail) */
  const highlightRow = (h, i, animate) => `<div class="${animate ? "reveal-in" : ""}" style="${animate ? `animation-delay:${0.15 + i * 0.09}s` : ""}">${ui.row({
    block: true, lead: ui.orb("join_inner", { size: 44 }),
    title: esc(h.statement), sub: `Both of you list “${esc(h.entry)}”`,
    faint: `<span class="h top gap-xs" style="margin-top:6px;color:var(--md-sys-color-primary);font-size:14px;font-weight:600">${icon.bubble(15)}<span>${esc(h.point)}</span></span>`,
  })}</div>`;

  /** TalkingPointsSection: "worth asking about" as chat bubbles */
  const talkingPoints = () => `<div class="v stretch gap-s">${ui.eyebrow("Worth asking about")}
      ${REVEAL.worthAsking.map((p) => ui.bubble(`${esc(p.prompt)}<div class="t-caption2 c-faint" style="margin-top:4px">You: “${esc(p.you)}” · Them: “${esc(p.them)}”</div>`)).join("")}
      ${T("caption2", "faint", "Suggested questions, built from both cards", "\" style=\"padding-left:6px")}</div>`;

  /** The opener, set like the site's quoted reply (.overlap__reply) */
  const opener = (text, source) => `<div class="v stretch gap-s">${ui.eyebrow("Something to talk about")}
      ${ui.bubble(`<span style="font:600 19px/1.25 var(--bump-typeface);letter-spacing:-0.01em">${esc(text)}</span>`, { me: true, who: source })}</div>`;

  /** TopicBrowser: tags, a frosted card per opened topic */
  const topicBrowser = (st, key) => {
    const sel = st[key], opened = st.opened[key];
    const topics = ui.flow(CATALOG.map(([cat]) => ui.chip(cat, { selected: sel.has(cat), act: "toggleTopic", arg: `${key}|${cat}` })).join(""));
    const open = CATALOG.filter(([cat, kids]) => opened.has(cat) || sel.has(cat) || kids.some((k) => sel.has(k)));
    return `<div class="v stretch gap-m">${topics}${open.map(([cat, kids]) => ui.card(`<div class="v lead gap-s">
        ${T("caption", "secondary", `${esc(cat)}: anything more specific?`)}
        ${ui.flow(kids.map((k) => ui.chip(k, { selected: sel.has(k), act: "toggleChip", arg: `${key}|${k}` })).join(""))}</div>`)).join("")}</div>`;
  };

  // MARK: Screens

  const S = [];
  const add = (group, id, title, swift, render, opts = {}) => S.push({ group, id, title, swift, render, ...opts });

  // ── Start ──
  // The site's hero on a phone: backdrop, the two photographs, the wordmark.
  // The two chat bubbles are decoration borrowed from the hero's floaters.
  add("Start", "welcome", "Welcome", "View/WelcomeView.swift", () => `
    <div class="has-backdrop v stretch" style="flex:1;padding-bottom:var(--safe-bottom)">${ui.backdrop("hero")}
      <div style="flex:1;min-height:40px"></div>
      <div style="padding:70px var(--Space-gutter) 40px">${ui.floaters(ui.phones(true), [[LECTURE, { left: "0", top: "-66px", rotate: -4 }], [FILM, { me: true, right: "0", bottom: "-36px", rotate: 4 }]])}</div>
      <div class="v center gap-m" style="padding:0 var(--Space-gutter)">
        ${ui.wordmark("hero")}
        ${T("sectionTitle", "navy", "Meet someone. Find your overlap.", "t-center")}
        ${T("body", "secondary", "Tap phones with someone new. BUMP finds the specific things you actually have in common, and gives you something to say.", "t-center")}
      </div>
      <div style="flex:1;min-height:16px"></div>
      <div style="padding:0 var(--Space-gutter) var(--Space-l)">${ui.btn("Get started", "primary", { go: "onb-name", icon: "arrow_forward" })}</div>
    </div>`);

  // ── Onboarding ──
  add("Onboarding", "onb-name", "1 · Name", "View/OnboardingFlow.swift · NameStep", (st) => onb(0, "", `
    <div class="v stretch gap-l">
      <div class="v lead gap-m">${ui.wordmark()}${titleBlock("Step 1 of 4", "What should we call you?", "This is the name people see after you bump.")}</div>
      ${ui.field({ label: "Your name", placeholder: "First name is fine", value: st.name, bind: "name" })}
      ${st.name.trim() ? ui.row({ lead: ui.avatar(st.name, 44), title: esc(st.name), trail: "" }) : ""}
    </div>`, ui.btn("Continue", "primary", { go: "onb-consent", icon: "arrow_forward", disabled: !st.name.trim() }), "soft"));

  const introHead = titleBlock("Step 2 of 4", "Introduce yourself", "Say what you're into, what you've done, and what you're hoping to find. We'll turn it into a card you can edit.");
  const skipIntro = `<div class="v center" style="padding-top:var(--Space-s)">${ui.link("Skip, I'll pick interests myself", "t-caption c-secondary", { go: "onb-card" })}</div>`;

  add("Onboarding", "onb-consent", "2 · Intro, consent", "View/OnboardingFlow.swift · CloudConsentCard", () => onb(1, "onb-name", `
    <div class="v stretch gap-l">${introHead}
      ${ui.bento("lilac", "Before anything leaves your phone", "lock", `
        ${T("body", "navy", "To transcribe your intro and suggest a card, BUMP sends your recording, anything you type here, and your answers to the BUMP server, which passes them to xAI's Grok.")}
        ${T("caption", "secondary", "The BUMP server doesn't store your audio or text. xAI's documentation says API requests are kept for up to 30 days for auditing. Later, if you and the person you bump both allow it, your shared interests are sent the same way to write talking points.")}
        <div class="v stretch gap-s" style="padding-top:var(--Space-xs)">${ui.btn("Allow cloud processing", "primary", { go: "onb-record" })}${ui.btn("Keep everything on this phone", "secondary", { go: "onb-typing" })}</div>
        ${T("caption", "secondary", "On this phone you type instead of speak. You can change this any time in You.", "t-center")}`)}
    </div>`));

  add("Onboarding", "onb-record", "2 · Intro, record", "View/OnboardingFlow.swift · recorderPanel .idle", () => onb(1, "onb-name", `
    <div class="v stretch gap-xl">${introHead}
      <div class="v center gap-m">
        ${ui.pulse(`<button class="orb record-btn state" aria-label="Start recording" data-go="onb-recording">${icon.mic()}</button>`, false)}
        ${T("caption", "secondary", "Tap to record · up to 45 seconds")}
        ${ui.link("Type instead", "t-bodyEmphasis c-action", { go: "onb-typing-cloud" })}
      </div>
    </div>`, skipIntro));

  add("Onboarding", "onb-recording", "2 · Intro, recording", "View/OnboardingFlow.swift · recorderPanel .recording", () => onb(1, "onb-name", `
    <div class="v stretch gap-xl">${introHead}
      <div class="v center gap-m">
        <button class="link" data-go="onb-transcribing" aria-label="Stop recording" style="border-radius:50%">${ui.badge("", "", { cls: "badge--recording badge--fast", inner: `${icon.ms("stop", 40, { fill: true })}` })}</button>
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
        ${ui.field({ label: "", value: st.transcript, bind: "transcript", lines: 4 })}
        <div class="h" style="padding:0 4px">${T("caption2", "faint", "Transcribed by xAI speech-to-text")}<div class="spacer"></div>${ui.link("Record again", "t-caption c-action", { go: "onb-record" })}</div>
      </div>
    </div>`, ui.btn("Draft my profile", "primary", { go: "onb-drafting", icon: "arrow_forward", disabled: !st.transcript.trim() }) + skipIntro));

  const typingScreen = (cloud) => (st) => onb(1, "onb-name", `
    <div class="v stretch gap-l">${introHead}
      <div class="v stretch gap-s">
        ${ui.field({ label: "Your intro", placeholder: "I'm into…  I've been…  I'm hoping to…", value: st.typed, bind: "typed", lines: 4 })}
        <div class="h" style="padding:0 4px">${T("caption2", "faint", cloud ? "Grok will suggest a card from this." : "Stays on this phone. Your phone suggests a card from this.")}<div class="spacer"></div>${cloud ? ui.link("Record instead", "t-caption c-action", { go: "onb-record" }) : ""}</div>
      </div>
    </div>`, ui.btn("Draft my profile", "primary", { go: "onb-drafting", icon: "arrow_forward", disabled: !st.typed.trim() }) + skipIntro);
  add("Onboarding", "onb-typing", "2 · Intro, typing (on this phone)", "View/OnboardingFlow.swift · typingPanel", typingScreen(false));
  add("Onboarding", "onb-typing-cloud", "2 · Intro, typing (cloud)", "View/OnboardingFlow.swift · typingPanel", typingScreen(true));

  add("Onboarding", "onb-drafting", "2 · Intro, drafting", "View/OnboardingFlow.swift · WorkingCard", () => onb(1, "onb-name", `
    <div class="v stretch gap-l">${introHead}
      <div data-auto="onb-questions" data-delay="1600">${ui.workingCard("Drafting your profile…", "Grok is reading your intro.", "onb-transcript")}</div>
    </div>`));

  // Questions as a chat: Grok's questions are "them" bubbles, answers are "me".
  add("Onboarding", "onb-questions", "3 · Question", "View/OnboardingFlow.swift · QuestionsStep", (st) => onb(2, "onb-transcript", `
    <div class="v stretch gap-l">${titleBlock("Step 3 of 4", "A little more", "Up to three quick questions. Skip anything.")}
      <div class="v stretch gap-s">
        ${ui.bubble("What kind of hardware are you building?", { who: "Question from Grok" })}
        ${ui.bubble("Small legged robots", { me: true })}
        <div style="height:6px"></div>
        ${ui.eyebrow("Question 2 of up to 3", "\" style=\"text-align:center")}
        ${ui.bubble(`<span style="font-weight:600;font-size:17px">You mentioned climbing. Where do you usually go?</span>`, { who: "Question from Grok" })}
      </div>
      ${ui.field({ label: "Your answer", placeholder: "A sentence is plenty", value: st.answer, bind: "answer", lines: 2 })}
    </div>`, ui.btn("Next", "primary", { go: "onb-card", icon: "arrow_forward", disabled: !st.answer.trim() }) + `
    <div class="h t-caption c-secondary" style="padding:var(--Space-s) 4px 0">${ui.link("Skip question", "", { go: "onb-card" })}<div class="spacer"></div>${ui.link("Done with questions", "", { go: "onb-card" })}</div>`));

  const KIND_GLYPH = { interest: "favorite", experience: "work", goal: "flag" };
  const cardRow = (it) => ui.row({
    block: true,
    lead: ui.checkbox(it.on, { act: "toggleItem", arg: it.id, label: `${it.on ? "Shared" : "Not shared"}: ${it.text}` }),
    title: `<span class="${it.on ? "" : "struck"}">${esc(it.text)}</span>`,
    sub: it.evidence ? `From “${esc(it.evidence)}”` : "",
    faint: esc(it.origin),
    trail: ui.iconButton("more_vert", `More for ${it.text}`),
  });

  const cardSection = (st, kind, title, empty) => {
    const items = st.items.filter((i) => i.kind === kind);
    return `<div class="v stretch gap-s">
      <div class="h" style="padding:0 4px">${T("sectionTitle", "navy", title)}<div class="spacer"></div>${ui.link(`${icon.plus(16)} Add`, "t-caption c-action h gap-xs")}</div>
      ${items.length ? items.map(cardRow).join("") : T("caption", "secondary", empty, "\" style=\"padding:0 4px")}
      ${kind === "interest" ? `<button class="disclosure t-caption ${st.browsing ? "open" : ""}" style="padding:4px" data-act="toggleBrowse">Browse interests ${icon.expand()}</button>${st.browsing ? topicBrowser(st, "onbSelected") : ""}` : ""}
    </div>`;
  };

  add("Onboarding", "onb-card", "4 · Your Bump card", "View/OnboardingFlow.swift · CardStep", (st) => {
    const canFinish = st.name.trim() && st.items.some((i) => i.on);
    return onb(3, "onb-questions", `
    <div class="v stretch gap-l">${titleBlock("Step 4 of 4", "Your Bump card", "Confirmed partners receive this card. Keep what's right, fix what isn't, and uncheck anything you'd rather not share.")}
      ${ui.card(`<div class="v stretch gap-m">
        <div class="h top gap-m">${ui.photoAvatar(st.name, 64)}${ui.field({ label: "Name", placeholder: "Your name", value: st.name, bind: "name" })}</div>
        ${ui.field({ label: "Short bio (optional)", placeholder: "One line about you", value: st.bio, bind: "bio", lines: 1 })}
        ${T("caption2", "faint", "Suggested by Grok from your intro. Edit freely.")}
      </div>`, { l: true })}
      ${cardSection(st, "interest", "Interests", "Nothing yet. Add your own or browse below.")}
      ${cardSection(st, "experience", "Experiences", "Anything you've done, built, studied or worked on.")}
      ${cardSection(st, "goal", "Goals", "What you're hoping to find or do. Optional.")}
      ${T("caption", "secondary", "Only your name, photo, bio and the checked items are shared, and only with someone you've both confirmed after a bump. Your recording, transcript and answers are never saved or shared.")}
    </div>`, ui.btn("Start bumping", "primary", { go: "tutorial-0", icon: "vibration", disabled: !canFinish }) +
      (canFinish ? "" : T("caption", "secondary", "Add your name and check at least one thing to continue.", "t-center")));
  });

  // ── Tutorial ──
  const TUTORIAL = [
    ["Find someone to meet", "You both open BUMP and tap Start bumping. No codes, no accounts. BUMP finds the phones around you.", "open"],
    ["Tap your phones together", "A gentle tap, back to back. That's how BUMP knows who you just met, and nobody else.", "tap"],
    ["Both say yes", "You each confirm who you bumped. Nothing is shared until you both do.", "confirm"],
    ["See what you share", "Your cards swap, and BUMP shows what you have in common plus a few things to talk about.", "share"],
  ];
  const tutorialArt = (art) => {
    if (art === "open") return ui.floaters(ui.pulse(`<div class="avatar-stack">${ui.avatar("You", 72)}${ui.avatar("Them", 72, { warm: true })}</div>`),
      [[LECTURE, { left: "0", top: "0", rotate: -4 }], [FILM, { me: true, right: "0", bottom: "8px", rotate: 3 }]]);
    if (art === "tap") return ui.floaters(`<div style="padding:40px 0">${ui.phones(true)}</div>`, [[MIXER, { left: "0", top: "-30px", rotate: -3 }]]);
    // The site's hero floater "did you bump with dev?", as the confirm moment
    if (art === "confirm") return ui.card(`<div class="v stretch gap-m">
        <div class="h gap-m">${ui.avatar("Them", 48, { warm: true })}<div class="t-bodyEmphasis c-navy">Did you bump with them?</div></div>
        <div class="h gap-s"><button class="btn btn--secondary" style="height:40px;font-size:14px">Not them</button><button class="btn btn--tonal" style="height:40px;font-size:14px">${icon.check(18)} Confirm</button></div>
      </div>`, { style: "width:280px;rotate:-2deg" });
    // Just the site's morphing badge, popping up, cycling through what two
    // people have in common (the tutorial's own examples + the site's).
    return ui.badge("You both share this", "", { cls: "badge--pop badge--lg", inner: `<span class="badge__kicker">You both share this</span>
      <span class="badge__cycle">${["35mm photography", "Climbing", "Cold brew"].map((t) => `<span class="badge__interest">${t}</span>`).join("")}</span>` });
  };
  TUTORIAL.forEach(([title, body, art], i) => {
    const last = i === TUTORIAL.length - 1;
    add("Tutorial", `tutorial-${i}`, `${i + 1} · ${title}`, "View/BumpTutorial.swift", () => `
      <div class="has-backdrop v stretch" style="flex:1">${ui.backdrop("soft")}
        <div class="h" style="padding:var(--Space-s) var(--Space-gutter) 0;flex:none">${ui.eyebrow("How it works")}<div class="spacer"></div>
          ${ui.link("Skip", "t-bodyEmphasis c-secondary\" style=\"" + (last ? "opacity:0" : ""), { go: "bump-home" })}</div>
        ${art === "share" ? `<div class="v center" style="flex:1;padding:0 var(--Space-gutter)">
          <div style="flex:1;display:grid;place-items:center;width:100%">${tutorialArt(art)}</div>
          <div class="v center gap-s" style="padding:0 var(--Space-s) var(--Space-xl)">${T("screenTitle", "navy", title, "t-center")}${T("body", "secondary", body, "t-center")}</div>
        </div>` : `<div class="v center gap-l" style="flex:1;padding:0 var(--Space-gutter)">
          <div style="flex:1;min-height:12px"></div>
          <div style="min-height:300px;display:grid;place-items:center;width:100%">${tutorialArt(art)}</div>
          <div class="v center gap-s" style="padding:0 var(--Space-s)">${T("screenTitle", "navy", title, "t-center")}${T("body", "secondary", body, "t-center")}</div>
          <div style="flex:1"></div>
        </div>`}
        <div class="v center" style="padding-bottom:var(--Space-l)">${ui.steps(i, 4)}</div>
        <div style="padding:0 var(--Space-gutter) calc(var(--Space-l) + var(--safe-bottom))">${ui.btn(last ? "Let's bump" : "Next", "primary", { go: last ? "bump-home" : `tutorial-${i + 1}`, icon: "arrow_forward" })}</div>
      </div>`);
  });

  // ── Bump ──
  const home = () => bumpScreen(`<div class="v stretch gap-l">
      <div style="padding:34px 0 26px">${ui.floaters(ui.phones(true), [[MIXER, { left: "-4px", top: "-40px", rotate: -3 }], [FILM, { me: true, right: "-4px", bottom: "-30px", rotate: 4 }]])}</div>
      ${centerTitle("Meet someone new", "Tap phones with the person in front of you and see what you have in common.")}
      ${ui.btn("Start bumping", "primary", { go: "bump-looking", icon: "vibration" })}
      <div class="v stretch gap-s">
        <div class="h" style="padding:0 4px">${ui.eyebrow("How it works")}<div class="spacer"></div>${ui.link("Watch the tour", "t-caption c-action", { go: "tutorial-0" })}</div>
        ${[["vibration", "You both tap Start bumping"], ["how_to_reg", "Gently tap your phones together"], ["join_inner", "Both confirm, then see what you share"]]
          .map(([g, t], i) => ui.row({ lead: ui.orb(g, { size: 44, tone: ["", "secondary", "tertiary"][i] }), title: t })).join("")}
      </div>
      <div class="v center">${ui.link("Have an event code?", "t-caption c-secondary", { go: "bump-eventcode" })}</div>
    </div>`);

  add("Bump", "bump-home", "Home", "View/BumpScreen.swift · roomSetup", home, { tabs: "bump" });

  add("Bump", "bump-eventcode", "Event code (sheet)", "View/BumpScreen.swift · eventCodeSheet", home, {
    tabs: "bump",
    sheet: (st) => ({
      size: "medium", grabber: true,
      html: ui.nav({ title: "Event code", lead: ui.navText("Close", { go: "bump-home" }) }) + ui.screen(`<div class="v stretch gap-l">
        ${ui.sectionHeading("Join a specific event", "Only needed at big events. Everyone using the same code ends up together. A room holds up to 8 phones.")}
        ${ui.field({ label: "Event code", placeholder: "hackgt", value: st.code, bind: "code" })}
        <div class="v stretch gap-s">${ui.btn("Join this event", "primary", { go: "bump-event-ready", disabled: !st.code.trim() })}
        ${ui.btn("Host it on this phone", "secondary", { go: "bump-event-ready", disabled: !st.code.trim() })}</div>
        <div class="v stretch gap-s">${ui.eyebrow("Events nearby")}${ui.flow(ui.chip("hackgt", { act: "joinEvent", arg: "hackgt" }) + ui.chip("hackgt-2", { act: "joinEvent", arg: "hackgt-2" }))}</div>
      </div>`),
    }),
  });

  add("Bump", "bump-looking", "Looking for people", "View/BumpScreen.swift · notReadyState", () => bumpScreen(`<div class="v stretch gap-l" data-auto="bump-ready" data-delay="2200">
      <div style="padding-top:var(--Space-xl)">${ui.floaters(ui.pulse(ui.orb("travel_explore", { size: 96 })), [[LECTURE, { left: "-4px", top: "0", rotate: -4 }]])}</div>
      ${centerTitle("Looking for people nearby…", "Ask the person you want to meet to open BUMP and tap Start bumping.")}
      ${ui.btn("Stop bumping", "secondary", { go: "bump-home" })}
    </div>`), { tabs: "bump" });

  add("Bump", "bump-ready", "Ready: tap phones", "View/BumpScreen.swift · readyState", () => bumpScreen(`<div class="v stretch gap-l">
      ${ui.floaters(ui.pulse(ui.phones(true)), [[FILM, { me: true, right: "-4px", top: "6px", rotate: 4 }]])}
      ${centerTitle("Tap your phones together", "A gentle tap, back to back, with the person you want to meet. BUMP is listening.")}
      ${nearby([PARTNER.name])}
      ${ui.btn("Stop bumping", "secondary", { go: "bump-home" })}
      <div class="v center">${ui.link("Simulate a bump →", "t-caption c-secondary mock-only", { go: "bump-checking" })}</div>
    </div>`), { tabs: "bump" });

  add("Bump", "bump-event-ready", "Event: ready when you are", "View/BumpScreen.swift · notReadyState + header", (st) => bumpScreen(`<div class="v stretch gap-l">
      ${ui.pulse(ui.phones(false, { apart: true }), false)}
      ${centerTitle("Ready when you are", "Tap below, then gently tap phones with the person you want to meet.")}
      ${ui.btn("Ready to bump", "primary", { go: "bump-ready", icon: "vibration" })}
      ${nearby([PARTNER.name, "Second Sample (demo)", "Third Sample (demo)"])}
      ${ui.btn("Leave event", "secondary", { go: "bump-home" })}
    </div>`, { header: `<div class="h">${ui.pill(`In “${st.code || "hackgt"}”`, "good")}<div class="spacer"></div>${T("caption", "secondary", "3 of 8 phones")}</div>` }), { tabs: "bump" });

  add("Bump", "bump-checking", "Checking (felt a bump)", "View/BumpScreen.swift · .checking", () => `<div data-auto="bump-confirm" data-delay="1600" style="display:contents">${busyState("vibration", "Felt that. Finding who you bumped…", "Hold still for a moment.", [["Cancel", false, "bump-ready"]])}</div>`, { tabs: "bump" });

  // The site's hero floater "did you bump with dev?", full size.
  const confirm = (manual) => () => bumpScreen(`<div class="v stretch gap-l" style="padding-top:var(--Space-l)">
      ${ui.card(`<div class="v center gap-l">
        ${ui.avatar(PARTNER.name, 104, { warm: true })}
        <div class="v center gap-s">${ui.eyebrow("Did you bump with")}${T("screenTitle", "navy", esc(PARTNER.name), "t-center")}</div>
        ${manual ? ui.pill("You picked them manually", "warn") : ui.pill("Your phones were touching", "good")}
        <div class="v stretch gap-s fill-w">${ui.btn("Confirm & share interests", "primary", { go: "bump-waiting", icon: "check" })}${ui.btn("Not this person", "secondary", { go: "bump-ready" })}</div>
      </div>`, { l: true, style: "padding-top:32px" })}
      ${T("caption", "secondary", "Your interests are only shared after you both confirm.", "t-center")}
    </div>`);
  add("Bump", "bump-confirm", "Confirm partner", "View/ConfirmPartnerView.swift", confirm(false), { tabs: "bump" });
  add("Bump", "bump-confirm-manual", "Confirm partner (manual pick)", "View/ConfirmPartnerView.swift", confirm(true), { tabs: "bump" });

  add("Bump", "bump-waiting", "Waiting for them", "View/BumpScreen.swift · .waitingForPartner", () => `<div data-auto="bump-exchanging" data-delay="1800" style="display:contents">${busyState("how_to_reg", "Waiting for them to confirm", "They need to tap confirm on their phone too.", [["Cancel", false, "bump-ready"]])}</div>`, { tabs: "bump" });

  add("Bump", "bump-exchanging", "Swapping interests", "View/BumpScreen.swift · .exchanging", () => `<div data-auto="reveal" data-delay="1400" style="display:contents">${busyState("join_inner", "Swapping interests", "Only the two of you see each other's profiles.")}</div>`, { tabs: "bump" });

  add("Bump", "bump-timedout", "Error: nobody bumped back", "View/BumpScreen.swift · .timedOut", () => stopState("person_search", "Nobody bumped back", "Make sure they're in the same event and tapped ready too.", [["Try again", true, "bump-ready"], ["Pick someone instead", false, "bump-picker"]]), { tabs: "bump" });
  add("Bump", "bump-ambiguous", "Error: several bumps at once", "View/BumpScreen.swift · .ambiguous", () => stopState("group", "A few people bumped at once", "3 bumps landed at almost the same moment, so BUMP can't tell who was yours. Try again with a little space, or pick them from the room.", [["Try again", true, "bump-ready"], ["Pick someone instead", false, "bump-picker"]]), { tabs: "bump" });
  add("Bump", "bump-retry", "Error: didn't connect", "View/BumpScreen.swift · .needsRetry", () => stopState("refresh", "Didn't connect", "Sample Partner (demo) didn't confirm in time.", [["Try again", true, "bump-ready"], ["Stop bumping", false, "bump-home"]]), { tabs: "bump" });
  add("Bump", "bump-unsupported", "Error: can't use sensors", "View/BumpScreen.swift · .unavailable", () => stopState("sensors_off", "Can't use the sensors", "This iPhone isn't reporting motion data, so BUMP can't feel a bump. You can still connect by picking someone from the room.", [["Pick someone instead", true, "bump-picker"], ["Stop bumping", false, "bump-home"]]), { tabs: "bump" });

  add("Bump", "bump-picker", "Pick someone (sheet)", "View/BumpScreen.swift · manualPicker", () => stopState("person_search", "Nobody bumped back", "Make sure they're in the same event and tapped ready too.", [["Try again", true, "bump-ready"], ["Pick someone instead", false, "bump-picker"]]), {
    tabs: "bump",
    sheet: () => ({
      size: "large",
      html: ui.nav({ title: "Pick someone", lead: ui.navText("Close", { go: "bump-timedout" }) }) + ui.screen(`<div class="v stretch gap-l">
        ${ui.sectionHeading("Pick the person", "BUMP couldn't tell who you bumped, so you're choosing manually. This gets saved as a manual pick, not a detected bump.")}
        <div class="v stretch gap-s">${[PARTNER.name, "Second Sample (demo)", "Third Sample (demo)"].map((n, i) => ui.row({ lead: ui.avatar(n, 44, { warm: i % 2 === 0 }), title: esc(n), go: "bump-confirm-manual", trail: `<span class="chev">${icon.chevronRight()}</span>` })).join("")}</div>
      </div>`),
    }),
  });

  // ── Reveal ──  The site's overlap section, as the payoff.
  const reveal = (overlap) => () => ui.screen(`<div class="v stretch gap-l">
      <div class="v center gap-s" style="padding-top:var(--Space-m)">
        <div class="avatar-stack">${ui.avatar(ME.name, 52)}${ui.avatar(PARTNER.name, 52, { warm: true })}</div>
        ${T("bodyEmphasis", "navy", `${ME.name} + ${esc(PARTNER.name)}`, "t-center")}
        ${ui.pill(REVEAL.evidence, "good")}
      </div>
      ${T("screenTitle", "navy", overlap ? "You have more in common than you think." : "Nice to meet you.", "t-center")}
      ${overlap ? `<div class="v center reveal-in">${ui.badge("You're both into", "Jazz")}</div>
        <div class="v stretch gap-s">${ui.eyebrow("Specific things you share", "\" style=\"padding-left:4px")}
          ${REVEAL.highlights.map((h, i) => highlightRow(h, i, true)).join("")}
          ${T("caption2", "faint", "Ranked by how specific they are, not by how rare they are. We don't have data on how common an interest is, so we don't claim to.", "\" style=\"padding:0 6px")}</div>`
        : ui.card(T("body", "navy", "Your lists don't overlap yet, which is its own kind of interesting."), { l: true })}
      ${overlap ? talkingPoints() : ""}
      ${opener(overlap ? REVEAL.opener : "You two haven't listed anything in common yet. What's something you're into that most people have never tried?", REVEAL.openerSource)}
      <div class="v stretch gap-s safe-bottom" style="padding-top:var(--Space-s)">${ui.btn("Save connection", "primary", { go: "conn-list", icon: "bookmark" })}${ui.btn("Bump again", "secondary", { go: "bump-ready" })}</div>
    </div>`, { backdrop: "hero" });
  add("Reveal", "reveal", "Reveal", "View/RevealView.swift", reveal(true));
  add("Reveal", "reveal-none", "Reveal (no overlap)", "View/RevealView.swift", reveal(false));

  // ── Connections ──
  add("Connections", "conn-empty", "Empty", "View/ConnectionsScreen.swift · emptyState", () => `${ui.nav()}<div class="nav-large">Connections</div>
    <div class="has-backdrop v center gap-m" style="flex:1;padding:0 var(--Space-gutter)">${ui.backdrop("soft")}
      <div style="flex:1"></div><div style="padding-top:60px;width:100%">${ui.floaters(ui.phones(false, { apart: true }), [[LECTURE, { left: "0", top: "-56px", rotate: -3 }]])}</div>
      ${T("screenTitle", "navy", "Nobody yet", "t-center")}
      ${T("body", "secondary", "The people you bump show up here, with what you have in common and the question you started on.", "t-center")}
      <div style="flex:2"></div>
    </div>`, { tabs: "connections" });

  add("Connections", "conn-list", "List", "View/ConnectionsScreen.swift · list", () => `${ui.nav()}<div class="nav-large">Connections</div>
    ${ui.screen(`<div class="v stretch gap-s">${[[PARTNER.name, "Sep 25, 2026 · Jazz, Photography", true], ["Second Sample (demo)", "Sep 23, 2026 · demo · no shared interests yet", false]]
      .map(([n, s, warm]) => ui.row({ block: true, lead: ui.avatar(n, 48, { warm }), title: esc(n), sub: esc(s), go: "conn-detail", trail: `<span class="chev" style="align-self:center">${icon.chevronRight()}</span>` })).join("")}</div>`)}`, { tabs: "connections" });

  add("Connections", "conn-detail", "Detail", "View/ConnectionsScreen.swift · ConnectionDetail", () => ui.nav({ lead: ui.navBack("Connections", { go: "conn-list" }) }) + ui.screen(`<div class="v stretch gap-l">
      ${ui.card(`<div class="h gap-m">${ui.avatar(PARTNER.name, 72, { warm: true })}<div class="v lead gap-xs" style="min-width:0">${T("sectionTitle", "navy", esc(PARTNER.name))}${T("caption", "secondary", "Sep 25, 2026 at 8:14 PM · demo")}${ui.pill(REVEAL.evidence, "good", true)}</div></div>
        <div style="margin-top:14px">${ui.bubble(esc(PARTNER.bio))}</div>`, { l: true })}
      <div class="v stretch gap-s">${ui.eyebrow("Specific things you share", "\" style=\"padding-left:4px")}${REVEAL.highlights.map((h, i) => highlightRow(h, i, false)).join("")}</div>
      ${talkingPoints()}
      ${opener(REVEAL.opener, REVEAL.openerSource)}
      ${ui.btn("Delete connection", "secondary", { go: "conn-empty" })}
    </div>`, { backdrop: "soft" }), { tabs: "connections" });

  // ── You ──
  const permRow = (glyph, title, value, tone) => ui.row({ lead: ui.orb(glyph, { size: 40 }), title, sub: value, trail: `<span class="dot tone-${tone}" style="margin-right:6px"></span>` });
  add("You", "you", "You", "View/YouScreen.swift", (st) => ui.nav({ title: "You" }) + ui.screen(`<div class="v stretch gap-l">
      ${ui.card(`<div class="v stretch gap-m">
        <div class="h gap-m">${ui.photoAvatar(ME.name, 72)}<div class="v lead gap-2">${T("screenTitle", "navy", ME.name)}${T("caption", "secondary", `${ME.interests.length} interests`)}</div></div>
        ${ui.bubble(esc(ME.bio))}
        ${ui.flow(ME.interests.map((i) => ui.chip(i)).join(""))}
        ${ui.btn("Edit profile", "tonal", { go: "you-edit", icon: "edit" })}
      </div>`, { l: true })}
      ${ui.bento("lilac", "Cloud processing", "cloud", `
        ${T("caption", "secondary", "Voice transcription, profile drafting and Grok talking points go through the BUMP server to xAI. Talking points use Grok only when you AND the person you bump both allow it.")}
        <div class="h gap-m" style="padding:12px 14px;border-radius:16px;background:rgba(255,255,255,.7)"><div class="v lead gap-2" style="flex:1">${T("bodyEmphasis", "navy", "Allow cloud processing")}${T("caption", "secondary", st.cloud ? "On. The BUMP server is reachable and Grok is ready." : "Off. Nothing goes to the BUMP server or xAI, and you type instead of speak.")}</div>${ui.toggle(st.cloud, "toggleCloud")}</div>`)}
      <div class="v stretch gap-s">${ui.eyebrow("Permissions & help", "\" style=\"padding-left:4px")}
        ${permRow("vibration", "Motion", "Available", "good")}${permRow("radar", "Ultra-wideband", "Distance and direction", "good")}
        ${permRow("near_me", "Nearby Interaction permission", "OK", "good")}${permRow("auto_awesome", "On-device AI", "On-device Apple Intelligence is ready.", "good")}</div>
      ${T("caption", "secondary", "BUMP needs Local Network and Nearby Interaction access to find the phone next to you. Your card goes only to a partner you've both confirmed, directly between the two phones. There's no account. With cloud processing off, nothing goes to the BUMP server or xAI.", "\" style=\"padding:0 4px")}
      <div class="v stretch gap-s">${ui.btn("Open iPhone Settings", "secondary", { icon: "settings" })}${ui.btn("Testing tools", "secondary")}</div>
    </div>`, { backdrop: "soft" }), { tabs: "you" });

  add("You", "you-edit", "Edit profile", "View/ProfileEditor.swift", (st) => ui.nav({ title: "Edit profile", lead: ui.navBack("You", { go: "you" }) }) + ui.screen(`<div class="v stretch gap-l">
      <div class="h top gap-m">${ui.photoAvatar(ME.name, 64)}${ui.field({ label: "Display name", placeholder: "What should people call you?", value: ME.name })}</div>
      ${ui.field({ label: "Short bio (optional)", placeholder: "One line about you", value: ME.bio, lines: 1 })}
      <div class="v stretch gap-s">${ui.sectionHeading("What are you into?", "Start with a topic, then pick anything more specific. “Cold brew” starts a better conversation than “Coffee”.")}${topicBrowser(st, "editSelected")}</div>
      <div class="v stretch gap-s">${ui.field({ label: "Something else?", placeholder: "Add your own" })}${ui.btn("Add interest", "secondary", { disabled: true })}</div>
      <div class="v stretch gap-s">${ui.eyebrow(`Your interests (${st.editSelected.size})`, "\" style=\"padding-left:4px")}
        ${ui.flow([...st.editSelected].map((i) => ui.chip(i, { selected: true, remove: true, act: "toggleChip", arg: `editSelected|${i}` })).join(""))}</div>
      <div class="v stretch gap-s">${ui.sectionHeading("Experiences & goals", "Shared with confirmed partners, like your interests.")}
        ${ui.pillTabs(["Experience", "Goal"], st.detailKind, "detailKind")}
        ${ui.field({ label: "Add one", placeholder: st.detailKind === "Goal" ? "e.g. Find a climbing partner" : "e.g. Built a weather station" })}
        ${ui.btn("Add", "secondary", { disabled: true })}</div>
      ${ui.btn("Save", "primary", { go: "you", icon: "check" })}
    </div>`), { tabs: "you" });

  window.SCREENS = S;
  window.FIXTURES = { ME, CATALOG };
})();
