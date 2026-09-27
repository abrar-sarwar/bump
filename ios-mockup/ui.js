/*
 * ui.js: HTML builders, one per component. Screens in screens.js are written
 * only in terms of these, so a screen reads roughly like its SwiftUI body.
 */
(function () {
  const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
  const attrs = (o = {}) => Object.entries(o)
    .filter(([, v]) => v !== undefined && v !== null && v !== false)
    .map(([k, v]) => (v === true ? k : `${k}="${esc(v)}"`)).join(" ");
  const wire = ({ go, act, arg } = {}) => attrs({ "data-go": go, "data-act": act, "data-arg": arg });

  /** Material Symbols Rounded glyph (the site's icon font) */
  const ms = (name, size = 24, { fill = false, cls = "" } = {}) =>
    `<span class="ms ${fill ? "fill" : ""} ${cls}" style="font-size:${size}px" aria-hidden="true">${name}</span>`;

  // Icons by role. The comment is the SF Symbol the Swift code uses today.
  const icon = {
    ms,
    chevronLeft: (s = 22) => ms("arrow_back", s),                // chevron.left
    chevronRight: (s = 22) => ms("chevron_right", s),            // chevron.right
    info: (s = 20) => ms("info", s, { fill: true }),              // info.circle
    lockShield: (s = 18) => ms("lock", s, { fill: true }),        // lock.shield
    mic: (s = 46) => ms("mic", s, { fill: true }),                // mic.fill
    check: (s = 18) => ms("check", s),                            // checkmark
    ellipsis: (s = 22) => ms("more_vert", s),                     // ellipsis
    plus: (s = 18) => ms("add", s),                               // plus
    camera: (s = 14) => ms("photo_camera", s, { fill: true }),    // camera.fill
    bubble: (s = 18) => ms("chat_bubble", s, { fill: true }),     // bubble.left
    close: (s = 16) => ms("close", s),                            // xmark.circle.fill
    expand: (s = 18) => ms("expand_more", s),
    arrow: (s = 20) => ms("arrow_forward", s),
    handTap: () => ms("vibration", 24),                           // hand.tap.fill
    people: () => ms("group", 24),                                // person.2.fill
    personCircle: () => ms("account_circle", 24),                 // person.crop.circle
    signal: () => `<svg width="19" height="12" viewBox="0 0 19 12" fill="currentColor"><rect x="0" y="8" width="3.2" height="4" rx="1"/><rect x="5" y="5.5" width="3.2" height="6.5" rx="1"/><rect x="10" y="3" width="3.2" height="9" rx="1"/><rect x="15" y="0" width="3.2" height="12" rx="1"/></svg>`,
    wifi: () => `<svg width="17" height="12" viewBox="0 0 17 12" fill="currentColor"><path d="M8.5 2.3c2.4 0 4.6.9 6.3 2.5l1.2-1.3A10.6 10.6 0 0 0 8.5.5 10.6 10.6 0 0 0 1 3.5l1.2 1.3a8.9 8.9 0 0 1 6.3-2.5Z"/><path d="M8.5 5.8c1.5 0 2.8.5 3.8 1.5l1.2-1.3a7.2 7.2 0 0 0-10 0l1.2 1.3c1-1 2.3-1.5 3.8-1.5Z"/><path d="M8.5 9.2c.6 0 1.1.2 1.5.6L8.5 11.5 7 9.8c.4-.4.9-.6 1.5-.6Z"/></svg>`,
    battery: () => `<svg width="27" height="13" viewBox="0 0 27 13" fill="none"><rect x=".5" y=".5" width="23" height="12" rx="3.8" stroke="currentColor" opacity=".4"/><rect x="2" y="2" width="20" height="9" rx="2.5" fill="currentColor"/><path d="M25 4.5v4c.8-.3 1.3-1.1 1.3-2s-.5-1.7-1.3-2Z" fill="currentColor" opacity=".4"/></svg>`,
  };

  const initials = (name) => String(name).split(" ").slice(0, 2).map((p) => (p.match(/\p{L}/u) || [""])[0]).join("").toUpperCase() || "?";

  const ui = {
    esc, attrs, wire, icon, initials,

    /** Text(...).font(BumpFont.x).foregroundStyle(...) */
    text(style, color, content, extra = "") {
      return `<div class="t-${style} c-${color} ${extra}">${content}</div>`;
    },
    eyebrow(text, extra = "") { return `<div class="eyebrow ${extra}">${esc(text)}</div>`; },

    /** Wordmark: the Horizon artwork, never set in a font */
    wordmark(size = "compact", { white = false } = {}) {
      return `<img class="wordmark wordmark--${size} ${white ? "wordmark--white" : ""}" src="assets/wordmark.png" alt="BUMP">`;
    },

    /** Button(...).buttonStyle(.bumpPrimary / .bumpSecondary) */
    btn(label, kind = "primary", opts = {}) {
      const trail = opts.icon ? ms(opts.icon, 20) : "";
      return `<button class="btn btn--${kind} state ${opts.cls || ""}" ${wire(opts)} ${opts.disabled ? "disabled" : ""}>${esc(label)}${trail}</button>`;
    },
    link(label, cls, opts = {}) { return `<button class="link state tb ${cls}" ${wire(opts)}>${label}</button>`; },

    /** BumpField */
    field({ label, placeholder = "", value = "", bind, lines }) {
      const common = attrs({ class: "field__input", placeholder, "data-bind": bind, "aria-label": label });
      const input = lines
        ? `<textarea ${common} style="min-height:${lines * 24 + 26}px">${esc(value)}</textarea>`
        : `<input ${common} value="${esc(value)}">`;
      return `<label class="field">${label ? `<span class="field__label">${esc(label)}</span>` : ""}${input}</label>`;
    },

    /** InterestChip = the site's .tag */
    chip(title, { selected = false, act, arg, go, remove = false } = {}) {
      const tag = act || go ? "button" : "span";
      return `<${tag} class="chip ${selected ? "chip--selected" : ""} ${remove ? "chip--removable" : ""}" ${wire({ act, arg, go })}>${esc(title)}${remove ? icon.close() : ""}</${tag}>`;
    },
    flow(inner, style = "") { return `<div class="flow" style="${style}">${inner}</div>`; },

    card(inner, { l = false, cls = "", style = "" } = {}) {
      return `<div class="card ${l ? "card--l" : ""} ${cls}" style="${style}">${inner}</div>`;
    },
    /** .folk-bento: pastel wash, icon label, then content */
    bento(tone, label, glyph, inner, style = "") {
      return `<div class="bento bento--${tone}" style="${style}"><div class="v stretch gap-m">${label ? `<div class="bento__label">${ms(glyph, 18)}${esc(label)}</div>` : ""}${inner}</div></div>`;
    },

    /** StatusPill */
    pill(text, tone = "neutral", lead = false) {
      return `<div class="pill ${lead ? "pill--lead" : ""}"><span class="dot tone-${tone}"></span>${esc(text)}</div>`;
    },

    /** .folk-orb: glossy sphere with an icon */
    orb(glyph, { size = 44, tone = "" } = {}) {
      return `<span class="orb ${tone ? `orb--${tone}` : ""}" style="--orb:${size}px">${ms(glyph, Math.round(size * 0.46), { fill: true })}</span>`;
    },
    /** Avatar = an orb with a coloured letter (the site's .person__avatar) */
    avatar(name, size = 56, { warm = false } = {}) {
      return `<span class="orb avatar ${warm ? "avatar--warm" : ""}" style="--orb:${size}px" aria-hidden="true">${esc(initials(name))}</span>`;
    },
    photoAvatar(name, size = 64) {
      const b = Math.round(size * 0.36);
      return `<div class="photo-avatar" role="button" aria-label="Add a profile photo">${ui.avatar(name, size)}<span class="photo-avatar__badge" style="width:${b}px;height:${b}px">${icon.camera(Math.round(size * 0.2))}</span></div>`;
    },

    /** .folk-chip: pill row, leading orb, title / sub / faint, optional trail */
    row({ lead = "", title, sub, faint, trail = "", go, act, arg, block = false, tag = "div" }) {
      const t = go || act ? "button" : tag;
      return `<${t} class="row-pill ${block ? "row-pill--block" : ""}" ${wire({ go, act, arg })}>${lead}
        <span class="row-pill__text">${title ? `<span class="row-pill__title">${title}</span>` : ""}${sub ? `<span class="row-pill__sub">${sub}</span>` : ""}${faint ? `<span class="row-pill__faint">${faint}</span>` : ""}</span>${trail}</${t}>`;
    },

    /** .folk-pills */
    pillTabs(items, current, act) {
      return `<div class="pill-tabs" role="tablist">${items.map((k) => `<button class="${k === current ? "on" : ""}" role="tab" aria-selected="${k === current}" data-act="${act}" data-arg="${esc(k)}">${esc(k)}</button>`).join("")}</div>`;
    },

    /** .float-bubble */
    bubble(content, { me = false, who } = {}) {
      return `<div class="v ${me ? "center" : "lead"}" style="${me ? "align-items:flex-end" : ""}">${who ? `<div class="bubble__who">${esc(who)}</div>` : ""}<div class="bubble ${me ? "bubble--me" : ""}">${content}</div></div>`;
    },

    /** .walkby__notice */
    toast({ glyph = "vibration", title, body, trail = "" }) {
      return `<div class="toast"><span class="toast__app">${ms(glyph, 22, { fill: true })}</span><div class="v lead gap-2" style="flex:1;min-width:0">${title ? `<div class="t-bodyEmphasis c-navy">${title}</div>` : ""}${body ? `<div class="t-caption c-secondary">${body}</div>` : ""}</div>${trail}</div>`;
    },

    /** SharedBadge.tsx */
    badge(kicker, interest, { sm = false, cls = "", inner } = {}) {
      return `<div class="badge ${sm ? "badge--sm" : ""} ${cls}"><div class="badge__oval"></div><div class="badge__form"></div>
        <div class="badge__text">${inner || `<span class="badge__kicker">${esc(kicker)}</span><span class="badge__interest">${esc(interest)}</span>`}</div></div>`;
    },

    /** HeroBackdrop.tsx: dot grid + faint shapes + glyphs */
    backdrop(set = "hero") {
      const S = window.SHAPE;
      const svg = (d, cls, style, tone = "primary", box = "0 0 100 100") =>
        `<svg class="${cls}" style="--tone:var(--md-sys-color-${tone});${style}" viewBox="${box}" aria-hidden="true"><path d="${d}"/></svg>`;
      const sets = {
        hero: svg(S.cookie, "line", "width:170px;left:-40px;top:6%") + svg(S.flower, "fill", "width:190px;right:-60px;bottom:14%", "tertiary") +
          svg(S.clover, "line", "width:110px;right:18px;top:12%", "secondary") + svg(S.circle, "fill", "width:28px;left:48%;top:9%"),
        soft: svg(S.cookie, "line", "width:150px;right:-50px;top:4%") + svg(S.clover, "fill", "width:120px;left:-44px;bottom:18%", "secondary"),
      };
      return `<div class="backdrop" aria-hidden="true">${set === "hero" ? '<div class="backdrop__dots"></div>' : ""}${sets[set]}</div>`;
    },

    /** PhonesIllustration(animated:) */
    phones(animated = false, { apart = false } = {}) {
      const p = (c) => `<div class="phone-art phone-art--${c}"><div class="phone-art__cam"><i></i><i></i></div></div>`;
      return `<div class="phones ${animated ? "phones--animated" : ""} ${apart ? "phones--apart" : ""}" aria-hidden="true">${p("blue")}${p("warm")}</div>`;
    },

    pulse(inner, active = true) {
      return `<div class="pulse-wrap"><div class="pulse ${active ? "pulse--active" : ""}"><i></i><i></i><i></i></div>${inner}</div>`;
    },

    sectionHeading(title, subtitle) {
      return `<div class="v stretch gap-xs">${ui.text("sectionTitle", "navy", esc(title))}${subtitle ? ui.text("caption", "secondary", esc(subtitle)) : ""}</div>`;
    },

    steps(current, total) {
      let s = "";
      for (let i = 0; i < total; i++) s += `<i class="${i <= current ? "on" : ""} ${i === current ? "current" : ""}"></i>`;
      return `<div class="steps" aria-label="Step ${current + 1} of ${total}">${s}</div>`;
    },
    progress(current, total) {
      let s = "";
      for (let i = 0; i < total; i++) s += `<i class="${i <= current ? "on" : ""}"></i>`;
      return `<div class="progress" role="progressbar" aria-label="Step ${current + 1} of ${total}">${s}</div>`;
    },

    notice(text) { return `<div class="notice">${icon.info()}<div class="t-caption">${esc(text)}</div></div>`; },
    spinner() { return `<div class="spinner" role="progressbar"></div>`; },

    /** WorkingCard, as a toast */
    workingCard(title, detail, cancelGo) {
      return ui.toast({ glyph: "graphic_eq", title: esc(title), body: detail ? esc(detail) : "", trail: ui.spinner() }) +
        (cancelGo ? `<div class="v center" style="padding-top:var(--Space-m)">${ui.link("Cancel", "t-caption c-action", { go: cancelGo })}</div>` : "");
    },

    /** BottomBar { } */
    bottomBar(inner) {
      return `<div class="v stretch gap-xs" style="padding:var(--Space-s) var(--Space-gutter);padding-bottom:calc(var(--Space-s) + var(--safe-bottom));background:var(--BumpColor-background)">${inner}</div>`;
    },
    screen(inner, { backdrop } = {}) {
      return `<div class="scroll ${backdrop ? "has-backdrop" : ""}">${backdrop ? ui.backdrop(backdrop) : ""}<div class="screen-pad">${inner}</div></div>`;
    },

    nav({ title = "", principal = "", lead = "", trail = "" } = {}) {
      return `<div class="nav"><div class="nav__lead">${lead}</div><div class="nav__title">${principal || esc(title)}</div><div class="nav__trail">${trail}</div></div>`;
    },
    navText(label, opts = {}) { return `<button class="navbtn state" ${wire(opts)}>${esc(label)}</button>`; },
    navBack(label, opts = {}) {
      return `<button class="navbtn navbtn--icon state" aria-label="Back" ${wire(opts)}>${ms("arrow_back_ios_new", 20, { cls: "ic-ios" })}${ms("arrow_back", 22, { cls: "ic-md" })}<span class="navbtn__backlabel">${esc(label)}</span></button>`;
    },

    tabbar(active) {
      const tab = (id, label, svg, go) => `<button class="tab ${active === id ? "on" : ""}" data-go="${go}">${svg}<span>${label}</span></button>`;
      return `<nav class="tabbar">${tab("bump", "Bump", icon.handTap(), "bump-home")}${tab("connections", "Friends", icon.people(), "conn-list")}${tab("you", "You", icon.personCircle(), "you")}</nav>`;
    },

    toggle(on, act) { return `<button class="md-switch ${on ? "on" : ""}" role="switch" aria-checked="${on}" ${wire({ act })}><i>${ms("check", 16)}</i></button>`; },
    checkbox(on, opts = {}) {
      return `<button class="check state ${on ? "on" : ""}" role="checkbox" aria-checked="${on}" ${wire(opts)} aria-label="${esc(opts.label || "")}"><span class="cbx">${ms("check", 16)}</span></button>`;
    },
    iconButton(name, label, opts = {}) {
      return `<button class="icon-btn state" aria-label="${esc(label)}" ${wire(opts)}>${ms(name, 22)}</button>`;
    },
  };

  window.ui = ui;
})();
