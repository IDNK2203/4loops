---
name: week
description: Weekly board reconciliation — print the board, then pick (structured) what's done, what to commit this week, what to drop; set 3–5 anchors. Leads with overdue / due-soon. Run FIRST on a new ISO week, before /today, so the week's context flows down to the day.
allowed-tools: Bash, AskUserQuestion
user-invocable: true
---

`/week` is the weekly **board reconciliation** — the wider lens. Same shape as `/today`: **see the board, pick what changed**, no prose narration. Run it **first on a new ISO week, before `/today`** (run it once, at week start) — the sentinel has already auto-archived last week's Done + abandoned (rollover); you reconcile what remains and set the week's anchors, and that context flows down into `/today`.

## Steps

### 0. Require configuration

```bash
[ -f .4loops/config ] && echo CONFIGURED || echo UNCONFIGURED
```

If `UNCONFIGURED`, stop: **"No 4loops board is configured here yet — run `/4loops:configure` first."**

### 1. Orient — print the board ONCE

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-render.sh"
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-drift.sh"           # OVERDUE · DUE-SOON · caps · stale · abandon
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-week.sh" --default  # last week's still-alive focus → SUGGESTED_FOCUS
```

Print once. Lead with overdue / due-soon. Confirm the rollover didn't sweep anything important (archive is append-only under `.4loops/archive/`, reversible). Because `/week` runs before `/today`, this is the one board print at week start — don't re-dump it in `/today` right after.

### 2. Reconcile — structured multi-select (week lens)

ONE `AskUserQuestion`, up to three `multiSelect: true` groups (label `ID — title`, mark ◆ / `· due <date>` / `· OVERDUE`); omit empty ones:

- **"Now done?"** — **Testing + In Progress** → `vt-transition.sh <id> done`
- **"Commit this week (from Backlog)?"** — **Backlog** → `vt-transition.sh <id> planning` (`/today` starts the day's subset)
- **"Drop / park (stale · overdue)?"** — stale + overdue → `vt-transition.sh <id> backlog` (or `abandoned`)

(Prefix `"${CLAUDE_PLUGIN_ROOT}/scripts/`.) Loop over selected IDs, then **re-render once**. New work → `/4loops:arrange` or `vt-draft.sh … --type … --deadline …`, not the multi-select.

### 3. Set the week's anchors (3–5)

`AskUserQuestion` (single-select): **Keep `[SUGGESTED_FOCUS]`** / **Edit** / **Skip**. Cap 3–5; bias overdue/due-soon to the front. Then:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-week.sh" <ID1> ... <IDn>
cat .4loops/current-priorities.md
```

Preserves the Today section, refreshes slices, arms the rail. Then run `/today` to pick the day's 1–3 from these anchors.

## Notes

- `/week` sets the week's 3–5 anchors; `/today` selects the day's subset. Week first, refine daily.
- Skip at step 3 → don't write; the week gate stays active. Priority is yours; mutations ride the rails.
