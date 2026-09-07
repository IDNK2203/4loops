---
name: board
description: Render the 4loops board (kanban of stories by state). Default shows the full active pipeline as a single horizontal 4-column table (Planning | In Progress | Testing | Done), 5 rows per state, with compact cells (ID + title). Slicing flags filter to a single state (full why/context), a custom row cap, or a single project; `--list` gives a vertical view (kanban stays default). Use when the user wants to see the current state of their stories.
allowed-tools: Bash
user-invocable: true
---

Render the 4loops board for the current workspace.

The board is the **active pipeline** — Planning → In Progress → Testing → Done. It is not a capture
pen: uncommitted work lives in the detached store (`/capture`, `/sync`), and Done is short-lived
(`vt-flush.sh` archives it after its dwell). If the render ends with a migration notice, the board
predates v2.5 and still holds cells in a legacy Backlog column — `vt-migrate-backlog.sh` clears it.

## Usage

| Form | Result |
|---|---|
| `/board` | Full board, 5 rows per state |
| `/board <state>` | Single column (5 rows) for that state |
| `/board <state> <N>` | Single column, N rows |
| `/board --project <P>` | Filter all displayed rows to project `<P>` |
| `/board --all` | No per-state cap (show every row) |
| `/board --list` | Vertical list view (state headers + bullets) instead of the kanban table |

`<state>` is one of: `planning`, `in-progress`, `testing`, `done`. (`backlog` still renders the
legacy pre-migration column, so you can see what needs migrating.)

Combine flags freely, e.g.:
- `/board done 15` — last 15 Done stories
- `/board --project P0` — full board, P0 stories only
- `/board in-progress --project P0` — In Progress column for P0 stories
- `/board --all` — bypass the 5-row cap when you want the whole thing

## Steps

### 1. Parse args from the user's message

Build the arg list for the script. Order doesn't matter — the script accepts state, count, `--project <P>`, `--all` in any sequence.

### 2. Invoke the render script

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-render.sh" [args...]
```

### 3. Surface the output

Print the script's stdout **verbatim** as the response — it is a markdown artifact; let it render directly. Do NOT add commentary, summaries, or annotations, and **do NOT reflow the kanban table into a list**: the full-board cells are already compact (ID + title) so the table fits, and `/board --list` is the only list form. The board IS the message.

## Errors

If the board doesn't exist yet, the script prints a hint to run `/draft` first. Pass that message through unchanged.

If the user passes an unknown arg, the script exits non-zero with `Unknown arg: <x>`. Surface the message and stop — don't retry.
