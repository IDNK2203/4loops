# Beta walkthrough — 4loops as your dev friend would meet it

This is the *real* simulation: not script tests, but a believable solo-dev workspace you
open in Claude Code and drive with the live `/4loops:*` commands — the exact path a friend
you handed the plugin to would walk. Two sandboxes are already staged for you.

> **Why this loads the right version.** `--plugin-dir` makes the v2.2 branch **shadow** your
> globally-installed v2.0 for that session (verified against the CC docs) — only the branch's
> commands/hooks run, and your normal subscription auth stays intact. Nothing to disable.
> Edit a script mid-session? Run `/reload-plugins` to pick it up. Sandboxes live in `/tmp`,
> outside your real workspace — trash them anytime.

The mock workspace (both sandboxes): two real git repos — **web-app** + **api-service**
(detected as Projects, gated), a **docs/** Area (untracked, free to edit), and **study/**
(hard-exempt). It looks like a Tuesday on a real machine.

---

## Track A — the first hour (a brand-new user)  ·  sandbox `beta-fresh`

The honest onboarding: empty workspace, plugin silent, you run setup once.

```bash
cd /tmp/vt-sandbox-beta-fresh/workspace && claude --plugin-dir "$(cd ~/Ship/bls/projects/p0-vibe-table/vibe-table/plugin && pwd)"
```

Walk it as the friend:
1. **Notice it's silent.** No board, no nagging — 4loops does nothing until you opt in. (And nothing
   else works until you configure: every command requires `/4loops:configure` first.)
2. **`/4loops:configure`** — the one-time setup. Watch the checklist fill in. It detects
   `web-app` + `api-service` as Projects and `docs/` as an Area, asks you to confirm, pick a
   week-start, confirm what's gated — then asks **"what are your 3–5 anchors this week?"**
   Brain-dump a few. It spawns them and lands you on a **live board** — the aha is the filled board.
3. **Pin the board** when it tells you (open `.4loops/board.md`, pin the tab, ⌘K V for preview).
4. **Drive it:** `/4loops:today` to pick today's 1–3 focus, then **`/4loops:nav`** and just *talk*.
   Try editing `web-app/src/App.jsx` — allowed now (you reconciled).

**What you're judging:** does setup feel guided and fast? Does it end somewhere useful?

---

## Track B — a mid-week board (drive the real loop)  ·  sandbox `beta-day5`

A configured, mid-week workspace: stories across all five states, real deadlines (one overdue,
two due tomorrow), a ◆ modeling story — but **no focus set yet** (it's a fresh ISO week). This is
where you feel the *capabilities* and the *rules*.

```bash
cd /tmp/vt-sandbox-beta-day5/workspace && claude --plugin-dir "$(cd ~/Ship/bls/projects/p0-vibe-table/vibe-table/plugin && pwd)"
```

Walk it:
1. **Session start renders the board** + drift that **leads with overdue / due-soon**. Note ◆ on the
   modeling story and the `due:` dates.
2. **Hit the gate (the thesis).** Ask Claude to *edit* `web-app/src/components/Dashboard.jsx` (a gated
   Project) — don't pre-judge, let it try. The **PreToolUse hook denies it**. Now edit `docs/notes.md`
   → **allowed** (untracked Area); `study/reading.md` → always allowed (hard-exempt).
3. **Week before day (a rule).** Try **`/4loops:today`** first → it's **refused**: it's a new week, so
   `/4loops:week` must run first. Run `/4loops:week` (set 3–5 anchors), *then* `/4loops:today` (pick the
   day's 1–3). Retry the gated edit → now **allowed**.
4. **The headline — `/4loops:nav`, just talk.** Open it: it prints the **priority-annotated board**
   (★ focus · ! overdue · ⏳ due-soon · ◆ modeling — where you stand vs your day/week), then "what's
   changed?". Now talk:
   - *"the metrics endpoint is done, and start the pricing copy"* → two state moves, one re-render
   - *"new task: add rate limiting, due Friday, high priority"* → capture + focus
   - *"the request-logging task is dead"* → retired off the board into the archive
   - *"bump the metrics thing"* (ambiguous) → it asks **which** rather than guessing
5. **The lie test.** After it claims a move, run **`/4loops:board`** yourself — confirm the board
   actually changed. (It can't fake it: every move runs a rail and re-renders from disk, and the gate
   blocks hand-editing the board files.)

**What you're judging:** does talking-and-it-moves feel effortless and *trustworthy*? Does it ever
mis-map or invent? Does the gate feel like help or friction?

---

## The model (read this once)

**Two rituals on a rhythm; one conversation in between.** The four acts of the loop — capture · check ·
prioritize · review — you never have to name. You just:

- **`/4loops:week`** then **`/4loops:today`** — the rituals (review + reconcile). Structured see-then-pick.
- **`/4loops:nav`** — *everything in between, by talking.* New tasks, state moves, priority, retirements.

The rules that keep it honest:
- **You hold the key.** Every board-touching command is **user-invoked only** — Claude can't move your
  board on its own. Tell it "I finished the endpoint" in plain chat and it **won't** touch the board;
  the typed command is your consent.
- **Operate, never simulate.** `/nav` runs a real rail for every change and re-renders as proof; it
  can't fake a move and won't invent an ID — if it can't match what you said, it asks.
- **Config first · week before day.** Nothing works before `/configure`; `/today` is refused on a new
  week until `/week` runs.

> Hidden escapes exist (`/4loops:capture`, `:manage`, `:prioritize`) for direct use — but the normal
> path is just to talk in `/nav`.

## Sample inputs for `/nav` (copy-paste, then improvise)

Open `/4loops:nav`, then say things like — it infers project, type (`dev`/`modeling`), deadline, and
priority from how you phrase it:

```
the metrics endpoint 500s on empty ranges — fix before the demo tomorrow; also rewrite the pricing copy
new task: add rate limiting, due Friday, high priority
spike: should metrics be realtime or 1-min polled? decide before we build the endpoint   (→ ◆ modeling)
the request-logging task is dead                                                          (→ retire)
API-002 is superseded by the new caching task                                             (→ supersede)
bump the metrics thing                                                                    (→ it asks which)
```

It runs each on the rails and re-renders the annotated board as proof. New work lands in Backlog and
**doesn't** touch your focus unless you say so — priority stays yours.

## Reset / teardown

```bash
S=~/Ship/bls/projects/p0-vibe-table/vibe-table/sandbox/sandbox.sh
bash "$S" refresh beta-day5     # board back to seed (keeps the workspace)
bash "$S" expire  beta-day5     # backdate focus → next session's gate is ACTIVE (re-demo the block)
bash "$S" list                  # show sandboxes
bash "$S" rm beta-fresh         # delete one
```

Anything that feels off → note the step + what actually happened; it rides a fix commit on
`feat/v2-spine` (that's how the dense-grid drift bug got caught — in this exact harness).
