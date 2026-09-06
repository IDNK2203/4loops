---
name: today
description: Daily orientation — continue yesterday (carry-forward), pull from the store (urgent / today levers), see how today meets the week's anchors, and set today's 1–3 in the living priorities doc. Free text lands as a store item on the spot. Board is a state check at the end, not the planning pen. Writes the Today stamp, which lifts the gate for the day.
allowed-tools: Bash, AskUserQuestion
disable-model-invocation: true
user-invocable: true
argument-hint: "[optional: IDs or free-text items to set as today's focus directly]"
---

`/today` is the daily **orientation**. The living priorities doc (`current-priorities.md` — Today + Week) is the **main surface**: you face yesterday's still-alive focus, pull what the store is holding for today, check the week's anchors, and commit today's 1–3. **No board reconciliation ritual** — the board is a *state check* you glance at afterwards, and state only moves when work actually moved. Running it writes today's stamp, which lifts the gate for the day.

## Surfaces

| Surface | Role here |
| --- | --- |
| **`current-priorities.md`** (Today + Week) | THE surface — carry-forward + store pull + direct adds, stamped daily |
| **Store** (`.4loops/store/`, levers `urgent\|today\|later`) | Where suggestions come from; free text you add lands here with `lever=today` |
| **Board** | State check only (`--priorities` overlay). Never printed first; never the source of "what to do today" |

## Steps

### 0. Require configuration — and that the week ran first

Honor `VT_DIR` (rails sandbox) — default `./.4loops`:

```bash
VT="${VT_DIR:-./.4loops}"
[ -f "$VT/config" ] && echo CONFIGURED || echo UNCONFIGURED   # default path: .4loops/config
source "${CLAUDE_PLUGIN_ROOT}/scripts/vt-priorities-lib.sh"
week_stamp_current "$(read_week_stamp)" && echo WEEK_OK || echo WEEK_STALE
```

- `UNCONFIGURED` → stop: **"No 4loops board is configured here yet — run `/4loops:configure` first."**
- `WEEK_STALE` → stop: **"It's a new week — run `/4loops:week` first; its anchors flow into today."**
  Hard rule: on a fresh ISO week the week orientation comes before the day (the rail enforces it too — `vt-today.sh` refuses to set focus until the week is current).

### 1. Orient — print the orientation block ONCE (no board dump)

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-today.sh" --orient    # yesterday carry-forward · store pull · week anchors · SUGGESTED_FOCUS
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-drift.sh"             # OVERDUE · DUE-SOON (board deadlines) — lead with these
```

Print it once. Read it top-down with the user:

1. **Carry-forward** — yesterday's focus that is still alive is the default. Anything under *dropped* already got an honest ending (done / retired / expired) — say so in one line, don't re-litigate.
2. **Store pull** — `urgent` items lead, then `today`. `later` is only a count; the user names one if they want it.
3. **Week anchors** — the `← in suggested today` marks show how today meets the week. If no anchor is in today, say so plainly — that's the signal to reconsider, not a failure.
4. **`SUGGESTED_FOCUS`** — the proposed 1–3 (carry first, then urgent, then today). Bias overdue / due-soon to the front.

If the user passed items in `$ARGUMENTS`, skip the question and go straight to step 2 with those.

### 2. Set today's focus (the act)

ONE `AskUserQuestion` (single-select): **Keep `[SUGGESTED_FOCUS]`** / **Edit** (free text via Other — IDs and/or new items in plain words, e.g. `P0-019 CAP-004 "Fix the login bug"`) / **Skip**. Keep it to 1–3; if the suggestion is longer, propose the trim. Then:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-today.sh" <ID|CAP-ID|"free text"> ...
cat "${VT_DIR:-./.4loops}/current-priorities.md"
```

- Board IDs (`P0-12`) and store IDs (`CAP-003`) pass through. **Free text becomes a store item on the spot** (`lever=today`, state active) and goes straight into today — no `/capture` → `/prioritize` detour.
- Store levers follow the day: a CAP you committed becomes `lever=today`; a `today` item you left out goes back to `later` (logged in `store/transitions.log` — history, not deletion).
- `board.md` is **not** written by this step.
- Preserves the Week section, refreshes slices, appends to `priorities.log`, **arms the rail**, and records this session cleared when today + week are fresh. The file IS the message.

### 3. Board — state check (optional, light)

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-render.sh" --priorities   # ★ today's focus · ! overdue · ⏳ due-soon · ◆ modeling
```

Look only at **today's focus stories** on the board. Offer state moves ONLY where the state obviously lags the work — e.g. a focus story still in Backlog/Planning that the user is starting now (`vt-transition.sh <id> in-progress`), or one they say is finished (`… done`). One small `AskUserQuestion` at most, skippable, options labeled `ID — title`. Never walk the whole board; never move state "to look busy". CAP items have no board state — they live in the store until they become committed work.

## Notes

- Skip at step 2 → don't write; the gate stays active and re-prompts. Nothing else changed.
- Mid-day, don't re-run this: use `/4loops:prioritize add "<item>"` (or just say it in `/4loops:sync`) to add to today/week directly.
- "What did we do yesterday?" → `vt-today.sh --yesterday` (focus + that day's board and store transitions). History lives in `priorities.log` + the two `transitions.log`s — not in per-day files.
- Priority stays **yours** — propose, you decide. Mutations ride the rails; never hand-edit `board.md` / `current-priorities.md`.
