/*
 * app.js: the review harness around the screens. Not a design surface:
 * nothing here gets ported to Swift.
 *
 *   Flow mode   one phone, fully clickable, like running the app.
 *   Grid mode   every screen side by side, for review.
 *   #screen-id  in the URL opens that screen directly (shareable).
 */
(function () {
  const { ME } = window.FIXTURES;
  const byId = Object.fromEntries(SCREENS.map((s) => [s.id, s]));

  // Sample state, seeded from PreviewFixtures.onboarding(...)
  const st = {
    name: "Sam (sample)",
    transcript: "Hi, I'm Sam. I play jazz piano and I've been getting into climbing. I work at a robotics lab. I'd love to meet people building hardware.",
    typed: "",
    answer: "",
    bio: "Jazz pianist, new boulderer, robotics by day.",
    items: [
      { id: "s1", kind: "interest", text: "Jazz piano", evidence: "I play jazz piano", origin: "Suggested by Grok", on: true },
      { id: "s2", kind: "interest", text: "Climbing", evidence: "I've been getting into climbing", origin: "Suggested by Grok", on: true },
      { id: "s5", kind: "interest", text: "Coffee", evidence: "pour-over coffee", origin: "Suggested by Grok", on: false },
      { id: "s3", kind: "experience", text: "Works at a robotics lab", evidence: "I work at a robotics lab", origin: "Suggested by Grok", on: true },
      { id: "s4", kind: "goal", text: "Meet people building hardware", evidence: "meet people building hardware", origin: "Suggested by Grok", on: true },
    ],
    browsing: false,
    onbSelected: new Set(["Climbing"]),
    editSelected: new Set(ME.interests),
    opened: { onbSelected: new Set(), editSelected: new Set() },
    code: "",
    cloud: true,
    detailKind: "Experience",
  };

  const prefs = load();
  let current = byId[location.hash.slice(1)] ? location.hash.slice(1) : (prefs.screen || "welcome");
  let mode = prefs.mode || "flow";
  let chrome = prefs.chrome || "bump";
  let zoom = prefs.zoom || "fit";
  let autoTimer = null;

  function load() { try { return JSON.parse(localStorage.getItem("bump-mockup-v3") || "{}"); } catch { return {}; } }
  function save() { try { localStorage.setItem("bump-mockup-v3", JSON.stringify({ screen: current, mode, chrome, zoom })); } catch { /* private window */ } }

  // MARK: Device

  function device(id) {
    const s = byId[id];
    const body = s.render(st);
    const sheet = s.sheet ? s.sheet(st) : null;
    const tabs = s.tabs ? ui.tabbar(s.tabs) : "";
    return `<div class="device" data-chrome="${chrome}" data-screen="${id}">
      <div class="statusbar"><span>9:41</span><span class="statusbar__icons">${ui.icon.signal()}${ui.icon.wifi()}${ui.icon.battery()}</span></div>
      <div class="island"></div>
      <div class="app ${s.tabs ? "has-tabs" : ""}">${body}</div>
      ${tabs}
      ${sheet ? `<div class="sheet-layer"><div class="sheet-dim" data-go="${s.id.startsWith("bump-picker") ? "bump-timedout" : "bump-home"}"></div>
        <div class="sheet sheet--${sheet.size}">${sheet.grabber ? '<div class="grabber"></div>' : ""}${sheet.html}</div></div>` : ""}
      <div class="home-indicator"></div>
    </div>`;
  }

  // MARK: Render

  const $ = (sel) => document.querySelector(sel);
  const stage = $("#stage");

  function render({ keepScroll = false } = {}) {
    clearTimeout(autoTimer);
    document.body.dataset.mode = mode;
    $("#chrome").value = chrome;
    $("#zoom").value = zoom;
    document.querySelectorAll("[data-mode]").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.mode === mode)));
    document.querySelectorAll(".nav-list a").forEach((a) => a.classList.toggle("on", a.dataset.id === current));

    if (mode === "grid") {
      const groups = [...new Set(SCREENS.map((s) => s.group))];
      stage.innerHTML = groups.map((g) => `<section class="grid-group"><h2>${g}</h2><div class="grid">
        ${SCREENS.filter((s) => s.group === g).map((s) => `<a class="grid-item" href="#${s.id}" data-open="${s.id}">
          <div class="grid-device">${device(s.id)}</div><strong>${ui.esc(s.title)}</strong><code>${ui.esc(s.swift)}</code></a>`).join("")}
      </div></section>`).join("");
      stage.querySelectorAll("input, textarea, button").forEach((el) => el.setAttribute("tabindex", "-1"));
      return;
    }

    const scrollEl = stage.querySelector(".app .scroll, .sheet .scroll");
    const scrollTop = keepScroll && scrollEl ? scrollEl.scrollTop : 0;
    const s = byId[current];
    stage.innerHTML = `<div class="flow-wrap"><div class="flow-zoom">${device(current)}</div>
      <div class="flow-meta"><strong>${ui.esc(s.group)} · ${ui.esc(s.title)}</strong><code>ios/UWBBumpTest/${ui.esc(s.swift)}</code>
      <span class="hint">Click through it like the app. ← → step through every screen.</span></div></div>`;
    fit();
    if (keepScroll) { const el = stage.querySelector(".app .scroll, .sheet .scroll"); if (el) el.scrollTop = scrollTop; }

    const auto = stage.querySelector("[data-auto]");
    if (auto) autoTimer = setTimeout(() => go(auto.dataset.auto), Number(auto.dataset.delay || 1500));
    save();
  }

  function fit() {
    const z = stage.querySelector(".flow-zoom");
    if (!z) return;
    let scale = 1;
    if (zoom === "fit") {
      const avail = stage.clientHeight - 90;
      scale = Math.max(0.4, Math.min(1, avail / 876));
    } else scale = Number(zoom);
    z.style.zoom = scale;
  }

  function go(id) {
    if (!byId[id]) return;
    current = id;
    if (location.hash.slice(1) !== id) history.replaceState(null, "", `#${id}`);
    mode = "flow";
    render();
  }

  // MARK: Actions (the few interactions that change sample state)

  const actions = {
    toggleItem(id) { const it = st.items.find((i) => i.id === id); if (it) it.on = !it.on; },
    toggleBrowse() { st.browsing = !st.browsing; },
    toggleTopic(arg) {
      const [key, cat] = arg.split("|");
      const sel = st[key], opened = st.opened[key];
      if (sel.has(cat)) { sel.delete(cat); opened.delete(cat); } else { sel.add(cat); opened.add(cat); }
    },
    toggleChip(arg) { const [key, k] = arg.split("|"); const sel = st[key]; sel.has(k) ? sel.delete(k) : sel.add(k); },
    toggleCloud() { st.cloud = !st.cloud; },
    detailKind(k) { st.detailKind = k; },
    joinEvent(code) { st.code = code; current = "bump-event-ready"; },
  };

  stage.addEventListener("click", (e) => {
    const open = e.target.closest("[data-open]");
    if (open) { e.preventDefault(); go(open.dataset.open); return; }
    const a = e.target.closest("[data-act]");
    if (a && actions[a.dataset.act]) { e.preventDefault(); actions[a.dataset.act](a.dataset.arg); render({ keepScroll: true }); return; }
    const g = e.target.closest("[data-go]");
    if (g && g.dataset.go) { e.preventDefault(); go(g.dataset.go); }
  });

  stage.addEventListener("input", (e) => {
    const key = e.target.dataset.bind;
    if (!key) return;
    st[key] = e.target.value;
    const pos = e.target.selectionStart;
    render({ keepScroll: true });
    const el = stage.querySelector(`[data-bind="${key}"]`);
    if (el) { el.focus(); el.setSelectionRange(pos, pos); }
  });

  // MARK: Toolbar + sidebar

  const groups = [...new Set(SCREENS.map((s) => s.group))];
  $(".nav-list").innerHTML = groups.map((g) => `<li><span>${g}</span><ul>${SCREENS.filter((s) => s.group === g)
    .map((s) => `<li><a href="#${s.id}" data-id="${s.id}">${ui.esc(s.title)}</a></li>`).join("")}</ul></li>`).join("");
  $(".nav-list").addEventListener("click", (e) => {
    const a = e.target.closest("a[data-id]");
    if (a) { e.preventDefault(); go(a.dataset.id); }
  });
  document.querySelectorAll("[data-mode]").forEach((b) => b.addEventListener("click", () => { mode = b.dataset.mode; render(); save(); }));
  $("#chrome").addEventListener("change", (e) => { chrome = e.target.value; render({ keepScroll: true }); save(); });
  $("#zoom").addEventListener("change", (e) => { zoom = e.target.value; fit(); save(); });
  window.addEventListener("resize", fit);
  window.addEventListener("hashchange", () => { const id = location.hash.slice(1); if (byId[id] && id !== current) go(id); });
  document.addEventListener("keydown", (e) => {
    if (e.target.matches("input, textarea, select")) return;
    const i = SCREENS.findIndex((s) => s.id === current);
    if (e.key === "ArrowRight" || e.key === "ArrowDown") { e.preventDefault(); go(SCREENS[(i + 1) % SCREENS.length].id); }
    if (e.key === "ArrowLeft" || e.key === "ArrowUp") { e.preventDefault(); go(SCREENS[(i - 1 + SCREENS.length) % SCREENS.length].id); }
  });

  render();
})();
