---
name: week
description: Weekly board reconciliation — talk through the week in plain language (what shipped, what carries over, what to drop or add) and it reconciles the board, captures new work, and sets this week's 3–5 anchors. Surfaces overdue / due-soon. Run first on a new ISO week, before /today.
allowed-tools: Bash, AskUserQuestion
user-invocable: true
---

`/week` is your **weekly board conversation** — the wider lens, run first on a new ISO week before `/today`. Same idea as `/today`: you describe the week in plain language and I reconcile the board and set the week's anchors. The sentinel has already auto-archived last week's Done + abandoned (rollover); you reconcile what remains.

**Invoking this command authorizes me to drive the rails** — I apply your reconciliation from the conversation, no per-step confirmation. Only this (or `/today` · `/priority` · `/arrange`) moves the board.

## Steps

### 0. Require configuration

```bash
[ -f .4loops/config ] && echo CONFIGURED || echo UNCONFIGURED
```

If `UNCONFIGURED`, stop: **"No 4loops board is configured here yet — run `/4loops:configure` first."**

### 1. Orient

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-render.sh"
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-drift.sh"           # caps · OVERDUE · DUE-SOON · stale · abandon
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-week.sh" --default  # carry-forward (last week's still-alive focus)
```

Confirm the rollover didn't sweep anything important (archive is append-only under `.4loops/archive/`, reversible). Lead with overdue / due-soon.

### 2. Listen, then reconcile (the board moves here)

Map the user's plain-language account of the week to rail calls and run them — finish, carry over, park, drop, or capture new work (with `--type` and `--deadline`):

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-transition.sh" <id> done|backlog|abandoned|...
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-draft.sh" <P> "<title>" "<why>" "<doc>" --type <…> --deadline <YYYY-MM-DD>
```

Capturing the *week's* new work with deadlines is what makes drift meaningful across the week. Re-render after. Recap-only request → just summarize and stop.

### 3. Set the week's anchors (3–5)

Propose anchors — carry-forward + anything overdue/due-soon first. Confirm or edit, then:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-week.sh" <ID1> ... <IDn>
cat .4loops/current-priorities.md
```

Preserves the Today section, refreshes slices, arms the rail. Then run `/today` to pick the day's 1–3 from these anchors.

## Notes

- `/week` sets the week's 3–5 anchors; `/today` selects the day's subset. Set week first, refine daily.
- Priority stays **yours** — I propose, you decide. Mutations ride the rails; I never hand-edit `board.md`.
