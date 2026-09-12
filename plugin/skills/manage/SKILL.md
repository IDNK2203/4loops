---
name: manage
description: State + lifecycle escape — move stories across the active board (start / testing / done), edit·merge·remove a task, flush Done to the archive, retire dead work (abandon / supersede), and rename a project key. A hidden power-user hatch; the normal way to move state is to just say it in /sync. Never captures and never sets priority.
allowed-tools: Bash, AskUserQuestion
disable-model-invocation: true
user-invocable: true
argument-hint: "[<id> <state> | <id> abandoned | <id> superseded --by <id2> | edit <id> … | merge <a> <b> | remove <id> | flush | key rename <old> <new>]"
---

`/manage` is a **thin escape** for working the board by hand. It is **not the main path** — between
rituals you just say what moved in `/sync` and it transitions for you. This exists for the rare
direct move and for the lifecycle operations `/sync` doesn't cover.

The board is the **active pipeline** — Planning → In Progress → Testing → Done — and nothing else.
There is **no Backlog column and no intake here**: new work goes to the detached store (`/capture`,
or just say it in `/sync`), and commitment happens in `/week`. `/manage` never captures and never
sets focus; it moves committed work through state and manages its lifecycle.

User-invoked only (`disable-model-invocation: true`) — the agent can't fire it on its own.

## Step 0 — Require configuration

```bash
[ -f .4loops/config ] && echo CONFIGURED || echo UNCONFIGURED
```

If `UNCONFIGURED`, stop: **"No 4loops board here yet — run `/4loops:configure` first."**

## Usage

| Form | What it does |
|---|---|
| `/manage <id> <planning\|in-progress\|testing\|done>` | move a story one (or more) steps |
| `/manage <id> abandoned` | retire as dropped → `archive/<month>/abandoned.md` |
| `/manage <id> superseded --by <id2>` | retire as replaced |
| `/manage edit <id> …` | reword title · why · context (also type · due · branch) |
| `/manage merge <from> <into>` | fold a duplicate into the survivor |
| `/manage remove <id>` | drop a mis-captured row → `archive/<month>/removed.md` |
| `/manage flush` | archive Done rows past their dwell |
| `/manage key rename <old> <new>` | rename a project key across the workspace |
| `/manage` (bare) | print the board, then a structured pick of what moved |

## Steps

If the user named an operation, apply it directly (match the id to a real story first — never invent
one), then re-render as proof. Prefix every command with `"${CLAUDE_PLUGIN_ROOT}/scripts/`.

```bash
vt-transition.sh <id> <planning|in-progress|testing|done>
vt-transition.sh <id> abandoned
vt-transition.sh <id> superseded --by <id2>

vt-edit.sh <id> --title "…" --why "…" --context "…"     # also --type --due --branch --clear <field>
vt-merge.sh <from-id> <into-id>                          # survivor keeps its column + the tighter deadline
vt-remove.sh <id> --reason "…"                           # mis-capture, not a real abandon

vt-flush.sh --dry-run                                    # what Done would archive (dwell, default 7d)
vt-flush.sh                                              # do it
vt-flush.sh --restore <id> --to <state>                  # put a row back — every exit is reversible

vt-key.sh list
vt-key.sh rename <old> <new> --dry-run                   # then without --dry-run

vt-render.sh --priorities                                # proof — always finish here
```

Otherwise print the board and offer ONE `AskUserQuestion` with forward-step groups (each story in at
most one). This is a **state pass only** — it never sets today/the week and never lifts the gate
(that is `/week`'s one shot, and `/today` is only a mid-day re-pull from the week):

1. **"Starting?"** Planning → `in-progress`
2. **"Moved to testing?"** In Progress → `testing`
3. **"Now done?"** In Progress + Testing → `done`
4. **"Retire — abandon / superseded / remove?"** stale/overdue → `abandoned` · `superseded --by <id2>` · `remove`

Apply in flow order, then re-render once as proof. Retired stories leave the grid into
`archive/<month>/` (append-only, reversible via `vt-flush.sh --restore`).

## Done is short-lived

Done is "what I just finished", not a history dump. `vt-flush.sh` archives Done rows that have sat
past the dwell — default 7 days, override with `--dwell N`, `VT_DONE_DWELL_DAYS`, or a
`done-dwell: N` line in `.4loops/config`; `--all` flushes the whole column now. The weekly rollover
does the same sweep automatically at the ISO-week turn, so a flush here is the **mid-week** move
when Done has grown noisy. `--restore <id>` puts a row back; the archive record stays either way.

## Migrating an old board

A board written before v2.5 still carries a Backlog column. It is not intake any more, so move
those cells off it with a script — **never** by editing `board.md`:

```bash
vt-migrate-backlog.sh --dry-run            # what would move
vt-migrate-backlog.sh                      # → store, lever `later` (the default)
vt-migrate-backlog.sh --to planning --only <id>   # for work already committed
```

The column disappears once it is empty, and the board re-renders in its four active states.

## Notes

- **Operate, never simulate.** Every change runs a `vt-*.sh` rail and re-renders from disk; the
  board file is the proof. You cannot hand-edit `board.md` — the gate blocks it.
- `/manage` does **not** lift the daily/weekly gate — that's `/week`. It only works the board.
- `backlog` is not a valid transition target any more. Park uncommitted work in the store; retire
  dead work with `abandoned`.
