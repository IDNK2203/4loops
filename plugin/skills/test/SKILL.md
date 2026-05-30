---
name: test
description: Move a story to the Testing state. Use when the work is complete and is now in validation (PR review, manual QA, awaiting sign-off). Usage `/test <id>`. Distinct from running unit tests — this is a state-machine transition.
allowed-tools: Bash
user-invocable: true
---

Move a story to the **Testing** state.

## Usage

`/test <id>`  — e.g. `/test P0-005`

(Note: this is a state transition, not a "run tests" command. The state means: work is done, awaiting validation/review.)

## Steps

### 1. Parse the story ID from the user's message

First positional arg. Format `<PROJECT>-<NNN>`. Uppercase the prefix.

If missing, use AskUserQuestion to pick from current In Progress section.

### 2. Invoke the transition script

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-transition.sh" "<ID>" testing
```

### 3. Echo the result

Pass stdout through verbatim.

## Errors

If the script reports "Story not found" or "already in testing", pass through unchanged.
