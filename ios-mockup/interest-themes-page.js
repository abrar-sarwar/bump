(function () {
  const { themes, badge, themeFor, apply, escape } = window.BUMP_THEMES;
  const groups = ["All", ...new Set(themes.map((theme) => theme.group))];
  let group = "All";
  let selected = "night";
  const $ = (selector) => document.querySelector(selector);
  const preview = $("#theme-preview");
  const phrase = $("#theme-phrase");
  const search = $("#theme-search");

  preview.innerHTML = badge(phrase.value, { cls: "badge--reveal badge--pop" });
  $("#theme-filters").innerHTML = groups.map((name) => `<button class="theme-lab__filter" type="button" data-group="${escape(name)}" aria-pressed="${name === "All"}">${escape(name)}</button>`).join("");

  function updatePreview(text) {
    const interest = text.trim() || "Something unexpected";
    const theme = themeFor(interest);
    const el = preview.querySelector(".badge");
    el.querySelector(".badge__interest").textContent = interest;
    el.setAttribute("aria-label", `You're both into ${interest}`);
    apply(el, interest);
    $("#theme-kind").textContent = theme.label;
    $("#theme-match").textContent = theme.id === "general" ? "No keyword match yet. Showing the BUMP default." : `Matched ${theme.label.toLowerCase()} keywords.`;
    selected = theme.id;
    document.querySelectorAll(".theme-lab__card").forEach((card) => card.setAttribute("aria-pressed", String(card.dataset.themeId === selected)));
  }

  function renderCards() {
    const term = search.value.trim().toLowerCase();
    const visible = themes.filter((theme) => (group === "All" || theme.group === group) &&
      (!term || [theme.label, theme.example, theme.group, ...theme.terms].some((value) => value.toLowerCase().includes(term))));
    $("#theme-count").textContent = `${visible.length} of ${themes.length} themes`;
    $("#theme-grid").innerHTML = visible.length ? visible.map((theme) => `<button class="theme-lab__card" type="button" data-theme-id="${theme.id}" aria-pressed="${theme.id === selected}">
      <span class="theme-lab__card-badge">${badge(theme.example)}</span><strong>${escape(theme.label)}</strong><small>${escape(theme.example)}</small></button>`).join("") :
      `<p class="theme-lab__empty">No themes match that search.</p>`;
  }

  $("#theme-filters").addEventListener("click", (event) => {
    const button = event.target.closest("[data-group]");
    if (!button) return;
    group = button.dataset.group;
    document.querySelectorAll(".theme-lab__filter").forEach((item) => item.setAttribute("aria-pressed", String(item.dataset.group === group)));
    renderCards();
  });
  $("#theme-grid").addEventListener("click", (event) => {
    const card = event.target.closest("[data-theme-id]");
    if (!card) return;
    const theme = themes.find((item) => item.id === card.dataset.themeId);
    phrase.value = theme.example;
    updatePreview(theme.example);
  });
  phrase.addEventListener("input", () => updatePreview(phrase.value));
  search.addEventListener("input", renderCards);
  renderCards();
  updatePreview(phrase.value);
})();
