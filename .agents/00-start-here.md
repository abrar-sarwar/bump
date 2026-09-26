# START HERE — BUMP

> Read this file first, every session, whichever tool you are.
> Then read only the area file you need (`10-web.md`, `20-backend.md`, `30-ios.md`,
> `31-ios-mockup.md`).

## What BUMP is

**Meet someone. Find your overlap.**

Two people tap phones together. Each confirms it was really the other person.
Both phones then show the specific interests they genuinely share, plus a few
grounded talking points to open with.

Built at **HackGT**. There is no account system. Bump matching and profile
exchange are partner-only. The current iOS code tries the BUMP server relay for
room transport when available and uses Multipeer when it is not. The server also
handles consented voice transcription and Grok text; if that service is
unreachable, the app uses on-phone suggestions and says so.

**The team's plan lives in a Google Doc**, captured in `60-master-doc.md`. The
doc is intent and draft copy; the repo is what is built. It lists open
conflicts between the two (rarity scoring and more). StreetPass has since been
implemented on `main`; check the current repo before acting on older conflicts.
**Do not act on unresolved conflicts without the human.**

## Repo map

```
bump/
├── web/        React + TS + Vite marketing site. GSAP scroll hero. Standalone.
├── ios/        SwiftUI app. CoreMotion + UWB + Multipeer/server relay + StreetPass.
├── backend/    bump-api: zero-dependency Node >= 20 service with relay and xAI.
├── ios-mockup/ HTML stand-in for the iOS UI. Design here (no Mac), port to Swift.
├── README.md   Top-level overview
├── AGENTS.md   Entry point to the tracked agent notes
├── RESULTS.md  Blank test-day templates (rejection rate, accuracy) — unfilled
└── .agents/    ← you are here. Tracked shared AI context on this branch.
```

The three parts are **independent**. `web/` imports nothing from `ios/`.
`ios/` talks to `backend/` over HTTP only, per `backend/CONTRACT.md`.

## Running things

Node in WSL comes from nvm, not the Windows PATH. Prefix when needed:

```bash
export PATH="$HOME/.nvm/versions/node/v24.19.0/bin:$PATH"
```

| Part | Commands |
|---|---|
| **web** | `cd web && npm install && npm run dev` → http://localhost:5173 <br> `npm run build` (tsc -b then vite build) · `npm run preview` → :4173 · `npm run typecheck` |
| **backend** | `cd backend && cp .env.example .env` (add `XAI_API_KEY`) `&& npm start` → :8787 <br> `npm test` (mocked, no network, free) · `npm run smoke` (LIVE, costs money) |
| **ios-mockup** | `python3 -m http.server 8000 --bind 0.0.0.0 -d ios-mockup` → http://localhost:8000 (or open `index.html`). No build. Read `31-ios-mockup.md` first. |
| **ios** | `open ios/UWBBumpTest.xcodeproj` — needs a Mac with Xcode 26+. Not buildable from this machine (WSL/Windows). |

The repo lives on a Windows drive (`/mnt/c/...`) mounted into WSL. File
watching over that mount is slower than native; if Vite HMR ever stops firing,
restart the dev server rather than debugging the watcher.

## Git

- Remote `origin` → `https://github.com/abrar-sarwar/bump.git` (public).
- Branches: `main` (default), `onboarding`.
- The local user has **write** access via `gh` as `CharanPeeriga`.
- **Do not push or commit unless the human explicitly asks.** If you are on
  `main` and asked to commit, branch first.

## House rules that bite

1. **No em dashes in any shipped web copy.** Not in headings, body, buttons,
   `<title>`, or screen-reader-only text. `web/scripts/verify-reveal.mjs`
   fails the build check if one reaches rendered copy. Use periods, commas or
   colons. (This does not apply inside `.agents/` or code comments.)
2. **Never invent product claims.** No fake download badges, no waitlist, no
   App Store link, no invented metrics. Only real destinations: in-page
   anchors and the actual GitHub repo.
3. **The example match data on the site is fictional and labelled as such.**
   Every claimed overlap must actually appear in both example profiles; there
   is a runtime filter (`VALID`) that drops any example that fails this.
4. **Secrets live in `backend/.env` only**, which is git-ignored. Never put a
   key in code, in a doc, or in this folder.
5. **`assets-source/` originals are never edited.** Derivatives are generated
   by `python3 web/assets-source/extract.py`.

## Current state

| Part | Status |
|---|---|
| `ios/` | The site-style UI port and the merge from current `main` have not been built in Xcode. Swift syntax parses on Linux. **Unproven on two physical phones.** |
| `web/` | Built and verified at both breakpoints, reduced motion, resize, fast scroll. |
| `backend/` | 47 local tests pass, including the new relay tests. Earlier live smoke test against xAI passed. |
| `RESULTS.md` | Empty templates. To fill in on test day. |
| `ios-mockup/` | 38 screens in the site's language (brand kept). Verified in headless Chromium. Latest round **uncommitted**. |

## Where work is happening right now

**2026-09-26, latest:** `origin/main` was fetched and merged locally into
`ios-mockup-vis-charan`, keeping this branch's iOS visual design while adding
main's automatic bump flow, relay, StreetPass, Live Activity and notifications.
The iOS merge needs an Xcode build and visual review on a Mac. There is no
tracked `AGENTS.md` on `main` or the other checked branches. The added
`.agents/agents.md` tunnel note was folded into `20-backend.md` and `30-ios.md`.
The human explicitly requested committing and pushing `.agents/` and the
other local changes to this branch. This branch now has a root `AGENTS.md`
that points at these area notes.

Earlier context follows; some status statements below describe the pre-merge
branch and are retained as history.

**2026-09-26, latest: iOS UI design in `ios-mockup/`**, on branch
**`ios-mockup-vis-charan`** (pushed at `32de3f3`, first transcription only;
the MD3 pass, the restyle after the live site and the tutorial badge work are
uncommitted). The human has no Mac: design happens in HTML, gets approved,
then gets ported to Swift. **Read `31-ios-mockup.md`.** House rules from the
human for this work: keep the brand exactly (the wordmark is artwork, never a
font), take heavy inspiration from `web/` but **never edit `web/`** from
mockup work, and stage only `ios-mockup/` when committing.

Earlier the same day:

**Front-end design of the landing page** (`web/`), on branch
**`landing-page-design`**, pushed to origin at `6124dc3` (2026-09-26). `main` is untouched. No PR yet.

Read `11-material-design.md` before touching any styling: MD3 is the design
language and colour roles are generated from a seed, not hand-picked.

```
1d3d35b  Web: new Horizon wordmark, and a generator that can actually run here
ad94f55  Web: adopt Material Design 3 as the design language
142fb3c  <- main
```

### Open, not done

1. ~~Hero mask timing unverified~~ **Verified 2026-09-26**: a copy of
   `verify-reveal.mjs` passes on both breakpoints (see Environment for how).
2. **The wordmark is lower resolution than what it replaced** (1371px of ink vs
   1875px) and the hero caps at 1560px, so it upscales on wide displays. An SVG
   export fixes it permanently. Asked for, not received.
3. **Horizon font files were never supplied.** Headings are still Archivo. If
   `.woff2` files arrive, point `--md-ref-typeface-brand` at them.

## Environment, learned the hard way

- **Node**: nvm `v24.19.0` in WSL. Bare `node` on PATH does not resolve, and bare
  `npm` is the **Windows** npm (`/mnt/c/Program Files/nodejs/npm`) via interop.
  Always prefix: `export PATH="$HOME/.nvm/versions/node/v24.19.0/bin:$PATH"`.
  Never `npm install -g` anything with the bare npm: it lands on the Windows side.
- **Claude Code here is a NATIVE install**, not npm:
  `~/.local/bin/claude -> ~/.local/share/claude/versions/<v>` (an ELF binary).
  Update it with `claude update`. Running `npm install -g @anthropic-ai/claude-code`
  would create a second, competing Windows-side install.
- **Headless Chromium DOES work now, without root** (2026-09-26). The missing
  system libs were pulled with `apt-get download <pkgs>` (no root needed) and
  unpacked with `dpkg -x` into `~/.local/lib/chromium-deps/`. Run Playwright with
  `LD_LIBRARY_PATH=~/.local/lib/chromium-deps` and the bundled
  `chromium_headless_shell`. The repo scripts still ask for `channel: 'chrome'`,
  so run a scratch copy with that line removed (and `playwright` imported by
  absolute path from `web/node_modules`). If the dir is gone, recreate it:
  `apt-get download libnspr4 libnss3 libasound2t64 libatk1.0-0t64
  libatk-bridge2.0-0t64 libcups2t64 libatspi2.0-0t64 libxdamage1 libxfixes3
  libxrandr2 libxcomposite1 libxkbcommon0 libgbm1 libavahi-common3
  libavahi-client3`, then `dpkg -x` each.
- **Start the dev server with polling**, or edits will not show up at all:
  `CHOKIDAR_USEPOLLING=1 CHOKIDAR_INTERVAL=300 npm run dev`. Without it the
  server kept serving the old modules for a whole session of edits.
- **No root.** No sudo password is available in this environment, so nothing
  apt-installable can be added from a session. That blocks:
  - **Pillow** (so `assets-source/extract.py` cannot run here at all;
    `python3 -m venv` also fails, it needs `python3-venv` via apt)
  - **Headless Chromium's system libs.** The browser downloads fine via
    `npx playwright install chromium`, but will not launch:
    `error while loading shared libraries: libnspr4.so`.
    Ubuntu 24.04 (noble) needs the `t64`-suffixed packages, run in a real
    terminal where sudo can prompt:
    ```
    sudo apt-get install -y libnspr4 libnss3 libasound2t64 libatk1.0-0t64       libatk-bridge2.0-0t64 libcups2t64 libatspi2.0-0t64 libxdamage1       libxfixes3 libxrandr2 libxcomposite1
    ```
  - Note `npx playwright install chromium --with-deps` **exits 0 through a pipe
    even when it fails** on the sudo prompt. Always check
    `~/.cache/ms-playwright/` is non-empty afterwards.
- **The repo's own scripts want real Google Chrome**, not bundled Chromium:
  they call `chromium.launch({ channel: 'chrome' })`, which looks for
  `/opt/google/chrome/chrome`. Bundled Chromium does not satisfy that channel.
  Run a copy with the channel line dropped rather than editing the repo scripts.
- **Vite HMR does not reliably fire over the `/mnt/c` 9p mount.** An open tab can
  show stale CSS while the server serves the new file. Verify with
  `curl -s localhost:5173/src/styles/tokens.css | grep md-sys-color`, then
  hard-reload. Restart the dev server rather than debugging the watcher.
