/* Shared by the reveal screen and the standalone interest-theme gallery.
 * First matching theme wins; specific phrases precede broad categories. */
(function () {
  const themes = [
    { id: "night", label: "Night sky", group: "Places & mood", example: "Night hiking", terms: ["night", "stargazing", "night sky", "astronomy", "constellation", "moon", "stars"] },
    { id: "photography", label: "Photography", group: "Creative", example: "35mm photography", terms: ["photography", "photographer", "photo", "photos", "35mm", "camera", "cameras", "darkroom", "analog film", "portraiture"] },
    { id: "music", label: "Music", group: "Creative", example: "Jazz piano", terms: ["music", "musician", "jazz", "piano", "guitar", "drums", "singing", "singer", "concert", "dj", "orchestra", "classical", "hip hop", "rap", "saxophone", "sax", "bass", "ukulele", "band", "song", "songs", "songwriting", "beatmaking", "beats", "techno", "edm", "playlist", "violin", "karaoke", "choir", "flute"] },
    { id: "art", label: "Art & design", group: "Creative", example: "Illustration and design", terms: ["art", "artist", "design", "designer", "drawing", "draw", "sketch", "painting", "paint", "illustration", "ceramics", "pottery", "animation", "typography", "architecture", "fashion", "crafts", "sculpture", "watercolor", "doodle"] },
    { id: "food", label: "Food", group: "Food & drink", example: "Cooking pasta", terms: ["food", "cooking", "cook", "baking", "bake", "baker", "pasta", "ramen", "pizza", "bread", "recipe", "restaurant", "chef", "sushi", "dinner", "brunch", "pastry", "dessert", "cuisine"] },
    { id: "drink", label: "Drinks", group: "Food & drink", example: "Pour-over coffee", terms: ["drink", "coffee", "espresso", "tea", "matcha", "cocktail", "cocktails", "wine", "beer", "barista", "latte", "brew", "brewing", "boba", "smoothie", "cafe"] },
    { id: "outdoors", label: "Outdoors", group: "Places & mood", example: "Hiking trails", terms: ["outdoors", "nature", "hiking", "hike", "camping", "climbing", "bouldering", "mountain", "forest", "garden", "plants", "birdwatching"] },
    { id: "sports", label: "Sports", group: "Play & movement", example: "Basketball", terms: ["sport", "basketball", "soccer", "football", "tennis", "running", "run club", "cycling", "skating", "swimming", "volleyball", "baseball", "yoga"] },
    { id: "books", label: "Books", group: "Culture & ideas", example: "Science fiction books", terms: ["book", "books", "reading", "novel", "novels", "poetry", "literature", "writing", "writer", "library", "comics", "manga"] },
    { id: "technology", label: "Technology", group: "Culture & ideas", example: "Building robots", terms: ["technology", "tech", "robot", "robotics", "hardware", "software", "coding", "code", "programming", "engineering", "science", "ai", "electronics", "maker"] },
    { id: "gaming", label: "Gaming", group: "Play & movement", example: "Board games", terms: ["gaming", "game", "games", "gamer", "esports", "nintendo", "playstation", "board game", "board games", "tabletop", "dungeons", "rpg", "chess"] },
    { id: "travel", label: "Travel", group: "Places & mood", example: "Traveling by train", terms: ["travel", "trip", "backpacking", "exploring", "city break", "road trip", "train", "flight", "flying", "passport"] },
    { id: "cinema", label: "Film", group: "Culture & ideas", example: "Indie films", terms: ["film", "films", "movie", "movies", "cinema", "filmmaking", "screenwriting", "documentary", "anime", "theater", "theatre"] },
    { id: "collecting", label: "Collecting", group: "Culture & ideas", example: "Trading cards", terms: ["collecting", "collectibles", "trading cards", "figures", "sneakers", "coins", "stamps", "lego", "thrifting", "rocks", "minerals", "vinyl records"] },
    { id: "general", label: "Everything else", group: "Other", example: "Something unexpected", terms: [] },
  ];

  // Motifs follow the website badge: small details around the edge, leaving
  // the middle band clear for the label. Paths are drawn in a 20×20 box and
  // placed at roughly 6% of the badge width.
  const miniIcons = {
    photography: `<path d="M10 1 3 12h4l-3 4h12l-3-4h4L10 1ZM10 16v3"/>`,
    music: `<path d="M7 4v9a2.5 2.5 0 1 1-1.5-2.3V6l8-2v8a2.5 2.5 0 1 1-1.5-2.3V2z"/>`,
    art: `<path d="M2 14c4-8 8 7 12-2 2-4 4-3 5-2M4 18 16 6"/>`,
    food: `<circle cx="10" cy="10" r="7"/><circle cx="10" cy="10" r="4"/>`,
    drink: `<path d="M4 7h11v9H5L4 7Zm11 2h3c1 3-1 5-4 5M7 4c-2-2 2-2 0-4m5 4c-2-2 2-2 0-4"/>`,
    outdoors: `<path d="M2 17 8 5l4 7 2-4 5 9H2Zm6-12 2 4"/>`,
    sports: `<circle cx="10" cy="10" r="8"/><path d="M3 7c4 2 10 2 14 0M8 2c-2 5-1 11 4 16"/>`,
    books: `<path d="M10 17c-3-2-6-3-9-2V4c4-1 7 0 9 2 2-2 5-3 9-2v11c-3-1-6 0-9 2Zm0-11v11"/>`,
    technology: `<path d="M2 5h6v6h5V3h5M3 17h6v-4h7v4h2"/><circle cx="2" cy="5" r="1"/><circle cx="18" cy="3" r="1"/>`,
    gaming: `<path d="M5 5h10c2 0 3 2 4 10 0 2-2 3-4 1l-2-2H7l-2 2c-2 2-4 1-4-1C2 7 3 5 5 5Zm3 3v5m-2-2h4m4-2h1"/>`,
    travel: `<path d="M1 11 19 2l-5 8 5 3-6 1-4 5-1-7-7-1Z"/>`,
    cinema: `<rect x="2" y="4" width="16" height="12" rx="1"/><path d="M6 4v12m8-12v12m-8-7 6 2-6 2V9Z"/>`,
    collecting: `<rect x="4" y="3" width="10" height="12" rx="1"/><path d="M7 6h10v12H7m3-8 4 3-4 3"/>`,
    general: `<path d="M10 1v18M1 10h18M4 4l12 12M16 4 4 16"/>`,
  };
  const stars = [[22, 24, 3.2], [74, 20, 2.4], [84, 72, 3], [26, 80, 2.2], [58, 88, 1.6],
    [11, 48, 1.4], [48, 10, 1.3], [90, 42, 1.2], [70, 84, 1.1], [36, 16, 1]];
  function sparkle(x, y, size) {
    return `<path d="M${x} ${y - size}Q${x} ${y} ${x + size} ${y}Q${x} ${y} ${x} ${y + size}Q${x} ${y} ${x - size} ${y}Q${x} ${y} ${x} ${y - size}Z"/>`;
  }
  function motif(id) {
    if (id === "night") {
      return `<svg class="theme-motif" viewBox="0 0 100 100" fill="currentColor" stroke="none" aria-hidden="true">${stars.map(([x, y, size]) =>
        `<g class="theme-motif__part">${size >= 2 ? sparkle(x, y, size) : `<circle cx="${x}" cy="${y}" r="${size * 0.55}"/>`}</g>`).join("")}</svg>`;
    }
    const icon = miniIcons[id] || miniIcons.general;
    const places = [[23, 22, .34], [71, 22, .29], [71, 72, .34]];
    const accents = places.map(([x, y, scale]) => `<g class="theme-motif__part"><g transform="translate(${x} ${y}) scale(${scale})">${icon}</g></g>`).join("");
    return `<svg class="theme-motif" viewBox="0 0 100 100" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${accents}<g class="theme-motif__part"><circle cx="23" cy="75" r=".65"/><circle cx="89" cy="49" r=".6"/><circle cx="50" cy="18" r=".55"/></g></svg>`;
  }

  const escape = (s) => String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const normalize = (s) => String(s).toLowerCase().replace(/[_–—-]/g, " ").replace(/[^a-z0-9]+/g, " ").trim();
  const catalogueHints = {
    music: "music", coffee: "drink", food: "food", movement: "sports",
    games: "gaming", screen: "cinema", collecting: "collecting",
    outdoors: "outdoors", building: "technology", design: "art",
    words: "books", travel: "travel",
  };
  function themeFor(interest, hint = "") {
    const haystack = ` ${normalize(interest)} `;
    return themes.find((theme) => theme.terms.some((term) => haystack.includes(` ${normalize(term)} `)))
      || themes.find((theme) => theme.id === catalogueHints[hint]) || themes.at(-1);
  }
  function badge(interest, { cls = "", kicker = "You're both into" } = {}) {
    const theme = themeFor(interest);
    return `<div class="badge badge--themed ${cls}" data-theme="${theme.id}" role="img" aria-label="${escape(kicker)} ${escape(interest)}">
      <div class="badge__oval"></div><div class="badge__form"></div><div class="badge__motif">${motif(theme.id)}</div>
      <div class="badge__text"><span class="badge__kicker">${escape(kicker)}</span><span class="badge__interest">${escape(interest)}</span></div></div>`;
  }
  function cyclingBadge(interests, { cls = "", kicker = "You're both into" } = {}) {
    const seen = new Set();
    const entries = interests.map((entry) => typeof entry === "string" ? { text: entry, hint: "" } : entry)
      .map(({ text, hint = "" }) => ({ text: String(text).trim(), hint }))
      .filter(({ text }) => text && !seen.has(normalize(text)) && seen.add(normalize(text)));
    if (!entries.length) entries.push({ text: "Something unexpected", hint: "" });
    const theme = themeFor(entries[0].text, entries[0].hint);
    return `<div class="badge badge--themed ${cls}" data-cycle data-theme="${theme.id}" role="img" aria-label="${escape(kicker)}: ${escape(entries.map((entry) => entry.text).join(", "))}">
      <div class="badge__oval"></div><div class="badge__form"></div><div class="badge__motif">${motif(theme.id)}</div>
      <div class="badge__text"><span class="badge__kicker">${escape(kicker)}</span><span class="badge__cycle">${entries.map((entry, i) =>
        `<span class="badge__interest ${i === 0 ? "is-active" : ""}" data-theme-hint="${escape(entry.hint)}">${escape(entry.text)}</span>`).join("")}</span></div></div>`;
  }
  function apply(badgeElement, interest, hint = "") {
    const theme = themeFor(interest, hint);
    badgeElement.dataset.theme = theme.id;
    const holder = badgeElement.querySelector(".badge__motif");
    if (holder) holder.innerHTML = motif(theme.id);
  }
  window.BUMP_THEMES = { themes, themeFor, motif, badge, cyclingBadge, apply, escape };
})();
