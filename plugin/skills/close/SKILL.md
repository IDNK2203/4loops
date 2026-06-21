---
name: close
description: End-of-day / end-of-week close. `/close` prints a drift report as a retro prompt (no mutation). `/close --weekly` force-runs the weekly rollover (Done → archive/closed, abandoned → archive/abandoned) — this normally auto-fires on the first session of a new ISO week, so use the flag only to run it early or re-confirm.
allowed-tools: Bash
user-invocable: true
---

Close out the day or week.

## Usage

- `/close` — daily close: surfaces drift as a retro prompt; archives nothing.
- `/close --weekly` — force the weekly rollover now (idempotent — no-op if it already ran this ISO week).

## Steps

### Daily (`/close`)

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-close.sh"
```

Pass the drift report through. Optionally ask the user for a one-line retro and note it in the conversation (no file mutation in v1). No board changes.

### Weekly (`/close --weekly`)

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/vt-close.sh" --weekly
```

Echo the rollover summary (`N closed, N abandoned → archive/YYYY-MM/`). This normally fires automatically at the first session of a new ISO week (the sentinel does it); the flag is only for running it early or re-confirming. The archive is append-only under `.4loops/archive/` and reversible.

## Notes

- Daily close never archives — only the weekly rollover moves items off the board.
- Abandoned candidates (non-done stories untouched ≥ ~3 weeks) go to `abandoned.md`, NOT `closed.md`, so the archive stays honest for `/recall`.
