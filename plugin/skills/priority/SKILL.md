---
name: priority
description: The in-between reconciliation — when work lands between your /today and /week rituals, print what's changed and re-point: bump focus, nudge a state, capture urgent work. Lighter than /today, same see-then-pick model (no full walk, no chat).
allowed-tools: Bash, AskUserQuestion
user-invocable: true
---

`/priority` is the **in-between cadence** — for when reality shifts between `/today` and `/week`. Same model as the rituals: **print what's changed, then pick** — just lighter and faster (no full board walk). A new thing landed, a priority flipped, something's urgent: re-point focus and move on.

## Usage

- `/priority` — print what's shifted, then re-point (structured).
- `/priority add <id…>` / `set <id…>` — direct focus adjustment, no prompt.
- `/priority since` — just show what's landed since you last set focus.

## Steps

### 1. Print what shifted (ONCE)

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-priority.sh" since     # drafted/moved since the last Today stamp, not in focus
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-drift.sh"              # OVERDUE · DUE-SOON · caps · stale
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-today.sh" --current    # today's focus now
```

This is the lean view — not the whole board walk. Lead with overdue / due-soon.

### 2. Re-point — structured pick

If the user named IDs, apply directly. Otherwise ONE `AskUserQuestion`:
- **"Add to today's focus?"** (multiSelect) — options = the `since` candidates + any overdue/due-soon not yet focused → `vt-priority.sh add <id…>`.
- Need a clean swap instead? **set** replaces the focus: `vt-priority.sh set <id…>`.

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-priority.sh" add <id…>     # append (dedup) + freshen Today stamp
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-priority.sh" set <id…>     # replace focus
cat .4loops/current-priorities.md
```

Urgent NEW work → capture it first with `/4loops:arrange` or `vt-draft.sh … --type … --deadline …`, then add it. A state nudge → `vt-transition.sh <id> <state>`. Need to kill a story now (don't wait for the weekly prune)? Retire it: `vt-transition.sh <id> abandoned` or `… superseded --by <ID2>` — it leaves the grid into `archive/<month>/abandoned.md`. Keep it quick — this is the in-between, not the full walk.

`add`/`set` freshen the Today stamp (gate stays lifted) and re-arm/clear like `/today`.

## Notes

- Priority stays **yours** — given the drift, I propose what to bump; you decide. Mutations ride the rails.
- For the full daily/weekly walk use `/today` / `/week`; for pure capture use `/arrange`.
