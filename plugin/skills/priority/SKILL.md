---
name: priority
description: Midweek priority reconciliation — re-point today's focus between the daily/weekly rituals when new work lands, without rerunning the whole walk. Add to or replace today's focus, or surface what's been added since you last set focus. Freshens the Today stamp so the gate lifts.
allowed-tools: Bash, AskUserQuestion
user-invocable: true
---

`/priority` is the **lightweight midweek re-point**. When work lands after you've already run `/today`, you don't need the full reconciliation walk — just adjust focus and move on. Writing focus freshens the Today stamp, so this also lifts the day's gate.

## Usage

- `/priority` — show what's landed since you last set focus, then offer to add/replace.
- `/priority add <ID...>` — append stories to today's focus.
- `/priority set <ID...>` — replace today's focus.

## Steps

### 1. Surface what changed

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-priority.sh" since
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-today.sh" --current
```

`since` lists stories drafted or moved since the current Today stamp that aren't already in focus — the candidates you might be silently outrunning. `--current` shows today's focus now.

### 2. Re-point (the operator decides)

If the user named IDs, apply directly. Otherwise AskUserQuestion: **Add** the surfaced candidates, **Replace** focus with a new 1–3 list, or **Leave as is**.

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-priority.sh" add <ID...>     # or: set <ID...>
cat .4loops/current-priorities.md
```

The script dedups on `add`, freshens the Today stamp, arms the rail, and clears this session when the gate is fully clear. Priority stays **operator-owned** — propose, never auto-set. The file IS the message.

## Errors

Bad subcommand exits non-zero with a usage line — surface it and stop.
