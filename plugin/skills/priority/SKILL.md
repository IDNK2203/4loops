---
name: priority
description: The in-between reconciliation — when something lands mid-day or mid-week between your /today and /week rituals, talk it through and re-point the board: move states, add new work, and adjust today's focus, without rerunning the full ritual. Surfaces what's changed and what's overdue / due-soon.
allowed-tools: Bash, AskUserQuestion
user-invocable: true
---

`/priority` is the **in-between cadence** — the quick conversation for when reality shifts between your `/today` and `/week` rituals. A new thing lands, a priority flips, something becomes urgent: you talk it through and I re-point the board and your focus, then move on. Lighter than `/today`, same authorization.

**Invoking it authorizes me to drive the rails** — I apply the changes from what you tell me. Only this (or `/today` · `/week` · `/arrange`) moves the board.

## Usage

- `/priority` — show what's changed since you last set focus, then re-point conversationally.
- `/priority add <id…>` / `set <id…>` — direct focus adjustment (no conversation needed).

## Steps

### 1. Surface what shifted

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-priority.sh" since      # drafted/moved since the last Today stamp, not in focus
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-drift.sh"               # OVERDUE · DUE-SOON · caps · stale
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-today.sh" --current     # today's focus now
```

### 2. Re-point (the board moves here)

From the user's plain-language update, apply the relevant rails — capture new work, nudge a state, and adjust focus:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-draft.sh" <P> "<title>" "<why>" "<doc>" --type <…> --deadline <YYYY-MM-DD>   # new urgent thing
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-transition.sh" <id> in-progress|testing|done|...                            # nudge a state
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-priority.sh" add <id…>      # append to today's focus (dedup), freshen stamp
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-priority.sh" set <id…>      # replace today's focus
cat .4loops/current-priorities.md
```

`add`/`set` freshen the Today stamp (so the gate stays lifted) and re-arm/clear like `/today` does. Keep it quick — this is the in-between, not the full walk.

## Notes

- Priority stays **yours** — I propose what to bump given the drift, you decide. Mutations ride the rails.
- For the full daily/weekly walk use `/today` / `/week`; for pure capture use `/arrange`.
