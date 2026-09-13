---
name: today
description: Mid-day pull-from-week — re-point today's 2–3 from the current week's items in the living priorities doc (checkboxes). NOT the orientation and NOT required to clear the gate — /week is the one-shot that does both. Use this only when the day changed mid-day.
allowed-tools: Bash, AskUserQuestion
disable-model-invocation: true
user-invocable: true
argument-hint: "[optional: 2–3 week items to set as today directly]"
---

`/today` is the **mid-day pull from the week**. The daily orientation (look-back → week → today → gate clears) is `/4loops:week`, one shot; you do **not** need this command to finish orientation. Reach for it when the day changed mid-day and you want to re-point today's 2–3 from the week's items.

Rules the rails enforce: today **2–3**, **only from the week**; a pick that isn't on the week is **promoted onto it** (week cap 5). Free text lands in the store (`lever=today`) and on both lists. Board is a separate state check — nothing here writes `board.md`.

## Surfaces

| Surface | Role here |
| --- | --- |
| **`current-priorities.md`** (Today + Week, `[ ]`/`[x]`) | THE surface — today is a subset of the week |
| **Store** (`.4loops/store/`, levers `urgent\|today\|later`) | Free text you add lands here with `lever=today` |
| **Board** | Not part of this — a story going Done shows as `[x]` here on its own |

## Steps

### 0. Require configuration — and a current week

Honor `VT_DIR` (rails sandbox) — default `./.4loops`:

```bash
VT="${VT_DIR:-./.4loops}"
[ -f "$VT/config" ] && echo CONFIGURED || echo UNCONFIGURED   # default path: .4loops/config
source "${CLAUDE_PLUGIN_ROOT}/scripts/vt-priorities-lib.sh"
week_stamp_current "$(read_week_stamp)" && echo WEEK_OK || echo WEEK_STALE
```

- `UNCONFIGURED` → stop: **"No 4loops board is configured here yet — run `/4loops:configure` first."**
- `WEEK_STALE` → stop: **"It's a new week — run `/4loops:week` (one shot: look back, set the week from the store, pick today's 2–3)."** The rail refuses too (`vt-today.sh` exits 3 on a stale week).

### 1. Orient — print ONCE, ALWAYS (no board dump)

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-today.sh" --orient    # the file · the week to pull from · TODAY_SUGGESTED
```

Print it once. It is the priorities file plus the week's open items and a `TODAY_SUGGESTED` line (today's open carry first, then urgent, then in-progress; max 3). No drift dump, no board render.

**This step is unconditional** — same rule as `/week`. Run `--orient` and paste its stdout verbatim before any `AskUserQuestion` and before any write, including when the user already passed items in `$ARGUMENTS`. The rail is read-only and never gated. Never paraphrase it and never print only `TODAY_SUGGESTED`: the checkbox file is the surface.

`$ARGUMENTS` only skips the **question** in Step 2 — never this print. With items in `$ARGUMENTS`: print Step 1, then run the Step 2 commit directly with those.

### 2. Pick today (ONE `AskUserQuestion`, `multiSelect: true`)

Options = the week's open items, `TODAY_SUGGESTED` first, labelled `ID — title`. Ask for **2–3**. New items in plain words via **Other** (quote each as one argument). Then:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-today.sh" <2–3 items…>
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-today.sh" --print
```

- Board IDs (`P0-12`) and store IDs (`CAP-003`) pass through; free text becomes a store item on the spot (`lever=today`) — no `/capture` detour.
- A pick not on the week is promoted onto the week (the week stamp is left as is); more than 3, or a promotion over the week cap, is refused with the exact arithmetic — trim and re-run.
- Store levers follow the day (committed CAP → `today`; a `today` CAP left off → `later`, logged). Appends to `priorities.log`, arms the rail, clears the gate when week + today are fresh. **The file is the message.**

## Notes

- Nothing selected → no write; nothing else changed.
- Add one item without re-picking: `/4loops:prioritize add "<item>"`. Check a box: `/4loops:prioritize done <ID>`.
- "What did we do yesterday?" → `vt-today.sh --yesterday` (last Today's checkboxes + that day's board and store transitions). History lives in `priorities.log` + the two `transitions.log`s.
- Priority stays **yours** — propose, you decide. Never hand-edit `board.md` / `current-priorities.md`.
- **Read-only rails are never gated.** `vt-today.sh --orient` / `--print` / `--current` / `--yesterday`, `vt-week.sh --orient`, `vt-render.sh`, `vt-drift.sh`, `vt-store-list.sh` need no capability and no fresh orientation. Run them freely to answer a question — do not claim you are blocked from looking.
- **A stale gate blocks the codebase, not the board.** Stale orientation stops writes to the gated product surfaces only; board moves ride a separate per-session capability.
