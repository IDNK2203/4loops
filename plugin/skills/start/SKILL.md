---
name: start
description: Move a story to the In Progress state. Use when the user is actively beginning work on a story. Usage `/start <id>`. Records a timestamped state transition that downstream rituals (today/week activity, drift detection) read from.
allowed-tools: Bash
user-invocable: true
---

Move a story to the **In Progress** state.

## Usage

`/start <id>`  — e.g. `/start P0-005`

## Steps

### 1. Parse the story ID from the user's message

First positional arg. Format `<PROJECT>-<NNN>`. Uppercase the prefix.

If missing, use AskUserQuestion to pick from current Planning section.

### 2. Invoke the transition script

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-transition.sh" "<ID>" in-progress
```

### 3. Echo the result

Pass stdout through verbatim.

## Errors

If the script reports "Story not found" or "already in in-progress", pass through unchanged.
