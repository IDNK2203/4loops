---
name: priorities
description: Print the current 4loops priorities — today's 2–3 and this week's ≤5, as the checkbox list they're stored as. Read-only: it shows the same surface the morning orientation prints without running the ritual, setting anything, or clearing the orientation gate. Use when the user asks what they're working on today, what's on the week, or wants to see their focus without re-orienting.
allowed-tools: Bash
user-invocable: true
---

Print this workspace's current priorities — **today** and **this week**, as checkboxes.

This is the *view*, not the ritual. `/4loops:week` is what sets priorities and clears the
orientation gate; `/priorities` only shows you what is already on file. If the file is stale, this
prints the stale content and says so — it does not quietly re-orient to hide the staleness.

## Usage

| Form | Result |
|---|---|
| `/priorities` | Print today's focus + this week's list |

No flags. If the user wants to *change* a priority, that's `/4loops:prioritize` (thin edit) or
`/4loops:week` (the full orientation) — say so rather than improvising an edit here.

## Steps

### 1. Invoke the print rail

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-priorities-print.sh"
```

### 2. Surface the output

Print the script's stdout **verbatim** — it is a markdown artifact; let it render directly. Do not
reflow the checkboxes into prose, do not re-order them, and do not add a summary of what the user
"should" do next. The list IS the message.

### 3. Only if the stamps are stale, add one line

If the printed dates show today's or this week's focus is out of date, add a single line under the
output: `Stale — run /4loops:week to re-orient.` One line, no lecture. Never run `/week` yourself:
the orientation is user-invoked by design, and firing it here would clear a gate the user never
asked you to clear.

## Never blocked

`vt-priorities-print.sh` is a **read-only rail**: it cats `current-priorities.md` and returns. It
needs no session capability and the orientation gate does not apply to it. Print the priorities
whenever asked — before the morning `/week`, mid-ritual, or while some other write is being denied.
A deny you hit elsewhere is never a reason to refuse this.

Reading the priorities never clears the gate. Only `/4loops:week` does that.

## Errors

If no priorities file exists yet, the script prints `(no current-priorities.md yet — <path>)`. Pass
that through and point at `/4loops:configure` (first run) or `/4loops:week` (armed, never oriented).
