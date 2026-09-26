# .agents — shared context for every AI tool on this repo

This folder is the **shared context** for Claude Code, ChatGPT, Cursor, Copilot,
Windsurf, or anything else working on BUMP. It is tracked on
`ios-mockup-vis-charan` so the same repo instructions reach the team.
The root `AGENTS.md` points agents here automatically.

## For the human

Point each tool at this folder once:

| Tool | How |
|---|---|
| Claude Code | `@.agents/` in a prompt, or "read .agents/ first" |
| Cursor | Settings ▸ Rules ▸ reference `.agents/00-start-here.md` |
| ChatGPT / web chat | paste `00-start-here.md` + the file for the area you're in |
| Copilot Chat | `#file:.agents/00-start-here.md` |

## For the agent (you)

**Read `00-start-here.md` before touching anything.** Then read only the area
file you need. When you finish a meaningful chunk of work, append to
`90-worklog.md` so the next tool does not repeat you.

## Files

| File | What it holds |
|---|---|
| `00-start-here.md` | Repo map, how to run each part, house rules. Start here. |
| `10-web.md` | The marketing site. Deep detail: tokens, sections, the GSAP hero. |
| `11-material-design.md` | Material Design 3: what is installed, the traps, our seed palette. |
| `20-backend.md` | `bump-api`, the Node service between the app and xAI. |
| `30-ios.md` | The SwiftUI app. |
| `31-ios-mockup.md` | The HTML mockup of the app (no Mac): how to run it, the design language, what the human rejected, porting notes, git state. |
| `40-conventions.md` | Voice, copy rules, design rules, accessibility bar. |
| `60-master-doc.md` | The team's HackGT master doc (Google Doc): intent, draft copy, research, and OPEN conflicts with the repo. |
| `50-decisions.md` | Decisions already made, with the reason. Do not relitigate. |
| `90-worklog.md` | Append-only log. Who (which tool) did what, when. |

## Rules for keeping this folder useful

1. **Append, do not rewrite.** Especially `90-worklog.md` and `50-decisions.md`.
2. **Facts, not plans.** Record what is true now and why, not what you intend.
3. **If you change the code so a doc here is wrong, fix the doc in the same pass.**
4. **Never put secrets here** (no `XAI_API_KEY`, no tokens). This folder is
   committed to the public repo.
