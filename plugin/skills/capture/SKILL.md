---
name: capture
description: Capture escape — brain-dump a batch of work in plain language and it lands in the detached backlog store (with type + deadline + expiry lifecycle). A hidden power-user hatch; the normal way to capture is to just say it in /sync. It captures only — never sets priority, never moves board state.
allowed-tools: Bash, AskUserQuestion
disable-model-invocation: true
user-invocable: true
argument-hint: "<describe the work you want to capture>"
---

`/capture` turns a brain-dump into **detached store** items (off-board). It is a **thin escape** — the main path is to just say what's new in `/sync`, which captures as you talk. This exists for the case you want to dump a batch directly. You describe work in plain language; I parse it into items (with type + deadline) and write them to `.4loops/store/`. **Invoking `/capture` is your go** — I show what I'm capturing, then create it. I don't reorganize or reprioritize; capture is all this does.

User-invoked only (`disable-model-invocation: true`) — the agent can never trigger it on its own.

## Where things land (v2.5 Track A)

| Surface | Role |
| --- | --- |
| **`.4loops/store/`** | Capture + expiry pen (THIS command writes here) |
| **Board Backlog column** | NOT the capture target — do not call `vt-arrange.sh` / `vt-draft.sh` from `/capture` |

### Expiry state machine

```
captured  →  active  →  expired  →  cleared
   │            │           │
   │            │           └─ vt-store-expire.sh --clear / --clear-id
   │            └─ past TTL (default 14d) via vt-store-expire.sh
   └─ vt-store-expire.sh (tick activates captured → active)
```

TTL: `VT_STORE_TTL_DAYS` or `store_ttl_days: N` in `.4loops/config` (default 14).

## Step 0 — Require configuration

```bash
[ -f .4loops/config ] && echo CONFIGURED || echo UNCONFIGURED
```

If `UNCONFIGURED`, stop: **"No 4loops board here yet — run `/4loops:configure` first."**

## Steps

### 1. Orient

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-render.sh"
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-store-list.sh" live
cat .4loops/config 2>/dev/null
```

Read existing projects (Projects table / `config`). One project → that's the default; several → infer per item, ask only if genuinely ambiguous. Note anything already in the **store** (and on the board) so you don't duplicate it.

### 2. Parse the blurb into items

For each discrete work item, infer:
- **project** — the project key (default to the sole project).
- **title** — short imperative, no trailing punctuation.
- **type** — `dev` (fixed, testable) or `modeling` (fluid, emerges). Default `dev`.
- **deadline** — `YYYY-MM-DD` if the user gave or implied one (e.g. "by Friday"). Optional but encouraged — it's what drives drift later.
- **why** / **doc** — one-line rationale / a doc path if mentioned.

### 3. Show + create (the command was your go)

Preview the batch (creates nothing), then create it — no separate confirm gate, since invoking `/capture` is the consent:

```bash
# preview
printf '%s\t%s\t%s\t%s\t%s\n' "<P>" "<title>" "<type>" "<why>" "<YYYY-MM-DD>" ... | "${CLAUDE_PLUGIN_ROOT}/scripts/vt-store-capture.sh" --dry-run
# create
printf '%s\t%s\t%s\t%s\t%s\n' ... | "${CLAUDE_PLUGIN_ROOT}/scripts/vt-store-capture.sh"
# settle captured → active (happy-path tick)
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-store-expire.sh" --activate-only
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-store-list.sh" live
```

Show the preview to the user as you create — if they immediately object, items are only in the store (reversible: force-expire + clear, or leave them to TTL). If a field was genuinely ambiguous (which project? a date you couldn't infer?), ask ONE tight question before creating.

### 4. Hand priority / scope back

Every item lands in the **detached store** (`state=captured`, then activated). Do **not** set focus and do **not** draft onto the board — tell the user to pull into today's priority / scope later via `/sync` (or future Scope · Prioritize tracks). Priority stays the operator's.

## Notes

- TSV fields are tab-separated; titles/why must not contain tabs (the rails sanitize `|`). DUE must be `YYYY-MM-DD` (invalid is dropped with a warning).
- Store paths: `.4loops/store/items/CAP-NNN` (live), `.4loops/store/cleared/` (after clear), `.4loops/store/transitions.log`.
- Board `vt-draft` / `vt-arrange` still exist for intentional board drafts — `/capture` must not use them.
