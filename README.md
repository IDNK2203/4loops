# 4loops

> A personal orientation layer for solo operators, packaged as a Claude Code plugin: a story-state kanban + daily/weekly priorities + surfaced drift. You run two short rituals — and **between them you just talk**.

4loops turns any workspace into a story-driven operator loop. Work is tracked as stories moving across a five-state board (**Backlog → Planning → In Progress → Testing → Done**). A short daily reconciliation sets your 1–3 focus stories; a weekly one sets your anchors. Drift — stale states, overdue/due-soon deadlines, column caps — is *surfaced*, never nagged. And the discipline is the product: when today's or this week's focus is stale, a hard gate blocks edits to your **product surfaces** until you reconcile the board. Reading, research, and notes are never blocked.

It operates on whatever workspace it is enabled in. All state is plain files under `.4loops/` — no database, no network.

## The loop

The loop has four acts — **capture · check · prioritize · review** — at two cadences (daily, weekly). You never have to *think* about those acts: you run two rituals on a rhythm, and for everything in between, **you open one command and talk.**

**Between rituals, just talk.** Open `/4loops:nav` once and then say what's happening — *"the metrics endpoint is done, start the pricing copy, add rate limiting due Friday."* It opens on a **priority-annotated board** (★ today's focus · ! overdue · ⏳ due-soon · ◆ modeling — where you stand vs your day/week), then turns each thing you say into a real board move and runs it on the rails. New tasks, state moves, priority, retirements — all by talking, no commands to memorize.

| Command | What it does |
| --- | --- |
| `/4loops:configure` | **First-run setup** (run once): detect your projects, pick a week-start, confirm gated surfaces, spawn this week's focus — and pin your board. |
| `/4loops:week` | **Weekly ritual** — wider lens; pick done / commit-this-week / retire, set 3–5 anchors. **Run first on a new ISO week** (its context flows into the day; `/today` is blocked until it runs). |
| `/4loops:today` | **Daily ritual** — prints the board, you pick what started / moved / finished / parks; sets 1–3 focus, lifts the day's gate. Leads with overdue / due-soon. |
| `/4loops:nav` | **In-between — just talk.** The intra-cadence loop: open it and speak; it captures, moves state, re-points priority, retires — on the real rails, opening on the priority-annotated board. |
| `/4loops:board` | Render the raw kanban (keep it pinned — see below). |

Stories carry **type** (`dev` / `modeling`) and an optional **deadline** — the deadline powers prioritization + drift. The whole surface is the five commands above. Capture/check(move)/prioritize also exist as thin hidden escapes (`/4loops:capture`, `:manage`, `:prioritize`) for direct use, but the normal path is to just talk in `/nav`.

> **Pin your board.** The rituals + `/nav` assume the board is glanceable. Open `.4loops/board.md`, pin the tab, and toggle Markdown preview (VS Code: right-click tab → Pin · ⌘K V). `/4loops:configure` reminds you on first run.

## The rules (how the board stays honest)

4loops never moves your board on its own — and never *pretends* to:

- **You hold the key.** Every board-touching command is **user-invoked only** — Claude can't start a reconciliation, capture, or move on its own. The command you type is your consent; nothing happens ambiently.
- **Operate, never simulate.** Inside `/nav`, every change runs a real rail and **re-renders the board from disk as proof** — and the gate physically blocks hand-editing the board files, so a move can't be faked. If the board didn't change, it didn't happen.
- **Config first.** Every command requires `/4loops:configure` to have run — a fresh install does nothing until you set it up.
- **Week before day.** On a new ISO week, `/4loops:week` must run before `/4loops:today` — the weekly anchors flow into the day. `/today` refuses until the week is reconciled.
- **The board can't be hand-edited.** `board.md` / `current-priorities.md` are rail-owned; direct edits are blocked. Like the gate, the override (`VT_ALLOW_RECORD_WRITE=1`) is env-only — the agent can't set it; it edits only through the rails.

## How it enforces

- **SessionStart sentinel** — renders the board dashboard, surfaces drift, and auto-runs the weekly rollover (Done → `archive/<month>/closed.md`).
- **PreToolUse hard gate** — focus-staleness blocks writes to gated product surfaces until the daily/weekly reconciliation runs. Per-session clearance carries across midnight. The gate is **un-bypassable by the agent**: the override is read only from the session's environment (launch with `VT_ALLOW_STALE_GATE=1`), which the agent can't set — its only path when blocked is to stop and have you reconcile. Every override is logged to `override.log`.
- **Bash writes too** — a path-only Edit/Write gate is bypassable by shelling out, so the gate also re-derives write targets from Bash commands (`>`, `>>`, `tee`, `sed -i`, `rm`, `mv`, `cp`, `touch`, `ln`, `mkdir`) — honoring a leading `cd <dir> &&` so relative targets resolve right — and applies the identical check. Residual blind spots (fail-open): glob/quoted args, mid-command `cd` chains, and arbitrary-code writers (`python -c`, `node -e`). Recommended: set `CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR=1` so relative paths resolve against the workspace root.
- **Project-scoped by default** — each tracked project is gated as a *whole* (everything inside it, source included); Areas — notes, research, docs — always flow. `/4loops:configure` proposes the gated set (your projects) and lets you trim or add (see [Configuration](#configuration)).

## Configuration

**Projects & Areas.** `/4loops:configure` detects your **git repos** as *Projects* — the things you track to a done-state on the board, each **gated as a whole** (every file inside, source included). A single repo opened at the workspace root counts as one project too. Every other top-level folder is an *Area*: evolving notes/docs with no done-state, left untracked and free to edit. Promote an Area to a Project (or demote one) during setup — git is just the default signal, the call is yours.

`/4loops:configure` writes `.4loops/config` (plain `key: value` lines) plus your projects into the board. Re-running is safe — keys are replaced, project rows upserted. You can also hand-edit:

| Key | Values | Effect |
| --- | --- | --- |
| `week-start:` | `mon` (default) / `sun` | First day of the week — threads through the week range, the staleness check, and the weekly rollover boundary. |
| `gated:` | one glob per line, root-relative | The projects the gate guards — whole-project globs like `apps/web-dashboard/*` (the `*` spans subdirectories, so everything inside is covered). **Any `gated:` line replaces the built-in default** — list every surface you want gated. |

```
week-start: mon
gated: apps/web-dashboard/*
gated: apps/notes-cli/*
```

The **hard-exempt** surfaces are always writable regardless of config — `.4loops/`, `.claude/`, `study/`, `learnings/`, `inbox/`, `reviews/`, root `*.md`, `ARTIFACTS.md`, `.env*`, `.gitignore` — so the gate can never block its own reconciliation, your research, or your notes.

## What's new in v2.2

The intra-cadence loop — **between the rituals, you just talk:**

- **`/4loops:nav` — talk, don't click.** Open it once and speak ("metrics endpoint is done, start the pricing copy, add rate limiting due Friday"); it maps each thing to a real board move and runs it. The high-traffic acts (capture, move state, prioritize, retire) collapse into one conversation — no commands to memorize.
- **Priority-annotated board.** `/nav` (and `vt-render --priorities`) overlays your standing relative to your day/week onto the kanban: **★ today's focus · ! overdue · ⏳ due-soon · ◆ modeling.** "Where am I," not just "what's on the board."
- **Operate, never simulate.** Every `/nav` change runs a rail and re-renders from disk as proof; the gate blocks hand-edits, so a move can't be faked. It also refuses to invent IDs — if it can't match what you said to a real story, it asks.
- **Week-before-day, enforced.** On a fresh ISO week `/today` is *refused* until `/week` runs — the weekly anchors flow into the day (was only a nudge).
- **User-invoked only.** Every board-touching command is `disable-model-invocation` — Claude can't move your board on its own. The typed command is your consent.
- **Hidden escapes.** `/4loops:capture`, `:manage`, `:prioritize` remain for direct use, but `/nav` does all three by talking.

Carried forward from **v2.1**: see-then-pick rituals · story types (`dev` / `modeling`, ◆) · deadlines + deadline-aware drift · context-as-link · honest endings (abandon / supersede / backdate) · rail-owned records · self-cleaning markers. All additive — v2.0/v2.1 boards keep working untouched.

## Install

```
/plugin marketplace add idnk2203/4loops
/plugin install 4loops
```

Then run **`/4loops:configure`** once. It detects your projects, asks for a week-start, confirms the gated surfaces, and spawns this week's focus onto the board — so your first session ends on a board full of *your* work, not an empty template. After that: `/4loops:week` each new week, `/4loops:today` each day, and **`/4loops:nav` to just talk** in between.

The plugin stays quiet in any workspace without a `.4loops/` directory — install it globally and it only wakes up where you've configured it.

### Upgrading from v1.x (`vt` / Vibe Table)

v2.0.0 renames the plugin **`vt` → `4loops`** and its state directory **`.vibe-table/` → `.4loops/`**. Two breaking changes:

```
# 1. reinstall under the new name
/plugin install 4loops          # commands move from /vt:* to /4loops:*

# 2. in each workspace you tracked, rename the state dir
mv .vibe-table .4loops
```

That's it — the board, config, archive, and logs inside are unchanged.

## Requirements

Claude Code with plugin support. `jq` recommended — the hooks degrade gracefully without it.

## License

MIT — see [`LICENSE`](LICENSE).

## Author

[Ese Idukpaye](https://github.com/idnk2203). Built in the open as part of BLS (Build / Learn / Share).
