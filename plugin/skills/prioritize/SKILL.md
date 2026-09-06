---
name: prioritize
description: Thin prioritize escape — set/change store priority levers (urgent|today|later) and pull items into today's focus set. Also mid-cycle board focus add/set/since. Never drafts onto board Backlog; never requires deadline/impact/resource forms.
allowed-tools: Bash, AskUserQuestion
disable-model-invocation: true
user-invocable: true
argument-hint: "[lever <CAP-ID> <urgent|today|later> | today <CAP-ID…> | add <id…> | set <id…> | since]"
---

`/prioritize` is a **thin, focus-only escape** and the **real “scope” act** for v2.5 Track C: set or change **priority levers** on detached-store items and commit **today’s focus**. It does **not** write board columns and does **not** promote capacity scope docs. Week stays the `/week` ritual — not a fourth lever.

User-invoked only (`disable-model-invocation: true`) — the agent can't fire it on its own.

## Surfaces (LOCKED loop revision)

| Surface | This command |
| --- | --- |
| **Store levers** | `urgent` \| `today` \| `later` — change / pull to today |
| **Board focus** | Optional mid-cycle `add`/`set`/`since` on `current-priorities.md` (committed board IDs) |
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

**Store levers (Track C primary):**
- `/prioritize lever <CAP-ID> <urgent|today|later>` — change lever on one CAP.
- `/prioritize today <CAP-ID…>` — pull `later`/`urgent` item(s) into `today`.
- `/prioritize` (bare, store path) — list by lever, then ONE pick to pull into today or change lever.

**Board focus (legacy mid-cycle hatch):**
- `/prioritize add <id…>` — append to today's board focus (dedup).
- `/prioritize set <id…>` — replace today's board focus wholesale.
- `/prioritize since` — what's landed since last focus stamp (no change).

## Steps

### A. Store lever change / pull to today

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-store-list.sh" live
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-store-list.sh" later
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-store-list.sh" today
BOARD_BEFORE=$(shasum -a 256 "${VT_DIR:-./.4loops}/board.md" | awk '{print $1}')
# change among urgent|today|later
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-store-lever.sh" CAP-NNN today
# or pull one-or-many into today
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-store-lever.sh" today CAP-NNN [CAP-MMM …]
BOARD_AFTER=$(shasum -a 256 "${VT_DIR:-./.4loops}/board.md" | awk '{print $1}')
# board hash must match
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-store-list.sh" today
```

No deadline / impact / resource questions — levers only.

### B. Board focus (optional)

If the user named **board** IDs (`P0-NNN`), apply directly:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-priority.sh" add <id…>
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-priority.sh" set <id…>
cat "${VT_DIR:-./.4loops}/current-priorities.md"
```

Otherwise for board mid-cycle: `vt-priority.sh since` + `vt-drift.sh` + ONE `AskUserQuestion`.

## Illegal / refuse clearly

| Situation | Behavior |
| --- | --- |
| Urge to dump onto board Backlog | Refuse — levers live in store |
| Required capacity form (deadline·impact·resource) | Refuse — parked Track B; levers only |
| Week as a fourth lever | Redirect to `/week` ritual |
| CAP not found | Script errors; tell user to `/capture` first |

## Notes

- Priority stays **yours** — propose, you decide. Mutations ride the rails; never hand-edit records.
- New work → `/capture` (optional lever) or `/sync`. Board state move → `/manage` or `/sync`.
- Scripts: `vt-store-lever.sh` (mutate), `vt-store-list.sh` (readonly, filter by lever).
