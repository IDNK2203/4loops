# Beta walkthrough — 4loops as your dev friend would meet it

This is the *real* simulation: not script tests, but a believable solo-dev workspace you
open in Claude Code and drive with the live `/4loops:*` commands — the exact path a friend
you handed the plugin to would walk. Two sandboxes are already staged for you.

> **Why this loads the right version.** `--plugin-dir` makes the v2.1 branch **shadow** your
> globally-installed v2.0 for that session (verified against the CC docs) — only v2.1's
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
1. **Notice it's silent.** No board, no nagging — 4loops does nothing until you opt in. (Good first impression: it's not noisy.)
2. **`/4loops:configure`** — the one-time setup. Watch the checklist fill in. It detects
   `web-app` + `api-service` as Projects and `docs/` as an Area, asks you to confirm, pick a
   week-start, confirm what's gated — then asks **"what are your 3–5 anchors this week?"**
   Brain-dump a few (e.g. `WA: wire up the dashboard`, `AS: metrics endpoint`, `WA: pricing copy`).
   It spawns them and lands you on a **live board** — the aha is the filled board, not a tour.
3. **Pin the board** when it tells you (open `.4loops/board.md`, pin the tab, ⌘K V for preview).
   The whole loop assumes the board is glanceable.
4. **Drive the loop:** `/4loops:today` to pick today's 1–3 focus. Try editing `web-app/src/App.jsx`
   — allowed now (you reconciled). That's the daily rhythm.

**What you're judging:** does setup feel guided and fast? Does it end somewhere useful? Would
your friend know what to do next without reading docs?

---

## Track B — a mid-week board (drive the real loop)  ·  sandbox `beta-day5`

Day 5: the board's already full — stories across all five states, real deadlines (one overdue,
two due tomorrow), a ◆ modeling story. This is where you feel the *capabilities*.

```bash
cd /tmp/vt-sandbox-beta-day5/workspace && claude --plugin-dir "$(cd ~/Ship/bls/projects/p0-vibe-table/vibe-table/plugin && pwd)"
```

Walk it:
1. **Session start renders the board** + a drift line that **leads with overdue / due-soon**
   (`Ship dashboard v0.1` is overdue; two stories due tomorrow). Note ◆ on the modeling story
   and the `due:` dates on cells.
2. **Hit the gate (the thesis).** Ask Claude to *edit* `web-app/src/components/Dashboard.jsx`
   (a gated Project). Don't pre-judge — let it try. The **PreToolUse hook denies it**: the board
   isn't reconciled for today. Now edit `docs/notes.md` → **allowed** (untracked Area). Edit
   `study/reading.md` → always allowed (hard-exempt). *Feel the Project/Area line.*
3. **Reconcile — see, then pick.** Run **`/4loops:week` first** (fresh board = new ISO week),
   then **`/4loops:today`**. The board prints **once**, then you get **structured multi-select**
   (started / done / **retire**) — you tick what moved, no prose, no typing `/start` per story.
   Set your focus.
4. **Retry the gated edit, same session → now allowed.** The discipline paid for itself.
5. **Capture a brain-dump:** `/4loops:arrange "fix the flaky CI, draft the launch thread, start the demo video"`
   → it proposes ~3 stories with inferred **type + deadline** and drafts them on your confirm.
   It never sets your priority — that stays yours.
6. **Honest ending:** in `/4loops:week`, use the **Retire** group to abandon or supersede a dead
   story — it leaves the grid into `archive/<month>/abandoned.md`. (There's no `/archive` command
   anymore — retiring lives inside the reconcile, V9.)

**What you're judging:** is the see-then-pick faster than typing commands? Does drift surface the
*right* urgency? Does the gate feel like help or friction? Is retiring work obvious?

---

## How state actually moves (read this once)

There is **no `/transition` or `/done` command** — and that's the design, not a gap. Only four
commands touch the board, and each has one job:

- **`/4loops:arrange`** — *capture only.* Adds NEW stories to Backlog. Never moves state, never
  sets priority. (So a brain-dump can't quietly reshuffle your board.)
- **`/4loops:today` / `/4loops:week`** — *move state.* You see the board, then **pick** what
  started / finished / parks in a structured menu. This is where stories change columns.
- **`/4loops:priority`** — *quick in-between.* Bump today's focus or nudge a single story when
  something lands between rituals.

If you tell Claude "I finished the endpoint" in plain chat, it **won't** silently move it — the
board only moves when you run one of these. The command is your consent.

## Sample inputs (copy-paste, then improvise)

**Capture a brain-dump** — `/4loops:arrange` takes plain language; it infers project, type, and deadline:
```
/4loops:arrange the metrics endpoint 500s on empty ranges — fix before the dashboard demo tomorrow.
    also need to rewrite the pricing copy, and start sketching the demo video.
/4loops:arrange spike: should metrics be realtime or 1-min polled? decide before we build the endpoint
/4loops:arrange flaky CI run keeps failing on the e2e step, and add request logging to the api
```
→ It proposes ~3 stories with type (`dev`/`modeling`) + a deadline where you implied one, and drafts
them on your confirm. It does **not** set what you work on next.

**Daily reconcile** — `/4loops:today`. The board prints once, then you answer structured picks. Your
free-text moments are only the focus answer, e.g.:
```
/4loops:today
   → (tick) Started: WEB-002 pricing copy
   → (tick) Now done: API-001 metrics endpoint
   → focus today: WEB-001, API-002
```

**Quick mid-day nudge** — `/4loops:priority` (lighter than the full walk):
```
/4loops:priority                 # show what's shifted since you set focus, then pick
/4loops:priority add API-004     # add a story to today's focus, no menu
/4loops:priority set WEB-001 API-001   # replace today's focus wholesale
/4loops:priority since           # just list what's landed since your last focus
```

**Weekly reconcile** — `/4loops:week` (run first on a new week). Structured picks again:
```
/4loops:week
   → (tick) Now done: API-003 CI
   → (tick) Commit this week: WEB-002, API-002
   → (tick) Retire → superseded: WEB-005 (replaced by WEB-002)
   → anchors this week: WEB-001, API-001, API-002
```

**Retire dead work** — there's no `/archive`; it lives in the `/week` "Retire" group (or quick via
`/priority`). Pick `abandon` (dropped) or `superseded` (name the story that replaced it) → it leaves
the grid into `archive/<month>/abandoned.md`.

> The pattern to internalize: **`/arrange` to get work IN, the reconcilers to move it ALONG.** You
> never type a per-story state command — you see the board and pick.

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
