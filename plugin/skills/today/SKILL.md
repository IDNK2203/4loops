---
name: today
description: Daily board-reconciliation ritual — walk the board (close finished, keep/drop stale, pull from backlog, add new), then set today's 1–3 focus stories as the byproduct. Carry-forward defaults from yesterday's still-alive focus. Writes the Today section of current-priorities.md and lifts the focus gate for the day.
allowed-tools: Bash, AskUserQuestion
user-invocable: true
---

`/today` is the daily **board-reconciliation ritual**. Managing the board IS setting priorities — you walk the board with the user, agree on reality, and today's focus falls out of it. Running it writes today's stamp, which lifts the PreToolUse focus gate for the day.

## Usage

`/today` — opens the interactive reconciliation.

## Steps

### 1. Orient: board + drift + carry-forward suggestion

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-render.sh"
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-drift.sh"
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-today.sh" --default
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-today.sh" --current
```

- `vt-render.sh` → the board.
- `vt-drift.sh` → caps hit, stale in-progress/testing, abandoned candidates (surface-only — **this is where you resolve them**).
- `--default` → carry-forward suggestion = yesterday's focus still in planning/in-progress/testing. Save as `SUGGESTED_FOCUS`.

### 2. Reconcile the board — batch multi-select (transitions happen HERE)

The heart of the ritual: make the board honest *before* setting focus, moving pieces in **batches** so it feels like a board-state selector. Build ONE `AskUserQuestion` with up to three `multiSelect: true` questions, each listing the relevant stories as options (label = `ID — title`). Omit a question whose source set is empty.

- **Q1 — "Which are now Done?"** options = current **Testing + In Progress** stories. Each selected → `"${CLAUDE_PLUGIN_ROOT}/scripts/vt-transition.sh" <id> done`.
- **Q2 — "Pull into focus from Backlog?"** options = **Backlog** stories. Each selected → `"${CLAUDE_PLUGIN_ROOT}/scripts/vt-transition.sh" <id> in-progress` (what you'll work on now).
- **Q3 — "Stale items to drop/park?"** options = the stale stories from `vt-drift.sh`. Each selected → `"${CLAUDE_PLUGIN_ROOT}/scripts/vt-transition.sh" <id> backlog` (parked).

Loop the transition script over each selected ID, then re-render the board. Anything not selected stays put. If all three source sets are empty, skip reconciliation silently — don't manufacture churn. (To add a brand-new item, use `/vt:draft`.)

### 3. Set today's focus (the byproduct)

AskUserQuestion (single-select):

- "Keep: [SUGGESTED_FOCUS]" — accept the carry-forward
- "Edit" — provide a custom 1–3 list (free-text via "Other")
- "Skip" — leave Today unchanged (gate stays active; sentinel/guard re-prompt)

For Edit, collect a space-separated ID list (cap 1–3; confirm if more). Sanity-check IDs against the board.

### 4. Write + show

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-today.sh" <ID1> <ID2> ...
cat .vibe-table/current-priorities.md
```

The script preserves the Week section, refreshes activity slices, **arms the rail** (first run), and **records this session as gate-cleared** when both today and week are fresh. The file IS the message — no extra commentary.

## Skip path

If the user Skips at step 3, do NOT call the write script. The focus gate stays active; the next product-surface write (or next session) re-prompts. Any reconciliation transitions you applied in step 2 still stand.

## Errors

Underlying scripts create `.vibe-table/` on first use. IDs aren't validated by the write script — filter in step 3.
