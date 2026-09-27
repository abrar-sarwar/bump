/**
 * MD3 shape vocabulary as SVG paths, in a 100 x 100 box.
 *
 * scallop(): a closed outline whose radius dips `depth` between `lobes`
 * bumps. lobes 9 / depth 0.1 is MD3's "cookie", 4 / 0.35 its "clover",
 * 12 / 0.06 its "sunny", 6 / 0.2 a "flower". depth 0 is a circle.
 */
export function scallop(lobes: number, depth: number, steps = 360) {
  let d = ''
  for (let i = 0; i < steps; i++) {
    const t = (i / steps) * Math.PI * 2
    const r = 50 * (1 - (depth * (1 - Math.cos(lobes * t))) / 2)
    d += `${i ? 'L' : 'M'}${(50 + r * Math.cos(t)).toFixed(2)} ${(50 + r * Math.sin(t)).toFixed(2)}`
  }
  return d + 'Z'
}

/** A pill in a 100 x 60 box. */
export const PILL = 'M30 5h40a25 25 0 0 1 0 50H30a25 25 0 0 1 0-50Z'
