---
name: manage
description: State-move escape — move stories across the board (start / testing / done / park) and retire dead work (abandon / supersede), directly. A hidden power-user hatch; the normal way to move state is to just say it in /nav. Never captures and never sets priority — state only.
allowed-tools: Bash, AskUserQuestion
disable-model-invocation: true
user-invocable: true
argument-hint: "[<id> <state> | <id> abandoned | <id> superseded --by <id2>]"
---

`/manage` is a **thin, state-only escape** for moving stories across the board by hand. It is **not
the main path** — between rituals you just say what moved in `/nav` and it transitions for you. This
exists for the rare direct move. It only changes a story's **state**: it never captures new work
(that's `/capture` or `/nav`) and never sets focus (that's `/prioritize` or `/nav`).

User-invoked only (`disable-model-invocation: true`) — the agent can't fire it on its own.

## Step 0 — Require configuration

```bash
[ -f .4loops/config ] && echo CONFIGURED || echo UNCONFIGURED
```

If `UNCONFIGURED`, stop: **"No 4loops board here yet — run `/4loops:configure` first."**

## Usage

- `/manage <id> <in-progress|testing|done|backlog>` — move a story one (or more) steps.
- `/manage <id> abandoned` — retire as dropped.
- `/manage <id> superseded --by <id2>` — retire as replaced by another story.
- `/manage` (bare) — print the board, then a structured pick of what moved.

## Steps

If the user named an id + target, apply directly (match the id to a real story first — never invent one):

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-transition.sh" <id> <state>
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-transition.sh" <id> abandoned
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-transition.sh" <id> superseded --by <id2>
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-render.sh" --priorities          # proof
```

Otherwise print the board and offer ONE `AskUserQuestion` with forward-step groups (each story in at
most one), exactly like `/today`'s reconcile but **without** setting focus or lifting the gate:

1. **"Starting?"** Backlog → `in-progress`
2. **"Moved to testing?"** In Progress → `testing`
3. **"Now done?"** In Progress + Testing → `done`
4. **"Retire — park / abandon / superseded?"** stale/overdue → `backlog` · `abandoned` · `superseded --by <id2>`

Apply in flow order, then re-render once as proof. Retired stories leave the grid into
`archive/<month>/abandoned.md` (append-only, reversible).

## Notes

- **Operate, never simulate.** Every move runs a `vt-transition.sh` call and re-renders from disk;
  the board file is the proof. You cannot hand-edit `board.md` — the gate blocks it.
- `/manage` does **not** lift the daily/weekly gate — that's `/today` / `/week`. It only moves state.
