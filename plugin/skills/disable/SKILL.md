---
name: disable
description: Opt this workspace out of 4loops enforcement. Writes .4loops/disabled so the orientation gate, the rail-capability bash-gate, the rail-record protection and the prompt nudge all fail open. Deletes nothing — board, priorities, store and archive survive untouched, and `off` puts the rail straight back. Also reports status. User-invoked only.
allowed-tools: Bash
disable-model-invocation: true
user-invocable: true
argument-hint: "[on|off|status]  (no argument = on)"
---

`/disable` is the **off-ramp**. It switches 4loops enforcement off for this workspace and **deletes
nothing** — your board, priorities, store and archive stay exactly as they are, so turning it back on
resumes the same board.

**User-invoked only** (`disable-model-invocation: true`) — the agent can never fire this on its own,
and `.4loops/disabled` is a rail-owned record it cannot hand-write either. Switching the rail off is
your decision alone: an agent that can disable its own gate has no gate.

## Usage

| Form | Result |
| --- | --- |
| `/disable` | Turn enforcement **off** (writes `.4loops/disabled`) |
| `/disable status` | Report whether this workspace is enabled or disabled — changes nothing |
| `/disable off` | Turn enforcement **back on** (removes the flag) |

## What goes off

While `.4loops/disabled` exists, **every** hook steps aside:

| Check | Normally | While disabled |
| --- | --- | --- |
| **Orientation gate** (`vt-gate.sh`, `vt-bash-gate.sh`) | Blocks writes to gated product surfaces while priorities are stale | Allows |
| **Rail capability** (bash-gate B1) | The agent needs a user-typed `/4loops:*` to drive a mutating rail | Allows |
| **Rail-record protection** (B2) | `board.md` / `current-priorities.md` / `store/` / `tasks/` can't be hand-edited | Allows — hand-edit freely |
| **Prompt nudge** (`vt-prompt-gate.sh`) | Injects the ritual reminder once on a stale day | Silent |

The opt-out is **full** on purpose. A half-disabled rail that still refused a board hand-edit would
be more confusing than either honest state — so while disabled, hand-editing `board.md` is allowed.
The rails stay the safer path (they keep counts and `transitions.log` in sync), so if the user wants
the board moved, `/4loops:sync` is still the better answer than a hand-edit.

The `SessionStart` sentinel prints a short "disabled" notice each session with the re-enable line, so
the rail can't stay silently off forever.

## What stays

`board.md` · `current-priorities.md` · `store/` · `tasks/` · `archive/` · `transitions.log` ·
`config`. **Nothing is deleted.** Never offer to clean up `.4loops/` as part of disabling, and never
do it unasked — if the user wants the data gone that's a separate, explicit request.

## Steps

### 1. Read the argument

`$ARGUMENTS` is `on` / `off` / `status`, or empty. Empty means **on** (turn enforcement off) — that's
what a bare `/4loops:disable` means.

### 2. Run the rail

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-disable.sh" --status   # report only
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-disable.sh" --on       # opt out
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-disable.sh" --off      # opt back in
```

Both `--on` and `--off` are idempotent — running one twice is safe and says so.

### 3. Print the result verbatim, then the re-enable line

The script's stdout already names the flag path and how to undo it. Pass it through, then confirm in
one sentence: enforcement is off for this workspace, nothing was deleted, and the way back is

```
rm .4loops/disabled
```

or `/4loops:disable off`. Don't add a lecture about why the rail is good.

## Notes

- **Scope is this workspace only.** The flag lives in this workspace's `.4loops/`. Other workspaces
  with 4loops enabled are unaffected.
- **`--status` is a read-only rail** — never gated, no capability needed. `--on` / `--off` need the
  capability your typing `/4loops:disable` mints.
- **Turning it back on is never blocked.** Once the flag is present the gates fail open, so `--off`
  runs with no capability at all.
- The plugin can also be removed outright (`/plugin uninstall 4loops`) if the user wants it gone
  rather than off. `/disable` is the reversible middle option — mention it only if they ask.
