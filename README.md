# 4loops

> A personal orientation layer for solo operators, packaged as a Claude Code plugin: a story-state kanban + daily/weekly priorities + surfaced drift — enforced by a SessionStart sentinel and a PreToolUse hard gate.

4loops turns any workspace into a story-driven operator loop. Work is tracked as stories moving across a five-state board (**Backlog → Planning → In Progress → Testing → Done**). A short daily reconciliation sets your 1–3 focus stories; a weekly one sets your anchors. Drift — stale states, column caps, abandoned candidates — is *surfaced*, never nagged. And the discipline is the product: when today's or this week's focus is stale, a hard gate blocks edits to your **product surfaces** until you reconcile the board. Reading, research, and notes are never blocked.

It operates on whatever workspace it is enabled in. All state is plain files under `.4loops/` — no database, no network.

## The loop

**You drive 4loops by *seeing the board and picking what moved*** — not by typing a state command per
story, and not by narrating it in prose. A reconciliation command **prints the board, then offers
structured options** (started / testing / done / park); you tick what changed and it runs the rails.
Three reconcilers + one capture are the only things that move the board; it never moves on its own.

| Command | What it does |
| --- | --- |
| `/4loops:configure` | **First-run setup** (run once): detect your projects, pick a week-start, confirm gated surfaces, spawn this week's focus — and pin your board. |
| `/4loops:today` | **Daily reconcile** — prints the board, then you pick what started / moved / finished / parks; sets 1–3 focus, lifts the day's gate. Leads with overdue / due-soon. |
| `/4loops:week` | **Weekly reconcile** — wider lens; pick done / commit-this-week / drop, set 3–5 anchors. Run first on a new ISO week (its context flows into `/today`). |
| `/4loops:priority` | **In-between** — when work lands between rituals: prints what's changed, you bump focus / nudge a state / capture urgent work. Lighter than the full walk. |
| `/4loops:arrange <blurb>` | **Capture** — brain-dump work in one go; it drafts the stories (type + deadline) onto the board. User-invoked only; never sets priority. |
| `/4loops:board` | Render the kanban (keep it pinned — see below). |

Capture carries **type** (`dev` / `modeling`) and an optional **deadline** (`--deadline YYYY-MM-DD`) — the deadline powers prioritization + drift. Under the hood, draft / transition / archive / close scripts are the rails the reconcilers call — there are no per-state slash commands to memorize; the six above are the whole surface. (Power users can still shell the rail scripts directly, e.g. `vt-transition.sh <id> done`, but you never need to.)

> **Pin your board.** The print-once model assumes the board is glanceable. Open `.4loops/board.md`, pin the tab, and toggle Markdown preview (VS Code: right-click tab → Pin · ⌘K V). `/4loops:configure` reminds you on first run.

## How it enforces

- **SessionStart sentinel** — renders the board dashboard, surfaces drift, and auto-runs the weekly rollover (Done → `archive/<month>/closed.md`).
- **PreToolUse hard gate** — focus-staleness blocks writes to gated product surfaces until the daily/weekly reconciliation runs. Per-session clearance carries across midnight; a single-action override (`VT_ALLOW_STALE_GATE=1`) is logged for escapes.
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

## What's new in v2.1

The spine, hardened for daily driving:

- **See-then-pick reconciliation** — `/today`, `/week`, and `/priority` print the board, then offer structured options (started / done / park…); you tick what moved and it runs the rails. No `/start`/`/done` typing per story, no prose narration. `/arrange` captures a brain-dump in one go.
- **Story types** — `dev` (fixed objective, DONE = shipped) vs `modeling` (fluid objective, DONE = a coherent, traceable decision log). Modeling stories are marked ◆ on the board and reminded at DONE.
- **Deadlines** — capture a `--deadline`; overdue and due-soon stories surface in drift and lead your daily/weekly prioritization (it's how you see you're going off-plan).
- **Cleaner capture** — a story's context renders as a markdown link, not a bare file path (nicer board, better image exports).
- **Honest endings** — the weekly `/4loops:week` prune retires dead work off the board: `abandoned` (dropped) or `superseded` (replaced by another story), recorded in the month's archive; `/4loops:priority` can retire one mid-week. `--backdate YYYY-MM-DD` records retroactive work on its real date.
- **Midweek re-point** — `/4loops:priority` adjusts today's focus between rituals; `priority since` surfaces what's landed since you last set focus, so new work doesn't silently outrun your priorities.
- **`/4loops:arrange`** — brain-dump a batch of work in plain language; it proposes stories and drafts them onto the board on your confirm. User-invoked only — it never fires on its own and never sets your priority.
- **The board can't be hand-edited out of band** — `board.md` and `current-priorities.md` are rail-owned; direct edits are blocked (they'd desync counts + the log). Everything rides the rails. Override with `VT_ALLOW_RECORD_WRITE=1`.
- **Self-cleaning state** — replicating idempotency markers are GC'd to latest-only.

All additive — v2.0 boards keep working untouched.

## Install

```
/plugin marketplace add idnk2203/4loops
/plugin install 4loops
```

Then run **`/4loops:configure`** once. It detects your projects, asks for a week-start, confirms the gated surfaces, and spawns this week's focus onto the board — so your first session ends on a board full of *your* work, not an empty template. After that the loop is `/4loops:today` daily, `/4loops:week` weekly.

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
