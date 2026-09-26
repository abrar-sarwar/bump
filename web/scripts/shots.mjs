/**
 * Visual check harness. Captures the hero at the beats that matter plus the
 * sections below, on desktop and mobile, and reports console errors and
 * horizontal overflow. Run against a live dev/preview server:
 *
 *   npm run preview  &  node scripts/shots.mjs http://localhost:4173
 */
import { chromium } from 'playwright'
import { mkdirSync } from 'node:fs'

const URL = process.argv[2] ?? 'http://localhost:4173'
const OUT = 'shots'
mkdirSync(OUT, { recursive: true })

// Hero scroll length must match BumpHero.tsx (end: '+=Nvh').
const HERO_VH = { desktop: 3.2, mobile: 2.4 }

const DEVICES = [
  { name: 'desktop', viewport: { width: 1440, height: 900 } },
  { name: 'mobile', viewport: { width: 390, height: 844 }, isMobile: true, deviceScaleFactor: 2 },
]

const BEATS = [
  ['00-opening', 0.0],
  ['01-approach', 0.32],
  ['02-pre-contact', 0.47],
  ['03-contact', 0.53],
  ['04-recoil', 0.6],
  ['05-reveal', 0.78],
  ['06-settled', 0.93],
]

const browser = await chromium.launch({ channel: 'chrome' })
const problems = []

for (const dev of DEVICES) {
  for (const reduced of [false, true]) {
    if (reduced && dev.name === 'mobile') continue
    const ctx = await browser.newContext({
      ...dev,
      reducedMotion: reduced ? 'reduce' : 'no-preference',
    })
    const page = await ctx.newPage()
    page.on('console', (m) => {
      if (m.type() === 'error') problems.push(`[console ${dev.name}] ${m.text()}`)
    })
    page.on('pageerror', (e) => problems.push(`[pageerror ${dev.name}] ${e.message}`))

    await page.goto(URL, { waitUntil: 'networkidle' })
    await page.waitForTimeout(700)

    const tag = reduced ? `${dev.name}-reduced` : dev.name

    if (reduced) {
      await page.screenshot({ path: `${OUT}/${tag}-full.png`, fullPage: true })
    } else {
      const vh = dev.viewport.height
      const span = HERO_VH[dev.name] * vh
      for (const [label, p] of BEATS) {
        await page.evaluate((y) => window.scrollTo({ top: y, behavior: 'instant' }), p * span)
        await page.waitForTimeout(900) // let the scrub settle
        await page.screenshot({ path: `${OUT}/${tag}-${label}.png` })
      }
      // sections below the fold
      for (const [label, sel] of [
        ['10-idea', '#the-idea'],
        ['11-how', '#how-it-works'],
        ['12-overlap', '#the-overlap'],
        ['13-cta', '.section--cta'],
      ]) {
        await page.locator(sel).scrollIntoViewIfNeeded()
        await page.waitForTimeout(400)
        await page.screenshot({ path: `${OUT}/${tag}-${label}.png` })
      }
    }

    // horizontal overflow check
    const overflow = await page.evaluate(() =>
      document.documentElement.scrollWidth - document.documentElement.clientWidth)
    if (overflow > 1) problems.push(`[overflow ${tag}] ${overflow}px horizontal scroll`)

    await ctx.close()
  }
}

await browser.close()
console.log(problems.length ? problems.join('\n') : 'no console errors, no horizontal overflow')
