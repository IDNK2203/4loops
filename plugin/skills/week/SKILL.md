---
name: week
description: Weekly orientation — the wider lens. See last week's anchors (still alive vs finished), committed board work, and the store pull (urgent / today / due-this-week); retire dead work honestly; set 3–5 anchors in the living priorities doc. Free text lands as a store item. Run FIRST on a new ISO week, before /today.
allowed-tools: Bash, AskUserQuestion
disable-model-invocation: true
user-invocable: true
argument-hint: "[optional: IDs or free-text items to set as this week's anchors directly]"
---

`/week` is the weekly **orientation** — the wider lens. Same shape as `/today`: **see where you stand, then set anchors** in `current-priorities.md`, no prose narration and no board-first ritual. Run it **first on a new ISO week, before `/today`** (once, at week start) — the sentinel has already auto-archived last week's Done + abandoned (rollover); you face what's still alive, prune honestly, set 3–5 anchors, and that context flows down into `/today`.

## Step 0 — Require configuration

Honor `VT_DIR` (rails sandbox) — default `./.4loops`:

```bash
VT="${VT_DIR:-./.4loops}"
[ -f "$VT/config" ] && echo CONFIGURED || echo UNCONFIGURED   # default path: .4loops/config
```

If `UNCONFIGURED`, stop: **"No 4loops board is configured here yet — run `/4loops:configure` first."**

## Step 1 — Orient (print ONCE)

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-week.sh" --orient   # last week alive/finished · committed board work · store pull · SUGGESTED_FOCUS
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-drift.sh"           # OVERDUE · DUE-SOON · stale · abandon-candidates
```

Print once; lead with overdue / due-soon. Read it with the user:

1. **Last week's anchors — still alive** is the carry. **Finished / retired / expired** already have their ending.
2. **Committed board work** (in-progress · testing) — what's actually moving.
3. **Store pull** — `urgent`, `today`, and `later` items due this week.
4. **`SUGGESTED_FOCUS`** — the proposed anchors, in that order. Confirm the rollover didn't sweep anything important (archive is append-only under `.4loops/archive/`, reversible).

If the user passed items in `$ARGUMENTS`, skip to step 3 with those.

## Step 2 — Prune honestly (only if there are candidates)

The weekly pass is where dead work gets an **honest ending** — history, not deletion. Build ONE `AskUserQuestion` (`multiSelect: true`, options labeled `ID — title`) from the *stale + overdue + abandon-candidates* that drift surfaced, plus last-week anchors that are still alive but the user says are dead. Omit the question entirely if there are none.

- board story: park → `vt-transition.sh <id> backlog` · abandon → `vt-transition.sh <id> abandoned` · replaced → `vt-transition.sh <id> superseded --by <ID2>` (one follow-up question for which)
- store item: park is the default (`lever=later` — nothing to do) · drop → `vt-store-expire.sh --force-expire <CAP> && vt-store-expire.sh --clear-id <CAP>`

(Prefix `"${CLAUDE_PLUGIN_ROOT}/scripts/`.) Never retire something in the current focus without explicit confirmation. This is the only board-state step in the ritual — and it's about endings, not "commit-this-week" shuffles.

## Step 3 — Set the week's anchors (3–5)

`AskUserQuestion` (single-select): **Keep `[SUGGESTED_FOCUS]`** / **Edit** (free text via Other — IDs and/or new items in plain words) / **Skip**. Cap 3–5; overdue / due-soon to the front. Then:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-week.sh" <ID|CAP-ID|"free text"> ...
cat "${VT_DIR:-./.4loops}/current-priorities.md"
```

- Free text becomes a store item on the spot (`lever=later` — week is **not** a lever; `/today` pulls it in when its day comes).
- Preserves the Today section, appends to `priorities.log`, arms the rail. `board.md` is not written.
- Then run `/4loops:today` to pick the day's 1–3 from these anchors.

## Notes

- `/week` sets 3–5 anchors; `/today` selects the day's subset and shows how it meets them. Week first, refine daily.
- Mid-week, add an anchor without re-running: `/4loops:prioritize week add "<item>"`.
- Skip at step 3 → don't write; the week gate stays active. Priority is yours; mutations ride the rails.
