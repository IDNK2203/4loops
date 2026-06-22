---
name: archive
description: Retire a story off the board with an honest terminal outcome — abandoned (dropped) or superseded (replaced by another story). Pulls it off the active grid into archive/<month>/abandoned.md immediately, so dead work stops cluttering the board without waiting for the weekly rollover. Supports --by to link the superseding story and --backdate to record a past date.
allowed-tools: Bash, AskUserQuestion
user-invocable: true
---

`/archive` gives a story an honest ending. Not everything ships — some work is dropped, some is replaced. The board stays honest only if those outcomes are recorded, not left rotting in a column. This retires a story **now**, into the month's `abandoned.md` archive.

## Usage

- `/archive <ID>` — abandon a story (dropped).
- `/archive <ID> --superseded-by <ID2>` — mark it replaced by another story.
- `/archive <ID> --backdate YYYY-MM-DD` — record the retirement on a past date.

## Steps

### 1. Confirm the outcome

A retire is destructive to the board (the story leaves the grid). Confirm intent and the reason — AskUserQuestion: **Abandoned** (dropped) vs **Superseded** (replaced; ask which story replaces it). Never retire a story the user is actively focused on without explicit confirmation.

### 2. Apply

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-transition.sh" <ID> abandoned
# or, replaced by another story:
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-transition.sh" <ID> superseded --by <ID2>
# retroactively:
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-transition.sh" <ID> abandoned --backdate 2026-06-01
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-render.sh"
```

The story is appended to `archive/<month>/abandoned.md` (with the `superseded-by` link when given), removed from the grid, and the transition is logged. A story already in **Done** is refused — let the weekly rollover close it.

## Errors

A missing story or a Done story exits non-zero with a message — surface it and stop.
