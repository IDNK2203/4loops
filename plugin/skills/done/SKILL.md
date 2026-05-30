---
name: done
description: Move a story to the Done state. Use when the story is closed (shipped, merged, completed). Usage `/done <id>`. The story stays in the Done section until the weekly rolloff (T3) archives it.
allowed-tools: Bash
user-invocable: true
---

Move a story to the **Done** state.

## Usage

`/done <id>`  — e.g. `/done P0-005`

## Steps

### 1. Parse the story ID from the user's message

First positional arg. Format `<PROJECT>-<NNN>`. Uppercase the prefix.

If missing, use AskUserQuestion to pick from current Testing or In Progress section.

### 2. Invoke the transition script

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-transition.sh" "<ID>" done
```

### 3. Echo the result

Pass stdout through verbatim.

## Errors

If the script reports "Story not found" or "already in done", pass through unchanged.
