---
name: week
description: The one-shot orientation — print the priorities file (checkboxes), a light look-back (last week on a new week; since yesterday on a follow-up day), set the week from the store (≤5 open), pick today's 2–3 from that week, gate clears. Run it every morning; on a new week it is the whole ritual, on Tue+ it is a short beat. No board-state moves.
allowed-tools: Bash, AskUserQuestion
disable-model-invocation: true
user-invocable: true
argument-hint: "[optional: week items … --today <2–3 of them>]"
---

`/week` is the **one-shot orientation**. One print, two picks, done. The priorities file (`current-priorities.md` — Today + Week as `[ ]` / `[x]` checkboxes) is the main surface; the **store** is where week picks come from; the **board** is a separate state check and is **not** part of this flow. There is no Keep / Edit / Skip menu and no board shuffle: you look back, choose the week, choose today, and the gate clears.

**Monday (new week):** print file → look back at last week (done vs carried) → set the week from the store (cap 5) → pick today's 2–3 from that week → gate clears.
**Tue+ (follow-up day):** print file → look back since yesterday → refresh/add to the week only if needed (cap) → pull today's 2–3 from the current week → gate clears.

**Invariant:** every `/week` run starts by printing `vt-week.sh --orient` stdout verbatim — priorities file first. No argument, no time of day, and no follow-up mode skips that print.

Rules the rails enforce: week ≤ **5 open** (2 already on → at most 3 new); today **2–3**, **only from the week**; a today pick that isn't on the week is **promoted onto it** (no orphan today items). Free text lands in the store on the spot.

## Step 0 — Require configuration

Honor `VT_DIR` (rails sandbox) — default `./.4loops`:

```bash
VT="${VT_DIR:-./.4loops}"
[ -f "$VT/config" ] && echo CONFIGURED || echo UNCONFIGURED   # default path: .4loops/config
```

If `UNCONFIGURED`, stop: **"No 4loops board is configured here yet — run `/4loops:configure` first."**

## Step 1 — Orient (print ONCE, ALWAYS — never skipped, never summarized)

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-week.sh" --orient
```

Print it once, verbatim — it already contains, in order: the **priorities file** (checkboxes), the **look-back** (`MODE: new-week` → last week's `[x]` done vs `[ ]` carried, plus what moved; `MODE: follow-up` → since yesterday only), the **week pick list** from the store (urgent · today · due this week · later; board work in flight is also pickable) with the cap arithmetic, and the **today** carry. Read the last lines:

- `WEEK_ACTIVE` — open items already on the week · `WEEK_CAP_LEFT` — how many new fit
- `WEEK_SUGGESTED` — carry + store pull, cut to the cap
- `TODAY_SUGGESTED` — 2–3 from that week (today carry first, then urgent, then in-progress)

No drift dump, no board render, no prose recap of last week. The look-back is a glance, not a task-state pass — never offer to move a story's state here.

**This step is unconditional.** Run `--orient` and paste its stdout verbatim *before* any `AskUserQuestion`, and before any write — including when the user already passed items in `$ARGUMENTS`, when you ran `/week` earlier today, and on a follow-up (Tue+) day. The rail is read-only and never gated, so there is never a reason not to run it. Do not paraphrase it, do not summarize it, do not print only the machine lines, and do not substitute `--print`: the `── Priorities ──` block with its `[ ]` / `[x]` checkboxes is the whole point of the command, and the user must see it. If the print is missing, the ritual did not happen.

`$ARGUMENTS` only skips **Step 2** (the two questions) — never Step 1. With items in `$ARGUMENTS`: print Step 1, then go straight to Step 3 with those (`… --today …` picks today too).

## Step 2 — Two picks (one `AskUserQuestion` each)

**Pick the week** (`multiSelect: true`, header "Week"): options = `WEEK_SUGGESTED` first (pre-labelled `carried` / `urgent` / `due`), then the rest of the store pull, then board work in flight; each labelled `ID — title`. Say the cap in the question text: *"Up to N new — WEEK_CAP_LEFT."* On a follow-up day where `WEEK_ACTIVE` already covers the week, ask only *"Add anything to the week? (up to N)"* and accept "nothing".

**Pick today** (`multiSelect: true`, header "Today"): options = the chosen week items, `TODAY_SUGGESTED` first, labelled `ID — title`. Ask for **2–3**. A pick that isn't on the week is fine — the rail promotes it onto the week (cap permitting).

New items in plain words go in via **Other** — quote each as one argument in Step 3; they land in the store (`lever=later` for week picks, `lever=today` for today picks).

## Step 3 — Commit (one call) and show the file

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-week.sh" set <week items…> --today <2–3 of them…>
```

- Follow-up day, nothing new for the week: `vt-week.sh today <2–3 items>` (or `vt-week.sh add <new…> --today <…>` when adding).
- The rail writes both sections with fresh stamps in **one write**, logs to `priorities.log`, sets store levers (today picks → `lever=today`, a `today` CAP left off → `later`), arms the rail, and **clears the gate**. `board.md` is never written.
- Cap or size refusals (exit 4) come back with the exact arithmetic — trim and re-run; do not work around them.

The command already prints the file. **The file is the message** — no summary paragraph.

## Notes

- Gate clears after this flow. `/4loops:today` is **not** required; it exists only for a mid-day re-pull from the week.
- Mid-day changes: `/4loops:prioritize add "<item>"` (today; promotes onto the week) · `/4loops:prioritize week add …` · `/4loops:prioritize done <ID>` checks the box.
- Board is a separate state check (`/4loops:board`, `/4loops:sync`). A story going Done on the board shows as `[x]` here automatically. The weekly rollover flushes Done into `archive/<month>/closed.md` at the ISO-week turn — mid-week, `/4loops:manage flush` does the same sweep on demand.
- Priority is yours — propose, you decide. Mutations ride the rails; never hand-edit `current-priorities.md`.
- **Read-only rails are never gated.** `vt-week.sh --orient` / `--print` (and `vt-today.sh --orient`, `vt-render.sh`, `vt-drift.sh`, `vt-store-list.sh`) need no capability and are not touched by the orientation gate. If you are blocked on something else, you can still run these — never tell the user you can't orient or show the board.
- **What a stale gate actually blocks:** writes to the configured **gated product surfaces** (the codebase), and nothing else. The board is not frozen by stale orientation — board rails are capability-gated instead, so a `/4loops:sync` or `/4loops:manage` session can still move state before `/week` has run.
