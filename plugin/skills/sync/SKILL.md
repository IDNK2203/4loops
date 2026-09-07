---
name: sync
description: The intra-cadence loop — invoke once, then just talk. Between your daily/weekly rituals, this is where you move the board by speaking: new tasks, state moves, priority changes, retirements. It opens on a priority-annotated board (where you are vs today's/this week's focus), then turns plain language into real rail operations. User-invoked only; the invocation is your standing okay for the session.
allowed-tools: Bash, AskUserQuestion
disable-model-invocation: true
user-invocable: true
argument-hint: "[optional: say what changed, or just open it and talk]"
---

`/sync` is the **conversational, intra-cadence** surface — the high-traffic space *between*
morning orientations (`/week`). You open it once and then **talk**: "new task: add rate limiting, high
priority", "the metrics endpoint is done", "bump auth to the top", "drop the pricing copy". It
maps each thing you say to a real board operation and **runs it on the rails** — you never type
`/capture` / `/manage` / `/prioritize` or remember a state command. The loops (capture · check ·
prioritize) are the engine; talking is the whole interface.

**Invoking `/sync` is your standing consent for this working session.** Once it's open, treat the
user's subsequent messages as intra-cadence operations and move the pieces — no per-action
re-confirmation (the board still can't move itself; only this invoked session moves it). When the
user shifts to other work, you simply stop; everything you did is already on the board.

## The contract — operate, never simulate (read first, every time)

This is non-negotiable. The product dies the moment the board lies.

1. **Every change goes through a `vt-*.sh` rail script.** Never describe a move you didn't run.
   You *cannot* hand-edit `board.md` / `current-priorities.md` — the gate blocks it — so the rail
   is the only real path. If you didn't run a script, nothing happened.
2. **Re-render as proof.** After each operation, re-render (the annotated board or the changed
   column) from disk and show it. The rendered file is the source of truth, not your summary. If
   your words and the render disagree, the render wins — fix it.
3. **Never invent an ID.** Match what the user says to a real story on the board (you printed it in
   step 1). If two stories could match, ask ONE tight question. If none match, say so — don't guess.

## Step 1 — Orient (print ONCE, the priority-annotated board)

Require config first:

```bash
[ -f .4loops/config ] && echo CONFIGURED || echo UNCONFIGURED
```

If `UNCONFIGURED`, stop: **"No 4loops board here yet — run `/4loops:configure` first."**

Otherwise, open on **where the user stands relative to their priorities** — not the raw board:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-render.sh" --priorities   # ★ focus · ! overdue · ⏳ due-soon · ◆ modeling
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-drift.sh"                  # overdue · due-soon · caps · stale
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-today.sh" --current        # today's focus line
```

Print this **once**. Lead the eye with **★ focus, then ! overdue / ⏳ due-soon** — that's "where am
I vs my day/week." Then a single open prompt — **"What's changed?"** — and listen. (If the user
already said what changed in their invocation args, skip straight to step 2 and act on it.)

## Step 2 — Converse: turn each utterance into one rail operation

For each thing the user says, classify the intent and run the matching rail. Then **re-render proof**.
(Prefix every command with `"${CLAUDE_PLUGIN_ROOT}/scripts/`.)

| They say… | Intent | Rail |
| --- | --- | --- |
| "new task: X", "I need to Y", "add Z" | **capture** | `printf '…\t…\n' \| vt-store-capture.sh` (+ `vt-store-expire.sh --activate-only`) — detached `.4loops/store/`. The board has no intake column |
| "start X", "X is in progress / testing / done" | **move state** | `vt-transition.sh <id> <planning\|in-progress\|testing\|done>` |
| "that title is wrong", "X and Y are the same thing", "that row shouldn't exist" | **task CRUD** | `vt-edit.sh <id> --title/--why/--context …` · `vt-merge.sh <from> <into>` · `vt-remove.sh <id>` |
| "focus on X", "bump X to the top", "add X to today" | **prioritize** | `vt-priority.sh add <id\|"text"…>` (or `set …` to replace). Free text lands in the store (`lever=today`) and straight onto Today — and onto the Week if it wasn't there (today ⊆ week; today 2–3, week ≤5 — a refusal carries the arithmetic). `week add …` for the week's list |
| "take X off today", "deprioritize X" | **prioritize** | `vt-priority.sh drop <id…>` (a CAP goes back to `lever=later` — logged, not deleted) |
| "X is done" (a CAP / priority item, not a board story) | **check the box** | `vt-priority.sh done <id…>` — `[x]` on today + week; a board story going Done shows `[x]` on its own via `vt-transition.sh` |
| "what did we do yesterday?", "where was I?" | **orient (read)** | `vt-today.sh --yesterday` · `vt-week.sh --print` (the checkbox file) · `vt-today.sh --orient` (never gated) |
| "drop X", "kill X", "X is dead", "X superseded by Y" | **retire** | `vt-transition.sh <id> abandoned` · `vt-transition.sh <id> superseded --by <id2>` |

After running, re-render proof and keep it tight:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-render.sh" --priorities    # or a single column, e.g. `… in-progress`
```

**Capture defaults** (mirror how the operator actually talks):
- **type** = `dev` unless the wording is exploratory ("spike", "figure out", "decide", "explore") → `modeling`.
- **deadline** = set it when stated or implied ("by Friday", "before the demo") as `YYYY-MM-DD`; else none.
- **priority** = only if the user states it ("high", "top", "today"). New work lands in the **detached store** (`.4loops/store/`, state `captured`→`active`);
  don't auto-prioritize and don't draft onto the board — capture and prioritize are separate acts, and priority stays the user's.
- **project** = the sole project by default; infer from context when several; ask only if truly ambiguous.

**Batch it.** If the user rattles off several things at once ("metrics is done, start the pricing
copy, and add rate limiting for Friday"), do them in order, each on its rail, then **one** re-render
at the end — not five.

## Step 3 — Stay in the loop

Keep operating on follow-up messages in the same session (the invocation already consented). Don't
re-print the full board each turn — re-render only what changed (a column, or the annotated board
when several things moved). When the user moves on to actual execution / other work, stop cleanly —
the board already reflects everything, because every change rode a rail.

## Notes

- This never lifts the **gate** — that's `/week`'s job (the one-shot orientation: look-back → week from
  the store → today's 2–3). `/sync` is the lightweight in-between; if priorities are stale, nudge the
  user toward `/week`, but don't block their flow.
- For the deliberate orientation pass, that's `/week` (and `/today` only for a mid-day re-pull from the
  week). `/sync` is the talk-don't-click path in between. Same rails underneath.
- The rails underneath (`vt-store-capture.sh` for new work, `vt-transition.sh`, `vt-priority.sh`; `vt-draft.sh` only for intentional board drafts) are the same ones the
  rituals use; talking here just drives them conversationally instead of via checkboxes.
- The board is **active state only** — Planning → In Progress → Testing → Done. There is no Backlog
  target: uncommitted work stays in the store, and dead work retires via `abandoned` / `superseded`.
  Lifecycle beyond state moves (edit · merge · remove · Done flush · key rename) lives in `/manage`.
