/**
 * Interest themes: which look a shared-interest badge gets, picked by keyword.
 * PORTED from ios-mockup/interest-themes.js (the app's own badge system),
 * data copied as-is, so the site and the app pick the same theme for the same
 * interest. First matching theme wins; specific phrases precede broad ones.
 * If the mockup's list changes, re-port it rather than editing here.
 */
export type Theme = { id: string; label: string; group: string; example: string; terms: string[] }

export const THEMES: Theme[] = [
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
  ]

/** Line-art motifs, drawn in a 20x20 box (stroke, no fill). */
const MINI_ICONS: Record<string, string> = {
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
  }

const STARS: [number, number, number][] = [[22, 24, 3.2], [74, 20, 2.4], [84, 72, 3], [26, 80, 2.2], [58, 88, 1.6],
    [11, 48, 1.4], [48, 10, 1.3], [90, 42, 1.2], [70, 84, 1.1], [36, 16, 1]]

const sparkle = (x: number, y: number, s: number) =>
  `<path d="M${x} ${y - s}Q${x} ${y} ${x + s} ${y}Q${x} ${y} ${x} ${y + s}Q${x} ${y} ${x - s} ${y}Q${x} ${y} ${x} ${y - s}Z"/>`

const normalize = (s: string) => s.toLowerCase().replace(/[_\u2013\u2014-]/g, " ").replace(/[^a-z0-9]+/g, " ").trim()

export function themeFor(interest: string): Theme {
  const haystack = ` ${normalize(interest)} `
  return THEMES.find((t) => t.terms.some((term) => haystack.includes(` ${normalize(term)} `))) ?? THEMES[THEMES.length - 1]
}

/** The motif SVG's inner markup. Static strings from this file only, never
 *  user text, so it is safe to set as HTML. */
export function motifMarkup(id: string): { night: boolean; html: string } {
  if (id === "night") {
    return {
      night: true,
      html: STARS.map(([x, y, s]) => `<g class="theme-motif__part">${s >= 2 ? sparkle(x, y, s) : `<circle cx="${x}" cy="${y}" r="${s * 0.55}"/>`}</g>`).join(""),
    }
  }
  const icon = MINI_ICONS[id] ?? MINI_ICONS.general
  const places: [number, number, number][] = [[23, 22, 0.34], [71, 22, 0.29], [71, 72, 0.34]]
  return {
    night: false,
    html: places.map(([x, y, sc]) => `<g class="theme-motif__part"><g transform="translate(${x} ${y}) scale(${sc})">${icon}</g></g>`).join("")
      + `<g class="theme-motif__part"><circle cx="23" cy="75" r=".65"/><circle cx="89" cy="49" r=".6"/><circle cx="50" cy="18" r=".55"/></g>`,
  }
}
