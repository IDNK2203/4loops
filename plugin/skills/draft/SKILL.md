---
name: draft
description: Create a new story-draft in the 4loops Backlog. Story-drafts are lightweight contribution units that live in the backlog until promoted by a Story Authoring skill. Usage `/draft <title> --project <P> [--why <line>] [--context <path>]`. Use when the user wants to capture a new piece of work as a tracked story.
allowed-tools: Bash, AskUserQuestion
user-invocable: true
---

Create a new story-draft in the Backlog.

## Usage

`/draft <title> --project <P> [--why <line>] [--context <path>]`

- `<title>` (required) — short human-readable name
- `--project <P>` (required) — project ID prefix, e.g. P0, P1, OPS
- `--why <line>` (optional, strongly recommended) — one-line motivation so future-you understands the draft
- `--context <path>` (optional) — pointer to a context blob (note, transcript, brief)

## Steps

### 0. Require configuration

Drafting adds a story to a **configured** board — it must not create a bare one. Check first:

```bash
[ -f .4loops/config ] && echo CONFIGURED || echo UNCONFIGURED
```

If `UNCONFIGURED`, stop here and tell the user: **"No 4loops board is configured in this directory yet — run `/4loops:configure` first to set up your projects, gates, and focus."** Do not run the steps below. (This skill is also invoked internally by `/4loops:configure`'s bootstrap, which calls the `vt-draft.sh` script directly and is unaffected by this guard.)

### 1. Parse args from the user's message

Extract `<title>`, `--project`, `--why`, `--context`. Title is the first positional arg, the rest are flags.

If `--project` is missing → use AskUserQuestion to prompt for it (single-select with the project IDs detected in `.4loops/.ids/` if any exist, plus "Other"; if none exist, free-text prompt).

If `--why` is missing → use AskUserQuestion: "Why does this matter? (one line so future-you understands the draft)". This field is heavily recommended; only skip if the user explicitly says to.

### 2. Invoke the draft script

Run via Bash:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-draft.sh" "<PROJECT>" "<TITLE>" "<WHY>" "<CONTEXT>"
```

Pass empty strings (`""`) for omitted optional args, not unset.

### 3. Confirm to the user

The script prints `Created P0-NNN: <title>`. Echo that back to the user verbatim. No additional commentary unless something failed.

## Errors

- If the script fails, surface its stderr message directly. Do not retry without understanding why.
- If `--project` value is invalid (e.g. lowercase or contains spaces), normalize to uppercase / strip spaces before passing.
