---
name: configure
description: First-run setup for Vibe Table — detect the projects you track, choose a week-start, confirm which build/share surfaces the rail guards, then bootstrap your board by spawning this week's focus. Run this once, right after the plugin installs. The aha is the first reconciliation, not a feature tour.
allowed-tools: Bash, AskUserQuestion
user-invocable: true
---

`/configure` turns a fresh install into a working board in one guided pass. The thesis: Vibe Table's value is the **habit of pulling your work together and reconciling it** — so this flow drives straight into the first reconciliation rather than touring features. Detect → confirm → write config → **spawn this week's focus** → render.

## Usage

`/configure` — interactive first-run setup. Safe to re-run (idempotent: config keys are replaced, project rows upserted).

## Steps

### 1. Init + detect

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-init.sh"
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-detect.sh"
```

`vt-detect.sh` prints TSV candidates (never writes):
- `PROJECT<TAB><name><TAB><suggested-prefix>` — top-level project dirs + nested git repos.
- `GATED<TAB><glob>` — likely build/share surfaces (content/, dist/, public/, …), already generalized per-project.

Hold these two lists.

### 2. Projects — propose, confirm, set prefixes

`AskUserQuestion` (multiSelect, header "Projects"): options = each detected `PROJECT` labeled `name (PREFIX)`. The user trims; **Other** adds any the scan missed (`name` → you propose a prefix). The PREFIX is the story-ID stem (e.g. `VT` → `VT-001`) — if the user wants a different one for a chosen project, take it from their note/Other and use that.

For each confirmed project:
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-config.sh" project <PREFIX> "<name>" [<repo>]
```

If detection found nothing, just ask the user to name their first project + prefix, then register it. At least one project is required (bootstrap needs a prefix to spawn stories under).

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

### 6. Render + hand off

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-render.sh"
cat .vibe-table/current-priorities.md
```

Tell the user where it lives (`.vibe-table/` in the workspace root) and that the board re-renders itself at the start of every session via the sentinel. From here the loop is `/vt:today` daily, `/vt:week` weekly. **Do not** narrate an on-ramp or feature list — the board they just filled is the message.

## Notes

- Re-running is safe: `week-start`/`gated` lines are replaced, project rows upserted by key. Bootstrap will append more backlog stories — only run bootstrap (step 5) on a genuinely empty board, or skip to step 4 when re-configuring an established workspace.
- The rail stays in unarmed grace (advisory) until step 5 arms it — that window is what lets bootstrap write the board before the gate clamps.
