import { chromium } from 'playwright'
const URL = process.argv[2] ?? 'http://localhost:4173'
const b = await chromium.launch({ channel: 'chrome' })
const out = []
const errs = []

const page = await b.newPage({ viewport: { width: 1440, height: 900 } })
page.on('pageerror', e => errs.push('pageerror: ' + e.message))
page.on('console', m => { if (m.type() === 'error') errs.push('console: ' + m.text()) })
await page.goto(URL, { waitUntil: 'networkidle' })
await page.waitForTimeout(800)

const heroH = () => page.evaluate(() => document.querySelector('.hero').getBoundingClientRect().height)
const overflow = () => page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)

out.push(`hero height @1440x900: ${await heroH()} (expect ~3780)`)

// resize desktop -> desktop
await page.setViewportSize({ width: 1100, height: 700 })
await page.waitForTimeout(900)
out.push(`hero height @1100x700: ${await heroH()} (expect ~2940) overflow=${await overflow()}`)

// cross the breakpoint into mobile layout
await page.setViewportSize({ width: 420, height: 800 })
await page.waitForTimeout(900)
out.push(`hero height @420x800 (mobile tl): ${await heroH()} (expect ~2720) overflow=${await overflow()}`)

// back to desktop
await page.setViewportSize({ width: 1440, height: 900 })
await page.waitForTimeout(900)
out.push(`hero height back @1440x900: ${await heroH()} overflow=${await overflow()}`)

// backward scroll: go to the end of the hero, then back to the very top
await page.evaluate(() => window.scrollTo(0, 2600)); await page.waitForTimeout(700)
await page.evaluate(() => window.scrollTo(0, 0)); await page.waitForTimeout(900)
const restPose = await page.evaluate(() => {
  const s = getComputedStyle(document.querySelector('.hero__phone--blue'))
  const cue = getComputedStyle(document.querySelector('.hero__cue')).opacity
  return { transform: s.transform, cueOpacity: cue }
})
out.push(`after scrolling to end and back to top: cue opacity=${restPose.cueOpacity} (expect ~1)`)

// fast scroll burst
for (let y = 0; y <= 3000; y += 250) { await page.evaluate(v => window.scrollTo(0, v), y) }
await page.waitForTimeout(900)
out.push(`fast scroll burst: overflow=${await overflow()}, errors so far=${errs.length}`)

// anchor navigation
for (const id of ['#the-idea', '#how-it-works', '#the-overlap']) {
  await page.evaluate(() => window.scrollTo(0, 0)); await page.waitForTimeout(300)
  await page.click(`a[href="${id}"]`); await page.waitForTimeout(700)
  const ok = await page.evaluate(sel => {
    const r = document.querySelector(sel).getBoundingClientRect()
    return Math.abs(r.top) < 260
  }, id)
  out.push(`anchor ${id}: ${ok ? 'lands on section' : 'MISSED'}`)
}

// refresh partway down the page
await page.evaluate(() => window.scrollTo(0, 4200))
await page.reload({ waitUntil: 'networkidle' })
await page.waitForTimeout(1200)
out.push(`reload at scroll 4200: restored y=${await page.evaluate(() => Math.round(window.scrollY))}, overflow=${await overflow()}`)

// every link/button has a destination or handler
const dead = await page.evaluate(() =>
  [...document.querySelectorAll('a')].filter(a => !a.getAttribute('href') || a.getAttribute('href') === '#').map(a => a.textContent.trim()))
out.push(`links with no destination: ${dead.length ? dead.join(', ') : 'none'}`)

await b.close()
console.log(out.join('\n'))
console.log(errs.length ? '\nERRORS:\n' + errs.join('\n') : '\nno console/page errors')
