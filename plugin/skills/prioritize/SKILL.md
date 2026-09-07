---
name: prioritize
description: Thin, focus-only escape for mid-flight priority edits — add / set / drop items on today or the week, check a box done, and change store levers (urgent|today|later). Today adds promote onto the week (today ⊆ week); week ≤ 5 open; today 2–3. Free text lands in the store on the spot. Never drafts onto board Backlog.
allowed-tools: Bash, AskUserQuestion
disable-model-invocation: true
user-invocable: true
argument-hint: "[add|set|drop <ID|\"text\">… | done <ID>… | week add|set|drop … | lever <CAP-ID> <urgent|today|later> | since]"
---

`/prioritize` is the **thin, focus-only escape** between orientations: re-point today or the week **without re-running `/week`**, check boxes, adjust store levers. The living priorities doc (`current-priorities.md` — Today + Week as `[ ]`/`[x]`) is the surface; the detached store is where new items land. It does **not** write board columns and does **not** promote capacity scope docs.

User-invoked only (`disable-model-invocation: true`) — the agent can't fire it on its own.

## Rules (the rails enforce them)

| Rule | Effect |
| --- | --- |
| Week ≤ **5 open** | `week add` past the cap is refused with the arithmetic (2 on → at most 3 new) |
| Today **2–3**, **only from the week** | `add`/`set` past 3 refused; a today item not on the week is **promoted onto it** |
| Day-add ⇒ week-add | no orphan today items — ever |
| `[x]` = done | `done <ID>` checks it on both lists; a CAP goes to store state `done`; a board story going Done shows `[x]` on its own |

## Step 0 — Require configuration

Honor `VT_DIR` (rails sandbox) — default `./.4loops`:

```bash
VT="${VT_DIR:-./.4loops}"
# rails sandbox: honor VT_DIR; default path is .4loops/config
[ -f "$VT/config" ] && echo CONFIGURED || echo UNCONFIGURED
[ -f .4loops/config ] && true  # config-first contract (cwd default)
```

If `UNCONFIGURED`, stop: **"No 4loops board here yet — run `/4loops:configure` first."**

## Usage

**Today (mid-day direct add — the primary path):**
- `/prioritize add <ID|"text">…` — add to today (and onto the week if not there). IDs may be board (`P0-12`) or store (`CAP-003`); anything else is **free text → new store item** (`lever=today`, state active), no `/capture` step.
- `/prioritize set <ID|"text">…` — replace today (2–3).
- `/prioritize drop <ID>…` — take items off today (a CAP goes back to `lever=later`, logged — an honest park, not a deletion). Stays on the week.
- `/prioritize done <ID>…` — check the box `[x]` (today + week).

**Week:**
- `/prioritize week add|set|drop …` — the week's list under the cap. Free text lands with `lever=later`. `week drop` also takes the item off today (today ⊆ week).

**Store levers:**
- `/prioritize lever <CAP-ID> <urgent|today|later>` — change one CAP's lever without touching the lists.
- `/prioritize` (bare) — show the file + the week, then ONE pick: add to today / add to week / mark done / change a lever.

**Read:**
- `/prioritize since` — board + store items that landed since the last Today stamp and aren't on today (no change).

## Steps

### A. Direct add / set / drop / done (today or week)

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-priority.sh" [--project P] add  <ID|"text"> ...
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-priority.sh" [--project P] set  <ID|"text"> ...
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-priority.sh" drop <ID> ...
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-priority.sh" done <ID> ...
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-priority.sh" [--project P] week add|set <ID|"text"> ...
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-priority.sh" week drop <ID> ...
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-week.sh" --print
```

- Quote each free-text item as one argument. `--project` picks the store project key for new items (default: first board project).
- Today edits keep store levers coherent (committed CAP → `today`; a `today` CAP left out → `later`), freshen the Today stamp, and lift the gate when today + week are fresh. `board.md` is never written.
- A refusal (exit 4) carries the exact cap arithmetic — relay it and trim; never work around it.
- If the user said it in prose, apply directly — the ask *is* the confirmation. Only ask when an item is genuinely ambiguous (which project, ID vs new item).

### B. Bare `/prioritize` — the file, then one pick

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-today.sh" --orient      # the file · the week's open items · TODAY_SUGGESTED
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-store-list.sh" later     # the parked list (the only place it's dumped)
```

ONE `AskUserQuestion` (`multiSelect: true`, options `ID — title [lever]` from the week + the parked list): **Add to today** / **Add to week** / **Mark done** / **Mark urgent** — then step A or C. Nothing selected → no change.

### C. Store lever change

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-store-lever.sh" CAP-NNN urgent|today|later
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-store-list.sh" live
```

No deadline / impact / resource questions — levers only.

## Illegal / refuse clearly

| Situation | Behavior |
| --- | --- |
| Urge to dump onto board Backlog | Refuse — new items live in the store |
| Required capacity form (deadline·impact·resource) | Refuse — parked Track B; levers only |
| Week as a fourth lever | Not a lever — use `week add` for the week's list |
| Today item that isn't on the week | Not possible — the rail promotes it onto the week (cap permitting) |
| CAP not found | Script errors; name it as free text to create it, or `/capture` |

## Notes

- Priority stays **yours** — propose, you decide. Mutations ride the rails; never hand-edit `current-priorities.md` / store records.
- Brain-dump without prioritizing → `/capture`. Board state move → `/manage` or `/sync`. Full orientation → `/week` (one shot); mid-day re-pull → `/today`.
- Scripts: `vt-priority.sh` (mutate), `vt-store-lever.sh` (mutate), `vt-store-list.sh` / `vt-today.sh --orient` / `vt-week.sh --print` (readonly).
