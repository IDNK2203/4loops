# Vibe Table (`vt`)

> A personal orientation layer for solo operators, packaged as a Claude Code plugin: a story-state kanban + daily/weekly priorities + surfaced drift — enforced by a SessionStart sentinel and a PreToolUse hard gate.

Vibe Table turns any workspace into a story-driven operator loop. Work is tracked as stories moving across a five-state board (**Backlog → Planning → In Progress → Testing → Done**). A short daily reconciliation sets your 1–3 focus stories; a weekly one sets your anchors. Drift — stale states, column caps, abandoned candidates — is *surfaced*, never nagged. And the discipline is the product: when today's or this week's focus is stale, a hard gate blocks edits to your **product surfaces** until you reconcile the board. Reading, research, and notes are never blocked.

It operates on whatever workspace it is enabled in. All state is plain files under `.vibe-table/` — no database, no network.

## The loop

| Command | What it does |
| --- | --- |
| `/vt:configure` | **First-run setup** (run once): detect your projects, pick a week-start, confirm which surfaces the gate guards, then spawn this week's focus. |
| `/vt:today` | Daily board reconciliation; sets 1–3 focus stories and lifts the day's gate. |
| `/vt:week` | Weekly reconciliation; sets 3–5 anchors. Run first on a new ISO week. |
| `/vt:board` | Render the kanban. |
| `/vt:draft <title>` | Capture a new story-draft into Backlog. |
| `/vt:plan` · `/vt:start` · `/vt:test` · `/vt:done` | Move a story across states. |
| `/vt:close [--weekly]` | End-of-day drift retro; `--weekly` archives Done → `archive/`. |

## How it enforces

- **SessionStart sentinel** — renders the board dashboard, surfaces drift, and auto-runs the weekly rollover (Done → `archive/<month>/closed.md`).
- **PreToolUse hard gate** — focus-staleness blocks writes to gated product surfaces until the daily/weekly reconciliation runs. Per-session clearance carries across midnight; a single-action override (`VT_ALLOW_STALE_GATE=1`) is logged for escapes.
- **Bash writes too** — a path-only Edit/Write gate is bypassable by shelling out, so the gate also re-derives write targets from Bash commands (`>`, `>>`, `tee`, `sed -i`) and applies the identical check. Known blind spots (not detected): `mv` / `cp` / `python -c "open(...)"` / `node -e`. Recommended: set `CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR=1` so relative paths resolve against the workspace root.
- **Narrow by default** — only your product/deliverable surfaces are gated; research and notes always flow. `/vt:configure` proposes the gated set from what it finds in your workspace and lets you trim or add (see [Configuration](#configuration)).

## Configuration

`/vt:configure` writes `.vibe-table/config` (plain `key: value` lines) plus your projects into the board. Re-running is safe — keys are replaced, project rows upserted. You can also hand-edit:

| Key | Values | Effect |
| --- | --- | --- |
| `week-start:` | `mon` (default) / `sun` | First day of the week — threads through the week range, the staleness check, and the weekly rollover boundary. |
| `gated:` | one glob per line, root-relative | The product surfaces the gate guards. **Any `gated:` line replaces the built-in default** (`projects/*/content/*`, `projects/*/gists/*`, `projects/*/repo-scaffolding/*`) — list every surface you want gated. |

```
week-start: mon
gated: projects/*/content/*
gated: projects/*/gists/*
```

The **hard-exempt** surfaces are always writable regardless of config — `.vibe-table/`, `.claude/`, `study/`, `learnings/`, `inbox/`, `reviews/`, root `*.md`, `ARTIFACTS.md`, `.env*`, `.gitignore` — so the gate can never block its own reconciliation, your research, or your notes.

## Install

> Currently dogfooded via a local directory marketplace during BLS P0. At ship this relocates to a public GitHub marketplace.

```
/plugin marketplace add idnk2203/vibe-table
/plugin install vt
```

Then run **`/vt:configure`** once. It detects your projects, asks for a week-start, confirms the gated surfaces, and spawns this week's focus onto the board — so your first session ends on a board full of *your* work, not an empty template. After that the loop is `/vt:today` daily, `/vt:week` weekly.

The plugin stays quiet in any workspace without a `.vibe-table/` directory — install it globally and it only wakes up where you've configured it.

## Requirements

Claude Code with plugin support. `jq` recommended — the hooks degrade gracefully without it.

## License

MIT — see [`LICENSE`](LICENSE).

## Author

[Ese Idukpaye](https://github.com/idnk2203). Built in the open as part of BLS (Build / Learn / Share).
