/**
 * Generate src/assets/wordmark.png from assets-source/wordmark.source.png.
 *
 * The source is flat brand artwork: BUMP in Horizon, brand blue on ivory. Two
 * colours, so the ivory can be keyed out exactly rather than by a tolerance
 * threshold.
 *
 * Every pixel on a letter edge is a linear blend of the two:
 *
 *     pixel = alpha * INK + (1 - alpha) * GROUND
 *
 * so alpha is recovered by projecting (pixel - GROUND) onto (INK - GROUND).
 * That keeps the anti-aliased edges smooth instead of stair-stepping them,
 * which matters because the hero displays this up to 92vw. Output RGB is the
 * pure ink colour everywhere, with the recovered alpha, so the artwork can be
 * recoloured downstream (the CTA panel inverts it to ivory).
 *
 * Then it crops to the ink bounding box. The tight crop is load-bearing: the
 * hero reveals the wordmark with a centre-out clip-path mask, so padding baked
 * into the image would offset the reveal from the point where the phones meet.
 *
 * Run:  node scripts/extract-wordmark.mjs
 *
 * (assets-source/extract.py does the phone cutouts and needs Pillow. This does
 * not, so it runs anywhere Node does.)
 */
import { decode, encode } from './_png.mjs'

const SRC = new URL('../assets-source/wordmark.source.png', import.meta.url)
const OUT = new URL('../src/assets/wordmark.png', import.meta.url)

const im = decode(SRC.pathname)
const { width: W, height: H, data } = im

// Sample the ground from a corner; find the ink as the most common colour that
// is not the ground. Nothing is hardcoded, so a recoloured logo still works.
const GROUND = [data[0], data[1], data[2]]
const hist = new Map()
for (let i = 0; i < W * H; i++) {
  const r = data[i * 4], g = data[i * 4 + 1], b = data[i * 4 + 2]
  if (Math.abs(r - GROUND[0]) + Math.abs(g - GROUND[1]) + Math.abs(b - GROUND[2]) < 30) continue
  const k = (r << 16) | (g << 8) | b
  hist.set(k, (hist.get(k) ?? 0) + 1)
}
const inkKey = [...hist].sort((a, b) => b[1] - a[1])[0][0]
const INK = [(inkKey >> 16) & 0xff, (inkKey >> 8) & 0xff, inkKey & 0xff]

const d = [INK[0] - GROUND[0], INK[1] - GROUND[1], INK[2] - GROUND[2]]
const dd = d[0] * d[0] + d[1] * d[1] + d[2] * d[2]

const out = Buffer.alloc(W * H * 4)
let minX = W, minY = H, maxX = -1, maxY = -1
for (let y = 0; y < H; y++) {
  for (let x = 0; x < W; x++) {
    const i = (y * W + x) * 4
    const p = [data[i] - GROUND[0], data[i + 1] - GROUND[1], data[i + 2] - GROUND[2]]
    let a = (p[0] * d[0] + p[1] * d[1] + p[2] * d[2]) / dd
    a = Math.max(0, Math.min(1, a))
    const alpha = Math.round(a * 255)
    out[i] = INK[0]; out[i + 1] = INK[1]; out[i + 2] = INK[2]; out[i + 3] = alpha
    if (alpha > 8) {
      if (x < minX) minX = x
      if (x > maxX) maxX = x
      if (y < minY) minY = y
      if (y > maxY) maxY = y
    }
  }
}

const cw = maxX - minX + 1
const chh = maxY - minY + 1
const cropped = Buffer.alloc(cw * chh * 4)
for (let y = 0; y < chh; y++) {
  out.copy(cropped, y * cw * 4, ((y + minY) * W + minX) * 4, ((y + minY) * W + minX + cw) * 4)
}

encode({ width: cw, height: chh, data: cropped }, OUT.pathname)

const hex = (c) => '#' + c.map((v) => v.toString(16).padStart(2, '0')).join('')
console.log(`source  ${W}x${H}`)
console.log(`ground  ${hex(GROUND)}   ink  ${hex(INK)}`)
console.log(`cropped ${cw}x${chh}   aspect ${(cw / chh).toFixed(3)}:1`)
console.log(`wrote   src/assets/wordmark.png`)
