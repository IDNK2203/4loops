# Closeout walkthrough — one sandbox, two stories

A single live pass that signs off **both** stories currently in Testing:

- **P0-014 (Sandbox script)** — the live `B1–B5` rail proof + install-UX.
- **P0-015 (Configuration & Onboarding)** — silent virgin → `/vt:configure` → bootstrap.

The merge: one `--empty --light` sandbox. `/vt:configure` fills the board (P0-015); then `sandbox.sh expire` flips that *same* reconciled board stale so the rail block (B1) is demoable — no separate `--seeded` sandbox needed.

Walk it once, tick the boxes, and both stories are done. Budget ~15 min.

---

## Setup

```bash
sandbox/sandbox.sh new --light --empty closeout
```

It prints one launch line: `cd <workspace> && claude --plugin-dir <plugin>`. `--light` points Claude straight at the plugin folder using your real login — no install, no marketplace, no `$HOME` override. It validates everything about whether the plugin **works**: silence in a virgin dir, `/vt:configure`, and the rail (B1 / B2 / B3 / B5).

> **B4 (install/update machinery) is deferred to ship — see Act III.** `--light` never installs (it points at the live folder), so there's no marketplace cache to test. That pass happens for real once the repo is on GitHub.

---

## Act I — Onboarding (P0-015) + install-UX & silence (P0-014)

1. **Skills + hooks load.** Launch with the printed `--plugin-dir` line. Confirm `/vt:*` skills appear and the 4 hooks are active (the SessionStart sentinel, the two PreToolUse gates, the prompt gate). (The *marketplace install* form of this is the ship-time pass — Act III.)
   - [ ] **P0-014 · skills/hooks load** — `/vt:*` present, hooks firing.
2. **Silent in a virgin workspace.** `cd` into the workspace (no `.vibe-table/` yet) and launch. The sentinel must be **silent** — no dashboard, no stderr.
   - [ ] **P0-015 · silent virgin** & **P0-014 · #1 silence** — nothing renders in a non-VT dir.
3. **`/vt:configure`.** Run it. It should:
   - detect the mock tree's gated surfaces (`projects/*/content/*`, `projects/*/gists/*`) and let you trim/add,
   - ask which projects + an editable prefix, and a week-start (Mon/Sun),
   - then **bootstrap**: ask your 3–5 anchors (free text), spawn them to the board, ask which you're doing today (multiSelect), and end on a **filled board** with the rail armed and today+week focus set.
   - [ ] **P0-015 · configure+bootstrap** — board ends full of *your* anchors, not a template.
   - [ ] **P0-014 · B5 (multiSelect)** — the "which today?" multiSelect rendered and its labels mapped back to story IDs.
4. **First render (B3).** Start a **new session** in the workspace. The premium dashboard renders on its own lines (`·` header, counts, Today/Week focus).
   - [ ] **P0-014 · B3** — sentinel dashboard renders (cwd = workspace root).

## Act II — The rail (P0-014 B1 / B2)

5. **Reconciled board lifts the gate.** The board is fresh (you just configured). Ask Claude to **attempt** an Edit to `projects/acme-demo/content/post.md` — it should be **ALLOWED** (reconciled today). Edit `study/notes.md` → allowed (exempt).
   - [ ] gated edit allowed on a reconciled board; exempt always allowed.
6. **Flip it stale, then prove the block (B1 — the thesis).** In another terminal:
   ```bash
   sandbox/sandbox.sh expire closeout
   ```
   Back in a session, ask Claude to **attempt** the same Edit to `projects/acme-demo/content/post.md` (don't let it pre-judge — make it run the Edit). The PreToolUse hook must **deny** it. Then drop `jq` off `PATH` and retry to confirm the `exit 2` fallback also blocks.
   - [ ] **P0-014 · B1** — CC hard-blocks the gated Edit (and the no-jq fallback blocks too).
   - [ ] exempt `study/notes.md` still allowed while gated.
7. **Lift it, same session (B2 — the session-id handshake).** Run `/vt:today`, reconcile (you'll see the **4-group** multiSelect: starting / →testing / done / park), set focus. Immediately retry the gated Edit → it **must** be **ALLOWED** in the same session.
   - [ ] **P0-014 · B2** — `/vt:today` lifts the gate for the same session (no re-block loop).
   - [ ] **P0-014 · B5** — 4-group reconcile renders; selections map to IDs; Skip leaves the gate active.

## Act III — Install machinery (P0-014 B4) — deferred to ship (P0-011)

B4 ("does bumping the version + reinstalling propagate new hooks past the cache?") only exists once the plugin is genuinely **installed** from a marketplace — which `--light` deliberately skips. We test it for real at publish time:

> Push the repo to GitHub → in a fresh test workspace: `claude plugin marketplace add idnk2203/vibe-table` → `claude plugin install vt` (this is the real install-UX, exactly as a stranger sees it) → edit a hook header, bump `version` in **both** manifests (`plugin/.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json`) → `/plugin update` + `/reload-plugins` → new session → confirm the new header runs.

- [ ] **P0-014 · B4 (ship-gate, not now)** — carried into P0-011's pre-ship checklist.

## Act IV — Robustness (optional, P0-014 #9)

9. Break the board separator (`| --- | … |` → `| - | … |`) → new session → confirm `[WARN] board.md looks malformed`. Put a `|` in a story title → run `/vt:close --weekly` → inspect the archive record (known limitation until ship).

---

## Capture + signoff

Per step: `#<step> · <expected> · <actual> · PASS/FAIL/SURPRISE · <note>`. Log into `stories/vibe-table/02-sandbox/RESULTS.md` (P0-014) and `03-onboarding/` (P0-015). Any FAIL/SURPRISE → fix before closing.

**Signoff map**

| Story | Closes when these pass |
| --- | --- |
| **P0-015** | Act I · steps 2 (silent), 3 (configure+bootstrap) |
| **P0-014** | Act I · steps 1 (skills/hooks), 3 (B5), 4 (B3) · Act II · 6 (B1), 7 (B2/B5) |

**B4** is the one carry-over: it can't be tested without a real marketplace install, so it rides P0-011's pre-ship checklist (Act III). P0-014 closes on B1/B2/B3/B5 here; B4 is signed off at publish.

All green → `/vt:done P0-014` and `/vt:done P0-015`. Then tear down: `sandbox/sandbox.sh rm closeout`.
