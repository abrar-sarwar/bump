/** Asserts the hero wordmark is invisible until after the bump, on both
 *  breakpoints, forwards and backwards. */
import { chromium } from 'playwright'
const URL = process.argv[2] ?? 'http://localhost:4173'
const HERO_VH = { desktop: 4.0, mobile: 3.0 }
const BEATS = [
  ['load',        0.00, 'hidden'],
  ['approach',    0.26, 'hidden'],
  ['pre-contact', 0.38, 'hidden'],
  ['contact',     0.42, 'hidden'],
  ['recoil',      0.48, 'hidden'],
  // The word opens in lockstep with the phones parting (0.574 to 0.912,
  // power1.inOut), so these sample that span.
  ['mid-reveal',  0.66, 'partial'],
  ['reveal',      0.80, 'visible'],
  ['settled',     0.95, 'visible'],
]
const b = await chromium.launch({ channel: 'chrome' })
const fails = []
for (const [name, vp] of [['desktop', { width: 1440, height: 900 }], ['mobile', { width: 390, height: 844 }]]) {
  const page = await b.newPage({ viewport: vp })
  await page.goto(URL, { waitUntil: 'networkidle' })
  await page.waitForTimeout(800)
  const span = HERO_VH[name] * vp.height
  // The wordmark is revealed by opening a centre-out mask, so "is it visible"
  // means "how much of it is unmasked", not opacity.
  const read = () => page.evaluate(() => {
    const el = document.querySelector('.hero__mark')
    const cs = getComputedStyle(el)
    const w = el.getBoundingClientRect().width || 1
    const m = cs.clipPath.match(/-?[\d.]+(px|%)?/g) || []
    const toPx = (v) => (v.endsWith('%') ? (parseFloat(v) / 100) * w : parseFloat(v))
    // inset(top right bottom left); 1 value = all sides, 2 = vert/horiz
    let l = 0, r = 0
    if (cs.clipPath.startsWith('inset')) {
      if (m.length === 1) { l = r = toPx(m[0]) }
      else if (m.length === 2) { l = r = toPx(m[1]) }
      else if (m.length >= 4) { r = toPx(m[1]); l = toPx(m[3]) }
    }
    const visible = Math.max(0, w - l - r) / w
    return { o: +cs.opacity * visible, visible, clip: cs.clipPath }
  })
  // at load, before any scroll
  let r = await read()
  if (r.o > 0.02) fails.push(`${name} load: wordmark visible ${r.o} (want 0)`)
  console.log(`${name.padEnd(8)} load         visible ${r.o.toFixed(3)}`)

  for (const [label, p, want] of BEATS.slice(1)) {
    await page.evaluate((y) => window.scrollTo({ top: y, behavior: 'instant' }), p * span)
    await page.waitForTimeout(850)
    r = await read()
    const ok = want === 'hidden' ? r.o <= 0.02
      : want === 'partial' ? (r.o > 0.02 && r.o < 0.98)
      : r.o >= 0.55
    if (!ok) fails.push(`${name} ${label}: visible ${r.o.toFixed(3)}, wanted ${want}`)
    console.log(`${name.padEnd(8)} ${label.padEnd(12)} visible ${r.o.toFixed(3)} ${ok ? '' : '  <-- FAIL'}`)
  }

  // reversibility: scroll back before the reveal, it must hide again
  await page.evaluate((y) => window.scrollTo({ top: y, behavior: 'instant' }), 0.4 * span)
  await page.waitForTimeout(900)
  r = await read()
  if (r.o > 0.02) fails.push(`${name} scrolled back to 0.40: visible ${r.o.toFixed(3)} (want 0)`)
  console.log(`${name.padEnd(8)} back-to-0.40 visible ${r.o.toFixed(3)}`)
  await page.close()
}
// em dashes in rendered copy
const page = await b.newPage({ viewport: { width: 1440, height: 900 } })
await page.goto(URL, { waitUntil: 'networkidle' })
const dashes = await page.evaluate(() => {
  const out = []
  const walk = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT)
  let n; while ((n = walk.nextNode())) if (n.nodeValue.includes('—')) out.push(n.nodeValue.trim().slice(0, 70))
  if (document.title.includes('—')) out.push('<title> ' + document.title)
  const d = document.querySelector('meta[name=description]')
  if (d && d.content.includes('—')) out.push('<meta description>')
  return out
})
console.log('\nem dashes in rendered copy:', dashes.length ? dashes : 'none')
if (dashes.length) fails.push('em dashes still rendered: ' + dashes.join(' | '))
await b.close()
console.log(fails.length ? '\nFAILURES:\n' + fails.join('\n') : '\nALL CHECKS PASS')
