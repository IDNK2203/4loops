---
name: arrange
description: User-invoked task arranger — describe a batch of work in plain language and it drafts the stories onto the board, riding the rails so the board never goes stale. Proposes first; creates only on your explicit confirmation. Never sets priority on its own.
allowed-tools: Bash, AskUserQuestion
disable-model-invocation: true
user-invocable: true
argument-hint: "<describe the work you want to capture>"
---

`/arrange` turns a brain-dump into board stories **without you hand-typing rail commands**. You describe a batch of work in natural language; the arranger parses it into stories, **proposes** them, and — only after you confirm — drafts them onto the board through the rails (so counts, the grid, and the log stay in sync). It captures and buckets; **it never decides your priority** — you set focus afterward.

This skill is **user-invoked only** (`disable-model-invocation: true`) — the main agent can never trigger it on its own. That's deliberate: arranging the board is the operator's call.

## Usage

`/arrange <describe the work>` — e.g. `/arrange I need to write the launch thread, fix the gate bug, and start sketching the demo video`.

## Steps

### 1. Orient

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-render.sh"
cat .4loops/config 2>/dev/null
```

Read the existing projects (the Projects table / `config`). If exactly one project exists, that's the default. If several, you'll ask which each item belongs to.

### 2. Parse the blurb into candidate stories

From the user's description, extract discrete work items. For each, infer:
- **project** — the project key (default to the sole project; ask if ambiguous).
- **title** — a short imperative title (no trailing punctuation).
- **type** — `dev` (objective fixed + testable) or `modeling` (objective fluid; emerges through discovery). Default `dev`.
- **why** — a one-line rationale if the user gave one (optional).

### 3. Propose — preview, do not create

Show the proposed batch as a preview (this creates nothing):

```bash
printf '%s\t%s\t%s\t%s\n' "<PROJECT>" "<TITLE>" "<TYPE>" "<WHY>" ... | "${CLAUDE_PLUGIN_ROOT}/scripts/vt-arrange.sh" --dry-run
```

Then AskUserQuestion: **Create all**, **Edit** (adjust titles/types/projects/drop items), or **Cancel**. Never skip this gate — `/arrange` proposes, the operator disposes.

### 4. Create the confirmed batch (only on explicit go)

Pipe the confirmed TSV (one `PROJECT⇥TITLE⇥TYPE⇥WHY` line per story) into the executor:

```bash
printf '%s\t%s\t%s\t%s\n' ... | "${CLAUDE_PLUGIN_ROOT}/scripts/vt-arrange.sh"
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-render.sh"
```

Every story lands in **Backlog**. Stories ride the rails (`vt-draft`), so the board stays honest.

### 5. Hand priority back to the operator

Do **not** set focus automatically. Tell the user the stories are on the board and they can run `/4loops:today` or `/4loops:priority add <id...>` to choose what to work on. Priority stays operator-owned.

## Notes

- Fields are tab-separated; titles/why must not contain tabs (the rails sanitize `|`).
- If the user names something already on the board, say so rather than duplicating it.
- Nothing is created before step 4's confirmation.
