---
name: prioritize
description: Focus-only escape — set or re-point today's 1-3 focus directly (add / set / since), without the full daily walk. A hidden power-user hatch; the normal way to re-point is to just talk in /nav. Never moves story state and never captures — focus only.
allowed-tools: Bash, AskUserQuestion
disable-model-invocation: true
user-invocable: true
argument-hint: "[add <id…> | set <id…> | since]"
---

`/prioritize` is a **thin, focus-only escape** for adjusting today's focus by hand. It is **not the
main path** — between rituals you just talk in `/nav` and it re-points for you. This exists for the
rare case you want to set focus directly without the conversation. It **only** touches the Today
focus line: it never moves a story's state (that's `/manage` or `/nav`) and never captures new work
(that's `/capture` or `/nav`).

User-invoked only (`disable-model-invocation: true`) — the agent can't fire it on its own.

## Step 0 — Require configuration

```bash
[ -f .4loops/config ] && echo CONFIGURED || echo UNCONFIGURED
```

If `UNCONFIGURED`, stop: **"No 4loops board here yet — run `/4loops:configure` first."**

## Usage

- `/prioritize add <id…>` — append to today's focus (dedup).
- `/prioritize set <id…>` — replace today's focus wholesale.
- `/prioritize since` — show what's landed since you last set focus (no change).
- `/prioritize` (bare) — print the lean "what shifted" view, then one pick to bump focus.

## Steps

If the user named IDs, apply directly:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-priority.sh" add <id…>     # append (dedup) + freshen Today stamp
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-priority.sh" set <id…>     # replace focus
cat .4loops/current-priorities.md
```

Otherwise print the lean view and offer one structured pick:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-priority.sh" since     # drafted/moved since the last Today stamp, not in focus
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-drift.sh"              # OVERDUE · DUE-SOON · caps · stale
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-today.sh" --current    # today's focus now
```

ONE `AskUserQuestion` — **"Add to today's focus?"** (multiSelect): options = the `since` candidates +
any overdue/due-soon not yet focused → `vt-priority.sh add <id…>`. Lead with overdue / due-soon.

`add`/`set` freshen the Today stamp (the day's gate stays lifted) and re-arm/clear like `/today`.

## Notes

- Priority stays **yours** — propose, you decide. Mutations ride the rails; never hand-edit records.
- New work → `/capture` (or just say it in `/nav`). A state move → `/manage` (or `/nav`). This is focus only.
