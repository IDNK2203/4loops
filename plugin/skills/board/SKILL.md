---
name: board
description: Render the Vibe Table board (kanban of stories by state). Default shows full board as a single horizontal 5-column table (Backlog | Planning | In Progress | Testing | Done), 5 rows per state, with compact cells (ID + title). Slicing flags filter to a single state (full why/context), a custom row cap, or a single project; `--list` gives a vertical view (kanban stays default). Use when the user wants to see the current state of their stories.
allowed-tools: Bash
user-invocable: true
---

Render the Vibe Table board for the current workspace.

## Usage

| Form | Result |
|---|---|
| `/board` | Full board, 5 rows per state |
| `/board <state>` | Single column (5 rows) for that state |
| `/board <state> <N>` | Single column, N rows |
| `/board --project <P>` | Filter all displayed rows to project `<P>` |
| `/board --all` | No per-state cap (show every row) |
| `/board --list` | Vertical list view (state headers + bullets) instead of the kanban table |

`<state>` is one of: `backlog`, `planning`, `in-progress`, `testing`, `done`.

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
