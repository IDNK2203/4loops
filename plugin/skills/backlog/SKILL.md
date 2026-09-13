---
name: backlog
description: Print the 4loops intake view — uncommitted work that is not yet on the active board. Shows detached store items with their levers (urgent / today / later), plus any cells still sitting in the legacy pre-migration Backlog column. Read-only: it lists intake and mutates nothing. Use when the user asks what's in the backlog, what's captured but not started, or what still needs migrating.
allowed-tools: Bash
user-invocable: true
---

Print the **intake** view for this workspace: work that has been captured but is not yet on the
active pipeline.

Intake lives in two places, and this view shows both:

1. **The detached store** — where `/4loops:capture` and `/4loops:sync` put uncommitted work. Each
   item carries a lever: `urgent`, `today`, or `later`. This is the modern intake.
2. **The legacy Backlog column** — a pre-v2.5 board still holds cells in a Backlog column on the
   board itself. Board intake is closed, so those rows need migrating out.

The board (`/4loops:board`) is the *active pipeline* — Planning → In Progress → Testing → Done.
Backlog is deliberately not one of its columns. That's why intake has its own view.

## Usage

| Form | Result |
|---|---|
| `/backlog` | Store items (live) + any legacy Backlog cells |

No flags. Use `/4loops:capture` to add to intake and `/4loops:sync` to promote something onto the
board — do not improvise either from here.

## Steps

### 1. List the detached store

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-store-list.sh" live
```

Each line is `ID  state  lever  project  age=Nd  title (due …)`. Print them as-is under a **Store**
heading. Do not re-sort or re-group unless the user asked for a particular slice.

### 2. List the legacy Backlog column

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-render.sh" backlog
```

On a migrated (or new) board this column is empty and the render says so — that is the normal case,
not an error. If it does hold cells, print them under a **Legacy Backlog** heading, followed by the
migration hint the render already emits.

### 3. If both are empty

Say so plainly in one line:

> Intake is empty — nothing captured and no legacy Backlog cells. Capture with `/4loops:capture`.

Don't pad an empty intake with suggestions about what the user could work on.

## Migration is not this command

If legacy Backlog cells show up, **report them and stop**. `vt-migrate-backlog.sh` is a `mutate`
rail: it moves real rows on a real board, it needs a capability this skill never mints, and running
it is the user's decision. Surface the hint the render prints, and leave it there.

## Never blocked

Both rails here — `vt-store-list.sh` and `vt-render.sh` — are **read-only**. They need no session
capability and the orientation gate does not apply to them. Print the intake whenever asked, before
the morning `/week` or while some other write is being denied. A deny you hit elsewhere is never a
reason to refuse this.

## Errors

If the board doesn't exist yet, the render prints a hint to run `/4loops:configure` first. Pass that
through unchanged. An empty store is not an error — it prints nothing, which step 3 covers.
