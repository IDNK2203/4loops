---
name: today
description: Daily board reconciliation — print the board, then pick (structured) what moved: started / testing / done / park. New work and today's 1–3 focus fall out of it. Leads with overdue / due-soon. Writes the Today stamp, which lifts the focus gate for the day.
allowed-tools: Bash, AskUserQuestion
user-invocable: true
---

`/today` is the daily **board reconciliation**. You **see the board, then pick what changed** — you don't hand-type `/start`/`/done` per story, and you don't narrate it in prose. The board print is the context; structured selection is how you move things; today's focus falls out. Your selections apply directly (the pick *is* the confirmation). Running it writes today's stamp, which lifts the gate for the day.

## Steps

### 0. Require configuration

```bash
[ -f .4loops/config ] && echo CONFIGURED || echo UNCONFIGURED
```

If `UNCONFIGURED`, stop and say: **"No 4loops board is configured here yet — run `/4loops:configure` first."**

### 1. Orient — print the board ONCE (the context)

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-render.sh"
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-drift.sh"          # OVERDUE · DUE-SOON · caps · stale · abandon-candidates
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-today.sh" --default   # carry-forward → SUGGESTED_FOCUS
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-today.sh" --current
```

Print this once — it's the whole picture you reconcile against (if the user keeps `board.md` pinned, treat it as a refresh, don't re-dump). **Lead with anything overdue / due-soon** — those are the off-plan signals that should shape today.

### 2. Reconcile — structured multi-select (state moves HERE)

Build ONE `AskUserQuestion` with up to **four** `multiSelect: true` groups — each a single forward step along `backlog → in-progress → testing → done`, plus a park escape. Omit any group whose source set is empty. Label every option `ID — title` (mark ◆ modeling, and append `· due <date>`/`· OVERDUE` where it applies, so the deadline is visible at the pick):

1. **"Starting today?"** — **Backlog** → `vt-transition.sh <id> in-progress`
2. **"Moved to testing?"** — **In Progress** → `vt-transition.sh <id> testing`
3. **"Now done?"** — **In Progress + Testing** → `vt-transition.sh <id> done`
4. **"Park / drop (stale · overdue)?"** — stale + overdue candidates → `vt-transition.sh <id> backlog` (or `abandoned` if truly dropped)

(Prefix each with `"${CLAUDE_PLUGIN_ROOT}/scripts/`.) Each story in at most one group. Apply selections in flow order, then **re-render once**. Unselected stays put. All sets empty → skip silently, no churn. Four groups is the `AskUserQuestion` max, so reconcile and focus-set stay two calls; a single-story group needs a `None — leave as is` filler option (≥2 required), treated as a no-op.

**New work** isn't a checkbox — capture it with type + deadline via `/4loops:arrange` (a batch) or one `vt-draft.sh <P> "<title>" "<why>" "<doc>" --type <…> --deadline <YYYY-MM-DD>`. Don't force it into the multi-select.

### 3. Set today's focus (the byproduct)

`AskUserQuestion` (single-select): **Keep `[SUGGESTED_FOCUS]`** / **Edit** (free-text 1–3 via Other) / **Skip**. Bias the suggestion so **overdue / due-soon lead**. Sanity-check IDs against the board.

### 4. Write + show

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-today.sh" <ID1> <ID2> ...
cat .4loops/current-priorities.md
```

Preserves the Week section, refreshes slices, **arms the rail**, and records this session cleared when today+week are fresh. The file IS the message.

## Notes

- Skip at step 3 → don't write; the gate stays active and re-prompts. Step-2 moves still stand.
- Priority stays **yours** — propose, you decide. Mutations ride the rails; never hand-edit `board.md`.
