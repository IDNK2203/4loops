---
name: today
description: Daily board reconciliation — talk through your day in plain language (what you finished, started, dropped, or need to add) and it moves the board, captures new work, and sets today's 1–3 focus. Surfaces overdue / due-soon. Writes the Today stamp, which lifts the focus gate for the day.
allowed-tools: Bash, AskUserQuestion
user-invocable: true
---

`/today` is your **daily board conversation**. You don't type `/start` or `/done` — you just tell me what happened ("shipped the gate fix, started the demo, drop the old idea, and add a new post due Friday") and I reconcile the board for you, then set today's focus.

**Invoking this command is your authorization to drive the rails.** You opened the door, so I apply the moves from what you tell me — I won't ask "are you sure?" on every step. The board can't move on its own; only this conversation (or `/week` · `/priority` · `/arrange`) moves it.

## Steps

### 0. Require configuration

```bash
[ -f .4loops/config ] && echo CONFIGURED || echo UNCONFIGURED
```

If `UNCONFIGURED`, stop and say: **"No 4loops board is configured here yet — run `/4loops:configure` first."**

### 1. Orient (board + drift + carry-forward)

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-render.sh"
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-drift.sh"          # caps · OVERDUE · DUE-SOON · stale · abandon-candidates
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-today.sh" --default   # carry-forward suggestion
```

Lead with anything **overdue or due-soon** — those are the off-plan signals that should shape today's focus.

### 2. Listen, then reconcile (this is where the board moves)

Take the user's plain-language account of their day. Map it to rail calls and **run them** — loop the scripts over each item, in flow order:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-transition.sh" <id> in-progress     # "started X"
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-transition.sh" <id> testing         # "X is in review"
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-transition.sh" <id> done            # "finished X"
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-transition.sh" <id> backlog         # "park X"
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-transition.sh" <id> abandoned       # "drop X" (or: superseded --by <id2>)
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-draft.sh" <P> "<title>" "<why>" "<doc>" --type <dev|modeling> --deadline <YYYY-MM-DD>   # "add X…"
```

When the user names new work, **capture it with its type and (if they gave one) a deadline** — deadlines are what let `/today` flag drift later. If something's ambiguous (which project? a date?), ask one tight question; otherwise just do it. Re-render after applying.

If the user only wants a recap, just summarize the board + drift and stop — reading never changes anything.

### 3. Set today's focus (the byproduct)

Propose 1–3 focus stories — carry-forward + anything overdue/due-soon first. Confirm or let the user edit (free-text). Then:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-today.sh" <ID1> <ID2> ...
cat .4loops/current-priorities.md
```

This freshens the Today stamp, **arms the rail**, and clears this session's gate when today+week are both fresh. The file IS the message.

## Notes

- Priority stays **yours** — I propose focus, you decide. I never reprioritize unprompted.
- All mutations ride the rails (which keep counts + the log in sync) — I never hand-edit `board.md`.
