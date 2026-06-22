---
name: arrange
description: User-invoked capture — brain-dump a batch of work in plain language and it drafts the stories onto the board (with type + deadline), riding the rails so the board never goes stale. You invoke it, so it captures from what you say; it never sets your priority. Run /today or /priority afterward to choose focus.
allowed-tools: Bash, AskUserQuestion
disable-model-invocation: true
user-invocable: true
argument-hint: "<describe the work you want to capture>"
---

`/arrange` turns a brain-dump into board stories — no hand-typing rail commands. You describe a batch of work in plain language; I parse it into stories (with type + deadline) and draft them onto the board. **Invoking `/arrange` is your go** — I show you what I'm capturing, then create it. I don't reorganize or reprioritize; capture is all this does.

This skill is **user-invoked only** (`disable-model-invocation: true`) — the agent can never trigger it on its own.

## Steps

### 1. Orient

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-render.sh"
cat .4loops/config 2>/dev/null
```

Read existing projects (Projects table / `config`). One project → that's the default; several → infer per item, ask only if genuinely ambiguous. Note anything already on the board so you don't duplicate it.

### 2. Parse the blurb into stories

For each discrete work item, infer:
- **project** — the project key (default to the sole project).
- **title** — short imperative, no trailing punctuation.
- **type** — `dev` (fixed, testable) or `modeling` (fluid, emerges). Default `dev`.
- **deadline** — `YYYY-MM-DD` if the user gave or implied one (e.g. "by Friday"). Optional but encouraged — it's what drives drift later.
- **why** / **doc** — one-line rationale / a doc path if mentioned.

### 3. Show + create (the command was your go)

Preview the batch (creates nothing), then create it — no separate confirm gate, since invoking `/arrange` is the consent:

```bash
# preview
printf '%s\t%s\t%s\t%s\t%s\n' "<P>" "<title>" "<type>" "<why>" "<YYYY-MM-DD>" ... | "${CLAUDE_PLUGIN_ROOT}/scripts/vt-arrange.sh" --dry-run
# create
printf '%s\t%s\t%s\t%s\t%s\n' ... | "${CLAUDE_PLUGIN_ROOT}/scripts/vt-arrange.sh"
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-render.sh"
```

Show the preview to the user as you create — if they immediately object, you've only drafted to Backlog (reversible via `/4loops:archive`). If a field was genuinely ambiguous (which project? a date you couldn't infer?), ask ONE tight question before creating.

### 4. Hand priority back

Every story lands in **Backlog**. Do **not** set focus — tell the user to run `/4loops:today` or `/4loops:priority add <id…>` to choose what to work on. Priority stays the operator's.

## Notes

- TSV fields are tab-separated; titles/why must not contain tabs (the rails sanitize `|`). DUE must be `YYYY-MM-DD` (invalid is dropped with a warning).
