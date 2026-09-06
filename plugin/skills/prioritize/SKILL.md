---
name: prioritize
description: Thin, focus-only escape for mid-flight priority edits — add / set / drop items on today's focus or the week's anchors directly (board IDs, store CAP IDs, or free text that lands in the store on the spot), and change store levers (urgent|today|later). Never drafts onto board Backlog; never requires deadline/impact/resource forms.
allowed-tools: Bash, AskUserQuestion
disable-model-invocation: true
user-invocable: true
argument-hint: "[add|set|drop <ID|\"text\">… | week add|set|drop … | lever <CAP-ID> <urgent|today|later> | since]"
---

`/prioritize` is the **thin, focus-only escape** between the rituals: re-point today's focus or the week's anchors **without re-running `/today` / `/week`**, and adjust store levers. The living priorities doc (`current-priorities.md`) is the surface; the detached store is where new items land. It does **not** write board columns and does **not** promote capacity scope docs.

User-invoked only (`disable-model-invocation: true`) — the agent can't fire it on its own.

## Surfaces

| Surface | This command |
| --- | --- |
| **`current-priorities.md`** (Today + Week) | `add` / `set` / `drop` — mid-flight edits; Today edits freshen the day stamp |
| **Store** (`.4loops/store/`, levers `urgent\|today\|later`) | Free text you add becomes a store item on the spot; `lever` changes a CAP's lever |
| **Board.md columns** | NEVER — no `vt-arrange` / `vt-draft` / Backlog dumps |
| **Scope docs** | Parked — do not call `vt-scope-promote` as product path |

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
- `/prioritize add <ID|"text">…` — append to today's focus. IDs may be board (`P0-12`) or store (`CAP-003`); anything else is **free text → new store item** (`lever=today`, state active), no `/capture` step.
- `/prioritize set <ID|"text">…` — replace today's focus wholesale.
- `/prioritize drop <ID>…` — take items off today. A CAP goes back to `lever=later` (logged in `store/transitions.log` — an honest park, not a deletion).

**Week (anchors):**
- `/prioritize week add|set|drop …` — same shape for the week's anchors. Free text lands with `lever=later` (week is **not** a lever; `/today` pulls it in when its day comes).

**Store levers:**
- `/prioritize lever <CAP-ID> <urgent|today|later>` — change one CAP's lever without touching focus.
- `/prioritize` (bare) — show the orientation block, then ONE pick: add to today / add to week / change a lever.

**Read:**
- `/prioritize since` — board + store items that landed since the last Today stamp and aren't in focus (no change).

## Steps

### A. Direct add / set / drop (today or week)

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-priority.sh" [--project P] add  <ID|"text"> ...
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-priority.sh" [--project P] set  <ID|"text"> ...
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-priority.sh" drop <ID> ...
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-priority.sh" [--project P] week add|set <ID|"text"> ...
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-priority.sh" week drop <ID> ...
cat "${VT_DIR:-./.4loops}/current-priorities.md"
```

- Quote each free-text item as one argument. `--project` picks the store project key for new items (default: first board project).
- Today edits keep store levers coherent (committed CAP → `today`; a `today` CAP left out → `later`), freshen the Today stamp, and lift the gate when today + week are fresh. `board.md` is never written.
- If the user said it in prose, apply directly — the ask *is* the confirmation. Only ask when an item is genuinely ambiguous (which project, ID vs new item).

### B. Bare `/prioritize` — orient, then one pick

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-today.sh" --orient      # carry-forward · store pull · week anchors · SUGGESTED_FOCUS
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-store-list.sh" later     # the parked list (the only place it's dumped)
```

ONE `AskUserQuestion` (`multiSelect: true`, options `ID — title [lever]` from the store pull + parked list): **Add to today** / **Add to week** / **Mark urgent** — then step A or C. Nothing selected → no change.

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
| Week as a fourth lever | Not a lever — use `week add` for anchors |
| CAP not found | Script errors; name it as free text to create it, or `/capture` |

## Notes

- Priority stays **yours** — propose, you decide. Mutations ride the rails; never hand-edit `current-priorities.md` / store records.
- Brain-dump without prioritizing → `/capture`. Board state move → `/manage` or `/sync`. Full orientation → `/today` / `/week`.
- Scripts: `vt-priority.sh` (mutate), `vt-store-lever.sh` (mutate), `vt-store-list.sh` / `vt-today.sh --orient` (readonly).
