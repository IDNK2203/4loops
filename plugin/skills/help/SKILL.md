---
name: help
description: The 4loops command map — what each /4loops:* command does, which one to type next, and one line on each of the two gates (orientation = the codebase only; bash-gate = rail capability). Read-only: it prints the map and mutates nothing. Use when the user asks what 4loops does, which command to run, why a 4loops gate blocked something, or how to turn 4loops off.
allowed-tools: Bash
user-invocable: true
---

`/help` prints the 4loops command map. It is the one **model-invokable** command besides `/board`:
when the user asks what 4loops can do, wonders which command to type, or hits a gate they don't
recognise, print this map rather than guessing or improvising a tour.

**Read-only.** No rail mutates here. Do not run a ritual, do not move the board, do not write
`.4loops/`. Print the map, answer the question, stop.

## Steps

### 1. Print the map

Reproduce the two tables below (Daily loop, then Board), plus the **two gates** line. One screen —
don't expand it into a feature essay, and don't drop the gate line: it is the part users are
actually confused by.

### 2. Answer the specific question, if there was one

If the user asked something narrower ("how do I add a task?", "why was that blocked?", "how do I
turn this off?"), lead with the one row that answers it, then the map for context.

### 3. If a matrix exists in the repo, point at it

Only for the 4loops repo itself. Check once, and mention the path only if the file is really there:

```bash
ls ~/Ship/bls/stories/vibe-table/16-v2.5-orientation-loop/tracks/INVOCATION-MATRIX-*.md 2>/dev/null
```

That file is the source of truth for gates, capabilities and rail tiers. Outside this repo there is
nothing to point at — say nothing.

## The map

**Daily loop** — the part you actually type every day:

| Command | What it does |
| --- | --- |
| `/4loops:week` | **The one-shot orientation. Type this every morning.** Prints your checkbox priorities, a light look-back (last week on a new week, since yesterday otherwise), sets the week from the store (≤5 open), picks today's 2–3 from it. This is what clears the orientation gate. |
| `/4loops:today` | Mid-day re-pull of today's 2–3 from the week. Optional — `/week` already includes the today beat. |
| `/4loops:prioritize` | Thin focus-only edit between orientations: add / set / drop on today or the week, check a box done, change a store lever. |

**Board and capture** — the state side:

| Command | What it does |
| --- | --- |
| `/4loops:sync` | **In between, just talk.** Open it once and say what changed ("metrics endpoint is done, add rate limiting"); it captures, moves state and re-prioritises on the real rails. |
| `/4loops:board` | Render the kanban — Planning → In Progress → Testing → Done. |
| `/4loops:capture` | Direct brain-dump into the detached store with a lever (`urgent` / `today` / `later`). |
| `/4loops:manage` | Direct state + lifecycle moves: start / testing / done, edit · merge · remove a task, flush Done, abandon / supersede, rename a project key. |

**Setup and off-ramp:**

| Command | What it does |
| --- | --- |
| `/4loops:configure` | First-run setup — detect projects, pick a week-start, confirm the gated surfaces, spawn this week's focus. Run once. |
| `/4loops:help` | This map. |
| `/4loops:disable` | Opt this workspace out of enforcement entirely. Deletes nothing; undone with `rm .4loops/disabled`. |

**Not sure? Type `/4loops:week` in the morning and `/4loops:sync` the rest of the day.** Everything
else is a shortcut for something those two already do.

## The two gates (one line each)

- **Orientation gate** — blocks writes to your **gated product surfaces (the codebase) only**,
  while today's or this week's priorities are stale. `/4loops:week` clears it. It does **not** freeze
  the board, and it never blocks notes, research or reading.
- **Rail-capability bash-gate** — blocks the *agent* from driving a mutating `vt-*.sh` rail unless
  **you** typed a `/4loops:*` command this session. Nothing is stale when this fires; the rail simply
  wasn't handed over. One capability per session, **last slash wins** — re-type the command you need.

Read-only rails (`vt-render.sh`, `vt-drift.sh`, `vt-store-list.sh`, `vt-week.sh --orient`,
`vt-today.sh --orient`) pass both gates with no capability and no fresh orientation. They are never
blocked.

## Never blocked

`/help` reads nothing that either gate guards, so it always works — before the morning `/week`,
mid-ritual, or while some other write is being denied. A deny you hit elsewhere is never a reason to
refuse this.
