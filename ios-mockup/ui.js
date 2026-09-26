/*
 * ui.js: HTML builders, one per SwiftUI component in Components.swift (plus
 * the private ones views define). Screens in screens.js are written only in
 * terms of these, so a screen here reads roughly like its SwiftUI body.
 */
(function () {
  const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
  const attrs = (o = {}) => Object.entries(o)
    .filter(([, v]) => v !== undefined && v !== null && v !== false)
    .map(([k, v]) => (v === true ? k : `${k}="${esc(v)}"`)).join(" ");
  /** data-go / data-act wiring shared by every tappable thing */
  const wire = ({ go, act, arg } = {}) => attrs({ "data-go": go, "data-act": act, "data-arg": arg });

  // SF Symbols stand-ins. Drawn to roughly match weight and optical size.
  const icon = {
    chevronLeft: (s = 20) => `<svg width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M15 4 7 12l8 8"/></svg>`,
    chevronRight: (s = 14) => `<svg width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="m9 4 8 8-8 8"/></svg>`,
    info: (s = 17) => `<svg width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><path d="M12 11v6" stroke-linecap="round"/><circle cx="12" cy="7.5" r="1.2" fill="currentColor" stroke="none"/></svg>`,
    lockShield: (s = 18) => `<svg width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><path d="M12 2 4 5v6c0 5 3.4 9.4 8 11 4.6-1.6 8-6 8-11V5l-8-3Z"/><rect x="9" y="11" width="6" height="5" rx="1" fill="currentColor" stroke="none"/><path d="M10 11V9.5a2 2 0 0 1 4 0V11"/></svg>`,
    mic: (s = 32) => `<svg width="${s}" height="${s}" viewBox="0 0 24 24" fill="currentColor"><rect x="8.5" y="2" width="7" height="12.5" rx="3.5"/><path d="M5.5 11a6.5 6.5 0 0 0 13 0" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><path d="M12 17.5V21" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>`,
    check: (s = 12) => `<svg width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3.4" stroke-linecap="round" stroke-linejoin="round"><path d="m4 12.5 5 5L20 6.5"/></svg>`,
    uturn: (s = 12) => `<svg width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M5 20v-8a5 5 0 0 1 5-5h10"/><path d="m15 2 5 5-5 5"/></svg>`,
    checkCircleFill: (s = 22) => `<svg width="${s}" height="${s}" viewBox="0 0 24 24"><circle cx="12" cy="12" r="11" fill="currentColor"/><path d="m7 12.3 3.3 3.3L17 9" fill="none" stroke="#fff" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/></svg>`,
    circle: (s = 22) => `<svg width="${s}" height="${s}" viewBox="0 0 24 24"><circle cx="12" cy="12" r="10.2" fill="none" stroke="currentColor" stroke-width="1.6"/></svg>`,
    ellipsis: (s = 20) => `<svg width="${s}" height="${s}" viewBox="0 0 24 24" fill="currentColor"><circle cx="5" cy="12" r="1.9"/><circle cx="12" cy="12" r="1.9"/><circle cx="19" cy="12" r="1.9"/></svg>`,
    plus: (s = 12) => `<svg width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3.2" stroke-linecap="round"><path d="M12 4v16M4 12h16"/></svg>`,
    camera: (s = 10) => `<svg width="${s}" height="${s}" viewBox="0 0 24 24" fill="currentColor"><path d="M8.5 4h7l1.6 2.4H20a2 2 0 0 1 2 2V18a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V8.4a2 2 0 0 1 2-2h2.9L8.5 4Z"/><circle cx="12" cy="13" r="3.6" fill="var(--BumpColor-action)"/></svg>`,
    bubble: (s = 12) => `<svg width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linejoin="round"><path d="M12 3c5 0 9 3.4 9 7.6s-4 7.6-9 7.6c-1 0-2-.1-2.9-.4L4 20l1.3-4C3.8 14.6 3 12.7 3 10.6 3 6.4 7 3 12 3Z"/></svg>`,
    xmarkCircleFill: (s = 20) => `<svg width="${s}" height="${s}" viewBox="0 0 24 24"><circle cx="12" cy="12" r="11" fill="currentColor"/><path d="m8 8 8 8M16 8l-8 8" stroke="#fff" stroke-width="2.2" stroke-linecap="round"/></svg>`,
    handTap: () => `<svg viewBox="0 0 28 28" fill="currentColor"><path d="M11.3 12.6V5.7a1.9 1.9 0 0 1 3.8 0v5.6l5.4.9c1.6.3 2.6 1.8 2.3 3.4l-1 5.4c-.4 2-2 3.4-4 3.4h-4.4c-1.3 0-2.5-.6-3.2-1.7l-3.9-5.6a1.8 1.8 0 0 1 2.7-2.4l2.3 2.2V12.6Z"/><path d="M8.4 8.2a4.8 4.8 0 1 1 8.8 2.2" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>`,
    people: () => `<svg viewBox="0 0 28 28" fill="currentColor"><circle cx="10" cy="9" r="4"/><path d="M2.5 21.5c0-3.8 3.4-6.3 7.5-6.3s7.5 2.5 7.5 6.3c0 .8-.6 1.2-1.3 1.2H3.8c-.7 0-1.3-.4-1.3-1.2Z"/><circle cx="19.5" cy="9.5" r="3.4"/><path d="M18.8 14.7c3.8-.2 6.7 2 6.7 5.5 0 .7-.5 1.1-1.2 1.1h-5c.3-2.6-.4-4.8-.5-6.6Z"/></svg>`,
    personCircle: () => `<svg viewBox="0 0 28 28" fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="14" cy="14" r="11.5"/><circle cx="14" cy="11.3" r="4" fill="currentColor" stroke="none"/><path d="M6.6 22.3c1.6-2.8 4.3-4.3 7.4-4.3s5.8 1.5 7.4 4.3" fill="currentColor" stroke="none"/></svg>`,
    signal: () => `<svg width="19" height="12" viewBox="0 0 19 12" fill="currentColor"><rect x="0" y="8" width="3.2" height="4" rx="1"/><rect x="5" y="5.5" width="3.2" height="6.5" rx="1"/><rect x="10" y="3" width="3.2" height="9" rx="1"/><rect x="15" y="0" width="3.2" height="12" rx="1"/></svg>`,
    wifi: () => `<svg width="17" height="12" viewBox="0 0 17 12" fill="currentColor"><path d="M8.5 2.3c2.4 0 4.6.9 6.3 2.5l1.2-1.3A10.6 10.6 0 0 0 8.5.5 10.6 10.6 0 0 0 1 3.5l1.2 1.3a8.9 8.9 0 0 1 6.3-2.5Z"/><path d="M8.5 5.8c1.5 0 2.8.5 3.8 1.5l1.2-1.3a7.2 7.2 0 0 0-10 0l1.2 1.3c1-1 2.3-1.5 3.8-1.5Z"/><path d="M8.5 9.2c.6 0 1.1.2 1.5.6L8.5 11.5 7 9.8c.4-.4.9-.6 1.5-.6Z"/></svg>`,
    battery: () => `<svg width="27" height="13" viewBox="0 0 27 13" fill="none"><rect x=".5" y=".5" width="23" height="12" rx="3.8" stroke="currentColor" opacity=".4"/><rect x="2" y="2" width="20" height="9" rx="2.5" fill="currentColor"/><path d="M25 4.5v4c.8-.3 1.3-1.1 1.3-2s-.5-1.7-1.3-2Z" fill="currentColor" opacity=".4"/></svg>`,
  };

  const ui = {
    esc, attrs, wire, icon,

    /** Text(...).font(BumpFont.x).foregroundStyle(...) */
    text(style, color, content, extra = "") {
      return `<div class="t-${style} c-${color} ${extra}">${content}</div>`;
    },

    /** Wordmark(size:) */
    wordmark(size = "compact") {
      return `<div class="wordmark wordmark--${size}" role="heading" aria-label="BUMP">BUMP</div>`;
    },

    /** Button(...).buttonStyle(.bumpPrimary / .bumpSecondary) */
    btn(label, kind = "primary", opts = {}) {
      return `<button class="btn btn--${kind} ${opts.cls || ""}" ${wire(opts)} ${opts.disabled ? "disabled" : ""}>${esc(label)}</button>`;
    },

    /** A plain Button("...") with a font and colour */
    link(label, cls, opts = {}) {
      return `<button class="link ${cls}" ${wire(opts)}>${label}</button>`;
    },

    /** BumpField(label:placeholder:axis:lines:text:) */
    field({ label, placeholder = "", value = "", bind, lines, autofocus }) {
      const common = attrs({ class: "field__input", placeholder, "data-bind": bind, "aria-label": label });
      const input = lines
        ? `<textarea ${common} style="min-height:${lines * 22 + 26}px">${esc(value)}</textarea>`
        : `<input ${common} value="${esc(value)}" ${autofocus ? "data-autofocus" : ""}>`;
      return `<label class="field"><span class="field__label">${esc(label)}</span>${input}</label>`;
    },

    /** InterestChip(title:selected:action:) */
    chip(title, { selected = false, act, arg, go } = {}) {
      const tag = act || go ? "button" : "span";
      return `<${tag} class="chip ${selected ? "chip--selected" : ""}" ${wire({ act, arg, go })}>${esc(title)}</${tag}>`;
    },
    flow(inner, style = "") { return `<div class="flow" style="${style}">${inner}</div>`; },

    /** Card(padding:) { } */
    card(inner, { l = false, cls = "", style = "" } = {}) {
      return `<div class="card ${l ? "card--l" : ""} ${cls}" style="${style}">${inner}</div>`;
    },

    /** StatusPill(text:tone:) */
    pill(text, tone = "neutral", lead = false) {
      return `<div class="pill ${lead ? "pill--lead" : ""}"><span class="dot tone-${tone}"></span>${esc(text)}</div>`;
    },

    /** Avatar(name:size:tint:) */
    avatar(name, size = 56, { warm = false, ring = false } = {}) {
      const parts = String(name).split(" ").slice(0, 2);
      const letters = parts.map((p) => (p.match(/\p{L}/u) || [""])[0]).join("").toUpperCase() || "?";
      return `<div class="avatar ${warm ? "avatar--warm" : ""} ${ring ? "avatar-ring" : ""}" style="width:${size}px;height:${size}px;font-size:${size * 0.38}px" aria-hidden="true">${esc(letters)}</div>`;
    },

    /** PhotoPickerAvatar(photo:name:size:) */
    photoAvatar(name, size = 64) {
      const b = size * 0.34;
      return `<div class="photo-avatar" role="button" aria-label="Add a profile photo">${ui.avatar(name, size)}
        <span class="photo-avatar__badge" style="width:${b}px;height:${b}px">${icon.camera(size * 0.2)}</span></div>`;
    },

    /** PhonesIllustration(animated:) */
    phones(animated = false) {
      const p = (c) => `<div class="phone-art phone-art--${c}"><div class="phone-art__cam"><i></i><i></i></div></div>`;
      return `<div class="phones ${animated ? "phones--animated" : ""}" aria-hidden="true">${p("blue")}${p("warm")}</div>`;
    },

    /** ZStack { PulseRings(active:); content } */
    pulse(inner, active = true) {
      return `<div class="pulse-wrap"><div class="pulse ${active ? "pulse--active" : ""}"><i></i><i></i><i></i></div>${inner}</div>`;
    },

    /** SectionHeading(title:subtitle:) */
    sectionHeading(title, subtitle) {
      return `<div class="section-heading">${ui.text("sectionTitle", "navy", esc(title))}${subtitle ? ui.text("caption", "secondary", esc(subtitle)) : ""}</div>`;
    },

    /** StepIndicator(current:total:) */
    steps(current, total) {
      let s = "";
      for (let i = 0; i < total; i++) s += `<i class="${i <= current ? "on" : ""} ${i === current ? "current" : ""}"></i>`;
      return `<div class="steps" aria-label="Step ${current + 1} of ${total}">${s}</div>`;
    },

    /** NoticeText(text:) */
    notice(text) {
      return `<div class="notice">${icon.info()}<div class="t-caption">${esc(text)}</div></div>`;
    },

    /** ProgressView() */
    spinner() {
      let s = "";
      for (let i = 0; i < 8; i++) s += `<i style="transform:rotate(${i * 45}deg);opacity:${0.25 + i * 0.1}"></i>`;
      return `<div class="spinner" role="progressbar">${s}</div>`;
    },

    /** WorkingCard(title:detail:onCancel:) */
    workingCard(title, detail, cancelGo) {
      return ui.card(`<div class="h top gap-m">${ui.spinner()}<div class="v lead gap-xs">
        ${ui.text("bodyEmphasis", "navy", esc(title))}
        ${detail ? ui.text("caption", "secondary", esc(detail)) : ""}
        ${cancelGo ? `<div style="padding-top:var(--Space-xs)">${ui.link("Cancel", "t-caption t-semibold c-action", { go: cancelGo })}</div>` : ""}
      </div></div>`, { l: true });
    },

    /** BottomBar { } (OnboardingFlow.swift) */
    bottomBar(inner) {
      return `<div class="v stretch gap-xs safe-bottom" style="padding:var(--Space-s) var(--Space-gutter) var(--Space-s);padding-bottom:calc(var(--Space-s) + var(--safe-bottom));background:var(--BumpColor-background)">${inner}</div>`;
    },

    /** Screen { } */
    screen(inner) {
      return `<div class="scroll"><div class="screen-pad">${inner}</div></div>`;
    },

    /** .navigationTitle + toolbar, inline display mode */
    nav({ title = "", principal = "", lead = "", trail = "" } = {}) {
      return `<div class="nav"><div class="nav__lead">${lead}</div><div class="nav__title">${principal || esc(title)}</div><div class="nav__trail">${trail}</div></div>`;
    },
    navText(label, opts = {}) { return `<button class="navbtn" ${wire(opts)}>${esc(label)}</button>`; },
    navBack(label, opts = {}) {
      return `<button class="navbtn navbtn--icon" aria-label="Back" ${wire(opts)}>${icon.chevronLeft(22)}<span class="navbtn__backlabel">${esc(label)}</span></button>`;
    },

    /** TabView { Bump, Connections, You } */
    tabbar(active) {
      const tab = (id, label, svg, go) => `<button class="tab ${active === id ? "on" : ""}" data-go="${go}">${svg}<span>${label}</span></button>`;
      return `<nav class="tabbar">${tab("bump", "Bump", icon.handTap(), "bump-home")}${tab("connections", "Connections", icon.people(), "conn-list")}${tab("you", "You", icon.personCircle(), "you")}</nav>`;
    },

    toggle(on, act) { return `<button class="switch ${on ? "on" : ""}" role="switch" aria-checked="${on}" ${wire({ act })}></button>`; },
  };

  window.ui = ui;
})();
