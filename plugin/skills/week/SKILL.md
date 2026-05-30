---
name: week
description: Weekly board-reconciliation ritual — review the week (Done already auto-archived by the rollover), reconcile what remains, then set this week's 3–5 anchor focus. Carry-forward defaults from last week's still-alive focus. Writes the Week section of current-priorities.md. Run first on a new ISO week, before /today.
allowed-tools: Bash, AskUserQuestion
user-invocable: true
---

`/week` is the weekly **board-reconciliation ritual** (run first on a new ISO week, before `/today`). On the first session of a new ISO week the sentinel has already auto-fired the weekly rollover (Done → `archive/closed`, abandoned → `archive/abandoned`). Your job is to reconcile what remains and set the week's anchor focus.

## Usage

`/week` — interactive weekly reconciliation.

## Steps

### 1. Orient

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-render.sh"
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-drift.sh"
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-week.sh" --default
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-week.sh" --current
```

Save `--default` output as `SUGGESTED_FOCUS` (last week's focus still in planning/in-progress/testing).

### 2. Reconcile — batch multi-select (week lens)

Same board-state selector as `/today`. Build ONE `AskUserQuestion` with up to three `multiSelect: true` questions (label = `ID — title`); omit empty ones:

- **Q1 — "Which are now Done?"** options = **Testing + In Progress** → `"${CLAUDE_PLUGIN_ROOT}/scripts/vt-transition.sh" <id> done`.
- **Q2 — "Commit to this week from Backlog?"** options = **Backlog** → `"${CLAUDE_PLUGIN_ROOT}/scripts/vt-transition.sh" <id> planning` (scoped for the week; `/today` starts the day's subset).
- **Q3 — "Stale items to drop/park?"** options = stale stories from `vt-drift.sh` → `"${CLAUDE_PLUGIN_ROOT}/scripts/vt-transition.sh" <id> backlog`.

Loop the transition script over each selected ID, then re-render. The weekly rollover already archived Done + abandoned at session start — confirm nothing important got swept (archive is append-only under `.vibe-table/archive/`, reversible).

### 3. Set week focus (3–5 anchors)

AskUserQuestion (single-select): Keep [SUGGESTED_FOCUS] / Edit / Skip. Week scope is broader than day — cap 3–5. Sanity-check IDs against the board.

### 4. Write + show

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-week.sh" <ID1> ... <IDn>
cat .vibe-table/current-priorities.md
```

Preserves the Today section, refreshes activity slices, arms the rail. Then run `/today` to pick the day's subset.

## Skip path

Skip at step 3 → don't write. The week gate stays active until set; the sentinel re-prompts on the next session crossing the ISO-week boundary.

## Relationship to /today

`/week` sets the week's 3–5 anchors; `/today` selects the day's 1–3 from them. Set week first, refine daily.
