# Vibe Table (`vt`)

> A personal orientation layer for solo operators, packaged as a Claude Code plugin: a story-state kanban + daily/weekly priorities + surfaced drift — enforced by a SessionStart sentinel and a PreToolUse hard gate.

Vibe Table turns any workspace into a story-driven operator loop. Work is tracked as stories moving across a five-state board (**Backlog → Planning → In Progress → Testing → Done**). A short daily reconciliation sets your 1–3 focus stories; a weekly one sets your anchors. Drift — stale states, column caps, abandoned candidates — is *surfaced*, never nagged. And the discipline is the product: when today's or this week's focus is stale, a hard gate blocks edits to your **product surfaces** until you reconcile the board. Reading, research, and notes are never blocked.

It operates on whatever workspace it is enabled in. All state is plain files under `.vibe-table/` — no database, no network.

## The loop

| Command | What it does |
| --- | --- |
| `/vt:today` | Daily board reconciliation; sets 1–3 focus stories and lifts the day's gate. |
| `/vt:week` | Weekly reconciliation; sets 3–5 anchors. Run first on a new ISO week. |
| `/vt:board` | Render the kanban. |
| `/vt:draft <title>` | Capture a new story-draft into Backlog. |
| `/vt:plan` · `/vt:start` · `/vt:test` · `/vt:done` | Move a story across states. |
| `/vt:close [--weekly]` | End-of-day drift retro; `--weekly` archives Done → `archive/`. |

## How it enforces

- **SessionStart sentinel** — renders the board dashboard, surfaces drift, and auto-runs the weekly rollover (Done → `archive/<month>/closed.md`).
- **PreToolUse hard gate** — focus-staleness blocks writes to gated product surfaces until the daily/weekly reconciliation runs. Per-session clearance carries across midnight; a single-action override (`VT_ALLOW_STALE_GATE=1`) is logged for escapes.
- **Narrow by default** — only your product/deliverable surfaces are gated (configurable via `.vibe-table/config`); research and notes always flow.

## Install

> Currently dogfooded via a local directory marketplace during BLS P0. At ship this relocates to a public GitHub marketplace.

```
/plugin marketplace add idnk2203/vibe-table
/plugin install vt
```

Then run `/vt:today` to arm the loop.

## Requirements

Claude Code with plugin support. `jq` recommended — the hooks degrade gracefully without it.

## License

MIT — see [`LICENSE`](LICENSE).

## Author

[Ese Idukpaye](https://github.com/idnk2203). Built in the open as part of BLS (Build / Learn / Share).

<!-- NOTE (pre-ship): framing/voice is a first-pass draft — refine before public ship. -->
