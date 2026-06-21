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

### 0. Require configuration

This skill reconciles a **configured** board — it must not create a bare one. Check first:

```bash
[ -f .4loops/config ] && echo CONFIGURED || echo UNCONFIGURED
```

If `UNCONFIGURED`, stop here and tell the user: **"No 4loops board is configured in this directory yet — run `/4loops:configure` first to set up your projects, gates, and focus."** Do not run the steps below.

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

### 2. Reconcile the board — granular forward transitions (state moves HERE)

The heart of the ritual: make the board honest *before* setting focus. Build ONE `AskUserQuestion` with up to **four** `multiSelect: true` groups — each one a single forward step along the flow `backlog → in-progress → testing → done`, plus a park escape. Omit any group whose source set is empty. Label every option `ID — title`.

1. **"Starting today?"** — options = **Backlog** → `"${CLAUDE_PLUGIN_ROOT}/scripts/vt-transition.sh" <id> in-progress`
2. **"Moved to testing?"** — options = **In Progress** → `"${CLAUDE_PLUGIN_ROOT}/scripts/vt-transition.sh" <id> testing`
3. **"Now done?"** — options = **In Progress + Testing** → `"${CLAUDE_PLUGIN_ROOT}/scripts/vt-transition.sh" <id> done`
4. **"Park (stale)?"** — options = stale candidates from `vt-drift.sh` → `"${CLAUDE_PLUGIN_ROOT}/scripts/vt-transition.sh" <id> backlog`

Each story belongs in at most one group. Apply the selected transitions in flow order (starting → testing → done → park), looping the script over each ID, then re-render the board. Anything unselected stays put. If all four source sets are empty, skip reconciliation silently — don't manufacture churn. (Brand-new item → `/4loops:draft`.)

Four groups is the `AskUserQuestion` max, so reconcile (here) and focus-set (step 3) stay **two** separate calls. Each question also needs **≥2 options**: if a group's source set has a single story, add a `None — leave as is` option so the call is valid; treat selecting it as a no-op.

### 3. Set today's focus (the byproduct)

AskUserQuestion (single-select):

- "Keep: [SUGGESTED_FOCUS]" — accept the carry-forward
- "Edit" — provide a custom 1–3 list (free-text via "Other")
- "Skip" — leave Today unchanged (gate stays active; sentinel/guard re-prompt)

For Edit, collect a space-separated ID list (cap 1–3; confirm if more). Sanity-check IDs against the board.

### 4. Write + show

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-today.sh" <ID1> <ID2> ...
cat .4loops/current-priorities.md
```

The script preserves the Week section, refreshes activity slices, **arms the rail** (first run), and **records this session as gate-cleared** when both today and week are fresh. The file IS the message — no extra commentary.

## Skip path

If the user Skips at step 3, do NOT call the write script. The focus gate stays active; the next product-surface write (or next session) re-prompts. Any reconciliation transitions you applied in step 2 still stand.

## Errors

Underlying scripts create `.4loops/` on first use. IDs aren't validated by the write script — filter in step 3.
