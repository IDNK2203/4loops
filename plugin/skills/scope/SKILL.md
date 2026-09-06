---
name: scope
description: Scope escape — promote an active store CAP into an ephemeral scope doc under tasks/<KEY>/ with capacity judgment only (deadline · impact · resource). No modeling. Does not write board columns.
allowed-tools: Bash, AskUserQuestion
disable-model-invocation: true
user-invocable: true
argument-hint: "<CAP-ID or describe which capture to promote + deadline/impact/resource>"
---

`/scope` promotes an **active** detached-store item into an ephemeral **scope doc** at `.4loops/tasks/<PROJECT-KEY>/<CAP-ID>.md`. Capacity judgment only — **deadline · impact · resource**. No model, no implementation plan, no board writes. **Invoking `/scope` is your go** after I show the capacity fields.

User-invoked only (`disable-model-invocation: true`) — the agent can never trigger it on its own.

## Where things land (v2.5 Track B)

| Surface | Role |
| --- | --- |
| **`.4loops/tasks/<KEY>/`** | Ephemeral scope docs (THIS command writes here) |
| **`.4loops/store/`** | Source — item must be `state=active`; promote annotates `scoped_at` / `scope_doc` |
| **Board columns** | NEVER touched — do not call `vt-arrange` / `vt-draft` / `vt-transition` |

### Capacity-only rule

Refuse any request to add modeling, architecture, implementation plan, or design sections to the scope doc. Those belong on build rails (`stories/…`), not here. If the user starts modeling mid-scope, redirect: *"Scope is capacity only — park the model on your rails after handoff."*

### Lifecycle note

Scope doc is a **handoff artifact**. Track D removes it on Done; board row becomes the only durable 4loops trace. Track B documents that — does not implement expiry-on-Done.

## Step 0 — Require configuration

Honor `VT_DIR` (rails sandbox) — default `./.4loops`:

```bash
VT="${VT_DIR:-./.4loops}"
[ -f "$VT/config" ] && echo CONFIGURED || echo UNCONFIGURED
```

If `UNCONFIGURED`, stop: **"No 4loops board here yet — run `/4loops:configure` first."**  
Isolated sandbox tip: after `vt-init.sh`, you still need a `config` (run `/4loops:configure` or drop a minimal projects config into `$VT_DIR`). Scope scripts honor `VT_DIR`.

## Steps

### 1. Orient

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-store-list.sh" active
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-scope-list.sh" all
```

Pick the CAP to promote (from `$ARGUMENTS` or ask). If it's still `captured`, activate first:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-store-expire.sh" --activate CAP-NNN
```

### 2. Gather capacity (required)

For the chosen item, ensure you have:
- **deadline** — `YYYY-MM-DD` (use store deadline if present; else ask)
- **impact** — short why-it-matters / consequence if delayed (not a model)
- **resource** — cost/effort (e.g. `2d`, `1 eng-week`, `half-day`)

Ask **one** tight question if any field is missing. Do not invent a multi-section plan.

### 3. Show + promote (the command was your go)

```bash
# preview path (list before)
BOARD_BEFORE=$(shasum -a 256 "${VT_DIR:-./.4loops}/board.md" | awk '{print $1}')
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-scope-promote.sh" CAP-NNN \
  --deadline YYYY-MM-DD \
  --impact "…" \
  --resource "…"
BOARD_AFTER=$(shasum -a 256 "${VT_DIR:-./.4loops}/board.md" | awk '{print $1}')
# board hash must match
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-scope-read.sh" CAP-NNN
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-scope-list.sh" all
```

Show the resulting capacity table. If they object, they can `--force` re-promote with corrected fields (still capacity-only).

### 4. Hand off — do not Prioritize or Manage

Tell the user the scope doc is ready for **build rails** (one-way handoff). Do **not** pull into Planning (that's Track C `/prioritize`) and do **not** edit board columns. Next kernel step when they're ready: prioritize / sync — not this skill.

## Illegal / refuse clearly

| Situation | Behavior |
| --- | --- |
| CAP not found | Script errors; tell user to `/capture` first |
| state ≠ active | Activate then retry (or report) |
| Missing deadline/impact/resource | Ask once; do not promote incomplete |
| Modeling content requested | Refuse — capacity only |
| Already scoped | Report path; `--force` only if user wants overwrite |
| Urge to draft onto board | Refuse — Scope never writes `board.md` |

## Notes

- Paths: `.4loops/tasks/<KEY>/<CAP-ID>.md`, log at `.4loops/tasks/transitions.log`.
- Scripts: `vt-scope-promote.sh` (mutate), `vt-scope-list.sh` / `vt-scope-read.sh` (readonly).
- Re-promote: `vt-scope-promote.sh CAP-NNN … --force`.
