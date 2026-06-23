---
name: capture
description: Capture escape — brain-dump a batch of work in plain language and it drafts the stories onto the board (with type + deadline). A hidden power-user hatch; the normal way to capture is to just say it in /nav. It captures only — never sets priority, never moves state.
allowed-tools: Bash, AskUserQuestion
disable-model-invocation: true
user-invocable: true
argument-hint: "<describe the work you want to capture>"
---

`/capture` turns a brain-dump into board stories. It is a **thin escape** — the main path is to just
say what's new in `/nav`, which captures as you talk. This exists for the case you want to dump a
batch directly. You describe work in plain language; I parse it into stories (with type + deadline)
and draft them onto the board. **Invoking `/capture` is your go** — I show what I'm capturing, then
create it. I don't reorganize or reprioritize; capture is all this does.

User-invoked only (`disable-model-invocation: true`) — the agent can never trigger it on its own.

## Step 0 — Require configuration

```bash
[ -f .4loops/config ] && echo CONFIGURED || echo UNCONFIGURED
```

If `UNCONFIGURED`, stop: **"No 4loops board here yet — run `/4loops:configure` first."**

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

Preview the batch (creates nothing), then create it — no separate confirm gate, since invoking `/capture` is the consent:

```bash
# preview
printf '%s\t%s\t%s\t%s\t%s\n' "<P>" "<title>" "<type>" "<why>" "<YYYY-MM-DD>" ... | "${CLAUDE_PLUGIN_ROOT}/scripts/vt-arrange.sh" --dry-run
# create
printf '%s\t%s\t%s\t%s\t%s\n' ... | "${CLAUDE_PLUGIN_ROOT}/scripts/vt-arrange.sh"
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-render.sh"
```

Show the preview to the user as you create — if they immediately object, you've only drafted to Backlog (reversible: `vt-transition.sh <id> abandoned`, or retire it in the next `/4loops:week` prune). If a field was genuinely ambiguous (which project? a date you couldn't infer?), ask ONE tight question before creating.

### 4. Hand priority back

Every story lands in **Backlog**. Do **not** set focus — tell the user to choose what to work on via `/nav` (or `/4loops:prioritize add <id…>`). Priority stays the operator's.

## Notes

- TSV fields are tab-separated; titles/why must not contain tabs (the rails sanitize `|`). DUE must be `YYYY-MM-DD` (invalid is dropped with a warning).
