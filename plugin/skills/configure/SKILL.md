---
name: configure
description: First-run setup for Vibe Table — detect the projects you track, choose a week-start, confirm which build/share surfaces the rail guards, then bootstrap your board by spawning this week's focus. Run this once, right after the plugin installs. The aha is the first reconciliation, not a feature tour.
allowed-tools: Bash, AskUserQuestion, TodoWrite
user-invocable: true
---

`/configure` turns a fresh install into a working board in one guided pass. The thesis: Vibe Table's value is the **habit of pulling your work together and reconciling it** — so this flow drives straight into the first reconciliation rather than touring features. Detect → confirm → write config → **spawn this week's focus** → render.

## Usage

`/configure` — interactive first-run setup. Safe to re-run (idempotent: config keys are replaced, project rows upserted).

## Steps

**Drive the flow with a visible checklist** so configure reads as stepping tasks, not a wall of questions. Before step 1, create a `TodoWrite` list with these items:

1. Detect projects
2. Confirm projects + prefixes
3. Choose week start
4. Confirm gated surfaces
5. Set this week's anchors
6. Pick today's focus
7. Arm rail + render board

Mark each `in_progress` when you start it and `completed` when it's done — the user watches the checklist fill in as they go.

### 1. Init + detect

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-init.sh"
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-detect.sh"
```

`vt-detect.sh` prints TSV candidates (never writes):
- `PROJECT<TAB><name><TAB><suggested-prefix>` — **git repos** (the high-confidence auto-suggest).
- `AREA<TAB><name>` — non-repo top-level folders (notes/docs/context). Untracked by default; offer to promote.
- `GATED<TAB><glob>` — build/share surfaces inside projects (content/, dist/, public/, …), **per-repo** (not generalized).

Hold these three lists.

### 2. Projects + Areas — confirm what's tracked

A **Project** is something with a done-state you'll track (git repos are the auto-suggest — but it's the user's call). An **Area** is an evolving folder with no done-state — untracked and never gated. Sort the candidates:

- `AskUserQuestion` (multiSelect, header "Projects"): options = each detected `PROJECT` labeled `name (PREFIX)`, **pre-selected**. Deselecting one **demotes** it to an Area (untracked). **Other** adds a project the scan missed — including **promoting** a detected Area (name it, propose a prefix).
- If any `AREA` candidates were detected, surface them so the promote choice is explicit: *"Detected these as untracked Areas: `<names>`. Promote any to a tracked Project?"* Promote → register like a project; leave → simply untracked (no gating, free-edit; no registration needed).

The PREFIX is the story-ID stem (e.g. `VT` → `VT-001`); honor a custom prefix from the user's note/Other.

For each confirmed project:
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-config.sh" project <PREFIX> "<name>" [<repo>]
```

If detection found nothing trackable, ask the user to name their first project + prefix, then register it. At least one project is required (bootstrap needs a prefix to spawn stories under). Areas need no registration — untracked is their default.

### 3. Week start

`AskUserQuestion` (single-select, header "Week start"): **Monday (ISO)** / **Sunday**. Then:
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-config.sh" week-start <mon|sun>
```

### 4. Gating — propose-then-confirm

The rail blocks product-surface writes until you've reconciled, so it's useful from day one. `AskUserQuestion` (multiSelect, header "Gated"): options = each detected `GATED` glob, **pre-selected**. The user trims/adds (Other = a custom glob). Seed with the built-ins `projects/*/content/*`, `projects/*/gists/*`, `projects/*/repo-scaffolding/*` if detection is thin, so there are ≥2 options and the set is sensible.

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-config.sh" gated <glob1> <glob2> ...
```

This **replaces** the built-in default glob set — once written, only these globs gate. (The hard-exempt surfaces — `.vibe-table/`, `study/`, `learnings/`, root `*.md`, `.env` — are always writable regardless.)

Show the final config: `"${CLAUDE_PLUGIN_ROOT}/scripts/vt-config.sh" show`.

### 5. Bootstrap — spawn this week's focus

This is the aha. Don't tour; **fill the board with the user's real work.**

1. Ask, in plain text: **"What are your 3–5 anchors this week? One per line."** If several projects are configured, accept `PREFIX: title` lines (or ask which project each belongs to); with one project, use its prefix for all.
   For each line:
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/vt-draft.sh" <PREFIX> "<title>"
   ```
   Parse the `Created <ID>: …` line for each new ID. Collect them as `WEEK_IDS`.

2. Set the week focus (writes the Week stamp + arms the rail):
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/vt-week.sh" <WEEK_IDS...>
   ```

3. `AskUserQuestion` (multiSelect, header "Today"): options = `WEEK_IDS` labeled `ID — title`. For each selected, start it and set today's focus:
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/vt-transition.sh" <id> in-progress     # per selected id
   "${CLAUDE_PLUGIN_ROOT}/scripts/vt-today.sh" <selected-ids...>
   ```
   (`vt-today.sh` writes the Today stamp, arms the rail, and marks this session cleared — the gate is now live but satisfied.)

### 6. Celebrate + render + hand off

Make the finish a *moment* — the first reconciliation is the aha, so mark it:

1. Say it plainly: **"🎉 Vibe Table is configured — your board is live."**
2. Render the board (the payoff):
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/vt-render.sh"
   cat .vibe-table/current-priorities.md
   ```
3. One line on the loop, and nothing more: **"From here: `/vt:today` each day to reconcile, `/vt:week` each week to anchor. Move stories with `/vt:start` · `/vt:test` · `/vt:done`, or just ask me to move them."**
4. Mark the final todo `completed`.

It lives in `.vibe-table/` at your workspace root and re-renders at the start of every session via the sentinel. **Do not** narrate an on-ramp or feature list — the board they just filled plus that one-line loop *is* the whole message.

## Notes

- Re-running is safe: `week-start`/`gated` lines are replaced, project rows upserted by key. Bootstrap will append more backlog stories — only run bootstrap (step 5) on a genuinely empty board, or skip to step 4 when re-configuring an established workspace.
- The rail stays in unarmed grace (advisory) until step 5 arms it — that window is what lets bootstrap write the board before the gate clamps.
