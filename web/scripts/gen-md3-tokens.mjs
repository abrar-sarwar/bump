/**
 * Regenerate the MD3 colour roles in src/styles/tokens.css.
 *
 * MD3 colour is ALGORITHMIC: every role is derived from one seed colour in the
 * HCT colour space. Hand-editing a role puts it out of sync with the algorithm,
 * so change SEED here and re-run instead.
 *
 * NOTE: @material/material-color-utilities ships extensionless internal imports,
 * so plain `node scripts/gen-md3-tokens.mjs` fails with ERR_MODULE_NOT_FOUND.
 * Bundle it first (bundlers resolve extensionless paths, Node does not):
 *
 *   npx esbuild scripts/gen-md3-tokens.mjs --bundle --platform=node \
 *     --format=esm --outfile=/tmp/gen.mjs && node /tmp/gen.mjs
 *
 * It prints CSS to stdout. Paste the block into tokens.css; it does not write
 * the file, so a bad seed can never silently destroy the palette.
 */
import {
  argbFromHex, hexFromArgb, themeFromSourceColor, Hct,
} from '@material/material-color-utilities'

const SEED = '#70aaf9' // BUMP wordmark ink, measured off assets-source/wordmark.source.png

const theme = themeFromSourceColor(argbFromHex(SEED))
const hct = Hct.fromInt(argbFromHex(SEED))
const kebab = (s) => s.replace(/[A-Z]/g, (c) => '-' + c.toLowerCase())

console.log(`/* seed ${SEED} -> HCT hue ${hct.hue.toFixed(1)} · chroma ${hct.chroma.toFixed(1)} · tone ${hct.tone.toFixed(1)} */`)

for (const [role, argb] of Object.entries(theme.schemes.light.toJSON())) {
  console.log(`  --md-sys-color-${kebab(role)}: ${hexFromArgb(argb)};`)
}

// The 2021 scheme predates the surface container ladder, so derive it from the
// same neutral palette per the MD3 2023 spec.
const n = (t) => hexFromArgb(theme.palettes.neutral.tone(t))
console.log(`  --md-sys-color-surface-dim: ${n(87)};`)
console.log(`  --md-sys-color-surface-bright: ${n(99)};`)
console.log(`  --md-sys-color-surface-container-lowest: ${n(100)};`)
console.log(`  --md-sys-color-surface-container-low: ${n(96)};`)
console.log(`  --md-sys-color-surface-container: ${n(94)};`)
console.log(`  --md-sys-color-surface-container-high: ${n(92)};`)
console.log(`  --md-sys-color-surface-container-highest: ${n(90)};`)
