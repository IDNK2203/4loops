# Beta walkthrough — a full demo of 4loops, end to end

Not the script tests — a believable solo-dev workspace you open in Claude Code and drive with the live
`/4loops:*` commands, the way a friend you handed the plugin to would. It's simple to *use* (two rituals
+ just talk), but there's a lot of machinery under the hood; this walk makes all of it visible.

Two tracks, each a complete arc:
- **Track A — Day one:** install → configure → do a day's work → watch the gate block you and let you back in.
- **Track B — A new week, mid-flight:** open a populated board on a fresh week → week-before-day → run the loop by talking.

> **Why this loads the right version.** `--plugin-dir` makes the v2.2 branch **shadow** your globally-
> installed v2.0 for that session (verified vs the CC docs) — only the branch's commands/hooks run, and
> your subscription auth stays intact. Edit a script mid-session? `/reload-plugins`. Sandboxes live in
> `/tmp`, outside your real workspace — trash them anytime.

**The mock workspace** (both sandboxes): two real git repos — **web-app** + **api-service** (detected as
Projects, gated), a **docs/** Area (untracked, free to edit), and **study/** (hard-exempt). A real Tuesday.

> **Did the plugin load? (read this first.)** The launch command points `--plugin-dir` at the plugin
> folder *inline* — don't rely on a shell variable (an empty one silently loads nothing). After launch,
> type `/4loops` — you should see the menu: **`/4loops:today` · `:week` · `:nav` · `:board` · `:configure`**.
> Commands are namespaced — it's `/4loops:today`, **not** `/today`. If the menu is empty, the plugin
> didn't load: check the `--plugin-dir` path resolves and re-run.

---

## Track A — Day one (install → configure → work → the gate)  ·  `beta-fresh`

A brand-new, empty workspace. This arc shows the **full gate lifecycle**: reconciled = you flow freely;
stale = you're blocked until you reconcile.

```bash
cd /tmp/vt-sandbox-beta-fresh/workspace && claude --plugin-dir ~/Ship/bls/projects/p0-vibe-table/vibe-table/plugin
```

**1. It's silent.** No board, no nagging — and nothing works yet: every command requires `/configure`
first (try `/4loops:today` → it tells you to configure). *Showcases: config-first.*

**2. `/4loops:configure`** — the one-time setup. Watch the 7-step checklist fill in. It detects
`web-app` + `api-service` as **Projects** (git repos) and `docs/` as an **Area** (untracked); you confirm,
pick a week-start, confirm the gated set, then brain-dump **3–5 anchors for the week**. It spawns them,
sets week + today focus, and lands you on a live board. *Showcases: detection, Project/Area split, gated
config, bootstrap — the aha is a board full of your work.*

**3. Pin the board** when it tells you (`.4loops/board.md`, pin the tab, ⌘K V for preview).

**4. You just reconciled, so you can work.** Ask Claude to **edit `web-app/src/components/Dashboard.jsx`**
(a gated Project file) → **allowed** (today's focus is fresh). Edit `docs/notes.md` → allowed (Area). Edit
`study/reading.md` → allowed (hard-exempt). *Showcases: the gate is satisfied; Project vs Area vs exempt.*

**5. Do a day's work — just talk in `/4loops:nav`.** Open it (it prints the priority-annotated board),
then speak as the day unfolds:
- *"new task: add a health-check endpoint to the api, due tomorrow"* → captures (API, dev, deadline)
- *"start the dashboard panel"* → moves it to In Progress
- *"the auth refactor spike — capture it, it's a modeling task"* → captures as ◆ modeling
- *"actually the health-check is done"* → moves it to Done
- *"drop the pricing-copy task"* → retires it into the archive

Each runs on the rails and re-renders as proof. *Showcases: `/nav` capture + move + prioritize + retire,
type/deadline inference, operate-never-simulate.*

**6. End of day → next morning (simulate expiry).** Quit the session. Backdate today's focus so tomorrow
it reads stale — the gate goes live:
```bash
bash ~/Ship/bls/projects/p0-vibe-table/vibe-table/sandbox/sandbox.sh expire beta-fresh
```
Reopen a **fresh session**:
```bash
cd /tmp/vt-sandbox-beta-fresh/workspace && claude --plugin-dir ~/Ship/bls/projects/p0-vibe-table/vibe-table/plugin
```

**7. The gate blocks you (the thesis).** The sentinel renders the board and flags stale focus. Ask Claude
to edit `web-app/src/components/Dashboard.jsx` → **DENIED** — today's focus is stale, reconcile first.
Note: `docs/` and `study/` still edit fine (Areas / exempt never block). *Showcases: the hard gate, and
that it only guards your Projects.*

**8. Reconcile → flow returns.** Run `/4loops:today` (week is still current from yesterday, so no
week-first block here), pick today's focus → the gate lifts. Retry the gated edit → **allowed**. *Showcases:
the daily ritual clears the gate; the loop pays for itself.*

> **One-off escape:** if you ever need to bypass without reconciling, prefix the action with
> `VT_ALLOW_STALE_GATE=1` — it's allowed once and **logged** to `.4loops/override.log`. (Confirm it works,
> then confirm the log entry.)

**Judging Track A:** does setup feel fast and end somewhere useful? Does the block feel like help, not
nagging? Does talking in `/nav` feel effortless *and* trustworthy?

---

## Track B — A new week, mid-flight (render → week-before-day → `/nav`)  ·  `beta-day5`

A configured, populated board — stories across all five states, real deadlines (one overdue, two due
soon), a ◆ modeling story — but **no focus set, on a fresh ISO week**. You're picking the week back up.
(Think: starting the week on a board that's already full — so the week ritual comes first.)

```bash
cd /tmp/vt-sandbox-beta-day5/workspace && claude --plugin-dir ~/Ship/bls/projects/p0-vibe-table/vibe-table/plugin
```

**1. The board renders itself.** SessionStart sentinel prints the dashboard; **drift leads with overdue /
due-soon**, ◆ marks the modeling story, cells show `due:` dates. *Showcases: session orientation, drift-as-
honesty, deadline surfacing.*

**2. Week before day (the cadence rule).** Try `/4loops:today` first → **refused**: it's a new week, run
`/4loops:week` first. Run **`/4loops:week`** — see-then-pick the done / commit-this-week / **retire** groups,
set 3–5 anchors. Then **`/4loops:today`** → pick the day's 1–3; the gate lifts. *Showcases: week-before-day
enforced, the two structured rituals, the Retire group (abandon / supersede).*

**3. Run the loop by talking — `/4loops:nav`.** It opens on the **priority-annotated board**
(★ focus · ! overdue · ⏳ due-soon · ◆ modeling — "where am I vs my day/week," not the raw grid), then
"what's changed?". Throw the day at it:
- *"the metrics endpoint is done, and start the pricing copy"* → two moves, one re-render
- *"new task: add rate limiting, due Friday, high priority"* → capture + focus
- *"bump the metrics thing"* (two match) → it **asks which**, doesn't guess
- *"the request-logging task is dead"* → retired into `archive/<month>/abandoned.md`
- *"API-002 is superseded by a caching task that doesn't exist yet"* → it **refuses to invent the ID**,
  offers to capture it first

**4. The lie test.** After any claimed move, run `/4loops:board` yourself → the board *actually* changed.
It can't fake it (every move runs a rail + re-renders from disk; the gate blocks hand-editing the records).

**Judging Track B:** does the week→day order feel natural? Does the annotated board answer "where am I"?
Does `/nav` ever mis-map or invent — or does it stay honest?

---

## Capabilities this demo covers (tick them off)

The two tracks above hit all of these — use this as the demo's coverage map:

| Capability | Where | Watch for |
|---|---|---|
| Config-first | A1 | command refuses before `/configure` |
| Project detection (git) + Area split | A2 | web-app/api-service = Projects, docs = Area |
| Gated config + bootstrap | A2 | board ends full of *your* anchors |
| Gate satisfied → free edits | A4 | gated edit allowed right after reconcile |
| Project vs Area vs hard-exempt | A4, A7 | Projects block when stale; Areas/study never |
| `/nav` capture (type + deadline inference) | A5, B3 | "due Friday" → date; "spike" → ◆ modeling |
| `/nav` move state · prioritize · retire | A5, B3 | each re-renders as proof |
| Expiry → gate blocks | A6–A7 | denied edit on stale focus |
| Daily reconcile lifts gate | A8 | retry edit now allowed |
| One-off override (logged) | A7 note | `VT_ALLOW_STALE_GATE=1` + `override.log` |
| Session orientation + drift | B1 | overdue/due-soon lead, ◆ shown |
| **Week-before-day** | B2 | `/today` refused → `/week` first |
| Two structured rituals (see-then-pick) | B2 | tick groups, no per-story typing |
| Retire: abandon / supersede / backdate | B2, B3 | leaves grid → archive |
| Priority-annotated board (★/!/⏳/◆) | B3 | "where am I vs day/week" |
| Operate-never-simulate (ask, don't invent) | B3 | refuses bad ID; asks on ambiguity |
| The lie test (board is source of truth) | B4 | `/board` confirms real change |
| User-only (Claude won't move it itself) | any | plain-chat "mark X done" → it declines |

**Worth confirming if you want full coverage** (not on the critical path): re-running `/4loops:configure`
is idempotent (keys replaced, projects upserted); `/4loops:board` slices (`--list`, a single state, a
`--project`); a `--backdate` capture records on its real date; the weekly rollover auto-archives Done at
the first session of a new ISO week (the sentinel does it once, idempotently).

---

## Reset / teardown

```bash
S=~/Ship/bls/projects/p0-vibe-table/vibe-table/sandbox/sandbox.sh
bash "$S" refresh beta-day5     # board back to seed (keeps the workspace)
bash "$S" expire  beta-fresh    # backdate Today's focus → next session's gate is ACTIVE (re-demo the block)
bash "$S" list                  # show sandboxes
bash "$S" new --light --empty beta-fresh   # recreate the onboarding sandbox if you trashed it
bash "$S" rm beta-fresh         # delete one
bash "$S" prune                 # delete ALL sandboxes (clean up dead workspaces)
```

> These `--light` sandboxes live under `/tmp`, so they're disposable by nature — macOS clears `/tmp` on
> reboot. `prune` is just the on-demand version; nothing here touches your real workspace.

Anything that feels off → note the step + what actually happened; it rides a fix commit on
`feat/v2-spine` (that's how the dense-grid drift bug got caught — in this exact harness).
