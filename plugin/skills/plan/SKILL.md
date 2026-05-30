---
name: plan
description: Move a story to the Planning state. Use after a story has been promoted by a Story Authoring skill (e.g. `/story`, `/grill`) and has a folder + plan in place but work hasn't started. Usage `/plan <id>`. Use when the user is ready to mark a story as scoped but not yet active.
allowed-tools: Bash
user-invocable: true
---

Move a story to the **Planning** state.

## Usage

`/plan <id>`  — e.g. `/plan P0-005`

## Steps

### 1. Parse the story ID from the user's message

The ID is the first positional arg. Format is `<PROJECT>-<NNN>` (e.g. `P0-005`). Uppercase the prefix; preserve the numeric suffix.

If no ID is provided, ask the user via AskUserQuestion which story they mean (pull candidates from the current Backlog section of the board).

### 2. Invoke the transition script

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-transition.sh" "<ID>" planning
```

### 3. Echo the result

Surface stdout (`<ID>: <old> → planning`) verbatim. No extra commentary.

## Errors

If the script reports "Story not found" or "already in planning", pass through unchanged.
