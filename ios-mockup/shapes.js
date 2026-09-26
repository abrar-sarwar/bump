/*
 * shapes.js: the site's MD3 shape vocabulary (web/src/shapes.ts), for the
 * mockup. Same formula, so the app's shapes are the site's shapes:
 *
 *   scallop(lobes, depth): radius dips `depth` between `lobes` bumps.
 *   9 / 0.1 cookie · 4 / 0.35 clover · 12 / 0.06 sunny · 6 / 0.2 flower · 0 circle
 *
 * Two outputs: SVG paths (backdrop outlines) and clip-path polygons with a
 * fixed point count, so CSS can morph one into another (the shared badge).
 * Porting: the same function is a SwiftUI Shape; morph via animatableData.
 */
(function () {
  const TAU = Math.PI * 2;
  const r = (lobes, depth, t) => 1 - (depth * (1 - Math.cos(lobes * t))) / 2;

  /** SVG path in a 100 x 100 box (web/src/shapes.ts scallop) */
  function scallop(lobes, depth, steps = 180) {
    let d = "";
    for (let i = 0; i < steps; i++) {
      const t = (i / steps) * TAU, rr = 50 * r(lobes, depth, t);
      d += `${i ? "L" : "M"}${(50 + rr * Math.cos(t)).toFixed(2)} ${(50 + rr * Math.sin(t)).toFixed(2)}`;
    }
    return d + "Z";
  }

  /** clip-path polygon, 72 points, so any two morph point by point */
  function poly(lobes, depth, turn = 0) {
    const pts = [];
    for (let i = 0; i < 72; i++) {
      const t = (i / 72) * TAU, rr = 50 * r(lobes, depth, t), a = t + turn;
      pts.push(`${(50 + rr * Math.cos(a)).toFixed(2)}% ${(50 + rr * Math.sin(a)).toFixed(2)}%`);
    }
    return `polygon(${pts.join(",")})`;
  }

  // SharedBadge.tsx FORMS (soft pentagon, cookie, clover, soft heptagon),
  // with shallower lobes than the site's so the shape never pinches in on
  // the text. The morph carries NO rotation: baking the turn into the
  // polygons made every point cut a chord across the shape mid-morph, so it
  // shrank. The turn is a separate transform animation instead.
  const FORMS = [[5, 0.1], [9, 0.07], [4, 0.14], [7, 0.08]];
  const frames = [...FORMS, FORMS[0]].map(([l, d], i, all) =>
    `${((i / (all.length - 1)) * 100).toFixed(1)}% { clip-path: ${poly(l, d)}; }`);
  const style = document.createElement("style");
  style.textContent = `@keyframes badge-morph { ${frames.join(" ")} }
@keyframes badge-turn { to { rotate: 360deg; } }
.badge__form { clip-path: ${poly(5, 0.1)}; }`;
  document.head.appendChild(style);

  window.SHAPE = {
    scallop,
    cookie: scallop(9, 0.1), clover: scallop(4, 0.35), sunny: scallop(12, 0.06), flower: scallop(6, 0.2),
    circle: scallop(0, 0),
    pill: "M30 5h40a25 25 0 0 1 0 50H30a25 25 0 0 1 0-50Z",
  };
})();
