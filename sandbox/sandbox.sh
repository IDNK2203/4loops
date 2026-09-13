#!/usr/bin/env bash
# sandbox.sh — disposable clean-room workspaces to dogfood 4loops as a fresh user.
#
# Two modes (config fidelity × persistence) and two install paths — see sandbox/README.md.
#   --light     ephemeral /tmp + real config (--plugin-dir). Fast inner loop.
#   --isolated  persistent ~/Ship/vt-sandbox + hermetic. The true fresh-user env. (default)
#     · settings injection (default): claude --bare --settings … (no cache/version machinery)
#     · --real-install: genuine marketplace add + install via $HOME override (tests install-UX + B4)
#
# Each sandbox carries a mock project tree whose gated paths match vt's real default
# globs, so the rail (B1) has real targets. Seeding drives the REAL vt CLI.
set -euo pipefail

# ── Paths ─────────────────────────────────────────────────────────────────────
SANDBOX_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO="$( cd "$SANDBOX_DIR/.." && pwd )"
PLUGIN_DIR="$REPO/plugin"
PLUGIN_SCRIPTS="$PLUGIN_DIR/scripts"
TMP_BASE="/tmp"
PERSIST_BASE="$HOME/Ship/vt-sandbox"
MARKETPLACE="4loops"   # must match .claude-plugin/marketplace.json "name"

# ── Defaults (set by parse_new_args) ────────────────────────────────────────────
# Default to --light: it keeps your real auth (no --bare → keychain/OAuth intact),
# and since sandboxes live OUTSIDE your project tree, other workspace hooks don't load.
# --isolated (--bare) is hermetic but SKIPS OAuth/keychain → needs ANTHROPIC_API_KEY.
MODE=light
INSTALL=inject     # inject | real | "" (light)
EMPTY=false
NAME=""

die() { printf 'sandbox: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
sandbox.sh — clean-room workspaces for dogfooding 4loops

USAGE
  sandbox.sh demo <a|b|c> [--no-launch] [--bypass] [--midweek]   ONE-SHOT: build a fresh, uniquely-named
                                 sandbox — a = empty (onboarding), b = seeded mid-week board,
                                 c = b + store (levers) + a prior Week at cap + yesterday's Today ⊆ week (Packet 006 one-shot /week)
                                 (both stale → week→week and day→day carry-forward visible), for the
                                 v2.5 Real C orientation loop (/week → /today → /prioritize) —
                                 and launch Claude in it. No prior workspace needed — run any time.
                                 --bypass launches with VT_ALLOW_STALE_GATE=1 (gate OFF, user-only).
                                 --midweek (demo c only) keeps the Week stamp on the CURRENT ISO
                                 week and staleness on Today alone → /4loops:week opens in
                                 follow-up mode, look-back = since yesterday (the Tue+ shape).
  sandbox.sh new [--light|--isolated] [--real-install] [--empty|--seeded] [name]
  sandbox.sh relaunch [name] [--bypass]   reopen a sandbox in a fresh Claude session (default:
                                 latest). --bypass = VT_ALLOW_STALE_GATE=1 in the env (gate OFF).
  sandbox.sh refresh <name>      reset the board to seed (keeps the workspace)
  sandbox.sh expire [name]       backdate Today's focus → flips the gate ACTIVE (default: latest)
                                 (demo the B1 rail block on a live, reconciled board)
  sandbox.sh list                show all sandboxes
  sandbox.sh rm <name>           delete a sandbox
  sandbox.sh prune               delete ALL sandboxes (clean up dead workspaces)

MODES
  --isolated   (default) persistent ~/Ship/vt-sandbox/<name>, hermetic. True fresh-user env.
  --light      ephemeral /tmp/vt-sandbox-<name>, real config (--plugin-dir). Fast iteration.

INSTALL (isolated only)
  (default)        settings injection — claude --bare --settings. Tests runtime B1/B2/B3/B5.
  --real-install   real marketplace add+install via $HOME override. Tests install-UX + B4.

SEED
  --seeded     (default) stories across states + pre-armed rail + stale focus (B1 demoable now)
  --empty      virgin workspace (no board) — walk /4loops:configure → /4loops:week → /nav from scratch
EOF
}

# ── Sandbox location + discovery ─────────────────────────────────────────────────
sandbox_root() {  # <mode> <name>
  case "$1" in
    light)    printf '%s/vt-sandbox-%s' "$TMP_BASE" "$2" ;;
    isolated) printf '%s/%s' "$PERSIST_BASE" "$2" ;;
  esac
}

find_sandbox() {  # <name> → echo root, or return 1. Require the .sandbox-meta marker
                  # (not bare dir existence) so a stale config-only dir left by an aborted
                  # real-install can't shadow the real sandbox at the other location.
  [ -f "$PERSIST_BASE/$1/.sandbox-meta" ]        && { printf '%s' "$PERSIST_BASE/$1"; return 0; }
  [ -f "$TMP_BASE/vt-sandbox-$1/.sandbox-meta" ] && { printf '%s' "$TMP_BASE/vt-sandbox-$1"; return 0; }
  return 1
}

# Echo the root of the most-recently-created sandbox (by marker mtime), or return 1.
# Lets `expire` / `relaunch` default to "the one you just used" — no name to remember.
latest_sandbox() {
  local d t best=0 newest=""
  for d in "$PERSIST_BASE"/*/ "$TMP_BASE"/vt-sandbox-*/; do
    [ -f "${d}.sandbox-meta" ] || continue
    t=$(stat -f %m "${d}.sandbox-meta" 2>/dev/null || stat -c %Y "${d}.sandbox-meta" 2>/dev/null || echo 0)
    [ "$t" -gt "$best" ] && { best="$t"; newest="${d%/}"; }
  done
  [ -n "$newest" ] && { printf '%s' "$newest"; return 0; }
  return 1
}

# ── Builders ──────────────────────────────────────────────────────────────────
scaffold_mock() {  # <workspace> — a realistic solo-dev machine, NOT a toy. vt-detect runs in
  local ws="$1"    # "workspace mode": top-level GIT REPOS become Projects (so /configure has
                   # real things to find), a non-git folder is an Area, study/ is hard-exempt.
                   # Gated-ness comes from the PATH (matches vt's default globs), NOT the content —
                   # keep files NEUTRAL (no "this is gated" meta-text, or the model self-refuses by
                   # reading instead of attempting the edit and letting the rail decide).

  # ── web-app — frontend repo (a real .git → detected as a Project) ──
  mkdir -p "$ws/web-app/src/components" "$ws/web-app/public"
  printf '# web-app\n\nMarketing site + customer dashboard. React + Vite.\n' > "$ws/web-app/README.md"
  printf '{\n  "name": "web-app",\n  "version": "0.1.0",\n  "type": "module"\n}\n' > "$ws/web-app/package.json"
  printf 'import { Dashboard } from "./components/Dashboard";\n\nexport default function App() {\n  return <Dashboard />;\n}\n' > "$ws/web-app/src/App.jsx"
  printf 'export function Dashboard() {\n  // TODO: wire up the live metrics panel\n  return <div className="dashboard">metrics go here</div>;\n}\n' > "$ws/web-app/src/components/Dashboard.jsx"
  ( cd "$ws/web-app" && git init -q )

  # ── api-service — backend repo (second Project) ──
  mkdir -p "$ws/api-service/src/routes"
  printf '# api-service\n\nNode/Express API behind the dashboard.\n' > "$ws/api-service/README.md"
  printf 'import express from "express";\nconst app = express();\napp.get("/health", (_req, res) => res.json({ ok: true }));\napp.listen(3000);\n' > "$ws/api-service/src/server.js"
  printf 'import { Router } from "express";\nexport const metrics = Router();\n// TODO: the dashboard is blocked on this aggregation endpoint\nmetrics.get("/", (_req, res) => res.json([]));\n' > "$ws/api-service/src/routes/metrics.js"
  ( cd "$ws/api-service" && git init -q )

  # ── docs — a non-git Area: evolving notes, no done-state → untracked, always free to edit ──
  mkdir -p "$ws/docs"
  printf '# Product notes\n\nRolling scratchpad.\n\n- realtime vs 1-min-polled metrics? (decide before the endpoint)\n- pricing page copy needs a rewrite\n' > "$ws/docs/notes.md"

  # ── study — hard-exempt by default (research is never gated, even mid-project) ──
  mkdir -p "$ws/study"
  printf '# Study\n\nReading + research links. Always writable, gate or no gate.\n' > "$ws/study/reading.md"
}

seed_board() {  # <vt_dir> — drive the REAL vt CLI so seeding exercises it too. v2.1-rich:
  local vtdir="$1"  # types (dev/modeling) + deadlines (computed relative to today, so overdue /
  local d_over d_soon d_wk d_next d_stale  # due-soon ALWAYS fire) + a spread across the four active states.
  d_over=$(date -v-3d  +%F 2>/dev/null || date -d '3 days ago' +%F)  # already overdue
  d_soon=$(date -v+1d  +%F 2>/dev/null || date -d '1 day'      +%F)  # due tomorrow (due-soon)
  d_wk=$(  date -v+5d  +%F 2>/dev/null || date -d '5 days'     +%F)  # later this week
  d_next=$(date -v+12d +%F 2>/dev/null || date -d '12 days'    +%F)  # next sprint
  d_stale=$(date -v-9d +%F 2>/dev/null || date -d '9 days ago'  +%F)  # past the 7d Done dwell
  # VT_DIR_QUIET: the seed deliberately points VT_DIR at the sandbox from wherever you ran
  # this script, so the "records are elsewhere" warning is expected noise here — suppress it.
  draft() { VT_DIR="$vtdir" VT_DIR_QUIET=1 bash "$PLUGIN_SCRIPTS/vt-draft.sh"      "$@" >/dev/null; }
  move()  { VT_DIR="$vtdir" VT_DIR_QUIET=1 bash "$PLUGIN_SCRIPTS/vt-transition.sh" "$@" >/dev/null; }

  # web-app (prefix WEB) — IDs land WEB-001..003 in draft order
  draft WEB "Wire up the live metrics panel" "dashboard shell is empty"  "web-app/src/components/Dashboard.jsx" --deadline "$d_soon"
  draft WEB "Rewrite the pricing page copy"  ""                          "docs/notes.md"                       --deadline "$d_next"
  draft WEB "Ship dashboard v0.1"            "first usable cut"          ""                                    --deadline "$d_over"
  # api-service (prefix API) — IDs land API-001..004
  draft API "Add metrics aggregation endpoint" "the dashboard is blocked on this" "api-service/src/routes/metrics.js" --deadline "$d_soon"
  draft API "Decide realtime vs polled metrics" "shapes the whole data path" "docs/notes.md" --type modeling --deadline "$d_wk"
  draft API "Set up CI"                         ""                              ""              --deadline "$d_wk"
  draft API "Add request logging"

  # spread across the ACTIVE pipeline — a believable mid-week board (planning·in-progress·testing·done).
  # vt-draft lands every story in Planning; there is no Backlog column to dump into.
  move WEB-001 in-progress   # due-soon, actively being worked
  move WEB-003 testing       # OVERDUE + in Testing — a real "deadline slipped" signal
  move API-001 in-progress   # due-soon, the blocker
  move API-003 done          # CI shipped
  # API-004 went Done nine days ago — past the 7d dwell, so `/manage flush` has
  # something ripe to archive while API-003 (today) is still dwelling. Track D demo.
  move API-004 done --backdate "$d_stale"

  # Write a REAL config so the seeded sandbox is an already-configured day-5 workspace
  # (names the projects, sets week-start + gated globs) — otherwise /today/week/task-nav
  # hit UNCONFIGURED and the gate can't enforce.
  cfg() { VT_DIR="$vtdir" VT_DIR_QUIET=1 bash "$PLUGIN_SCRIPTS/vt-config.sh" "$@" >/dev/null; }
  cfg project WEB "web-app"     web-app
  cfg project API "api-service" api-service
  cfg week-start mon
  cfg gated "web-app/*" "api-service/*"

  : > "$vtdir/.armed"   # pre-arm: armed + stale focus = gate active, so B1 is demoable immediately
}

seed_store() {  # <vt_dir> [midweek] — v2.5 Packet 006: a lived-in detached store + a PRIOR Week (last
  local vtdir="$1" midweek="${2:-0}" d_yest d_due dow left lw d_lw  # week) + a stale (yesterday) Today ⊆ that week, so the
  d_yest=$(date -v-1d +%F 2>/dev/null || date -d 'yesterday' +%F)   # one-shot /week opens on a real look-back.
  # Due date INSIDE the current ISO week (Mon start): +2d, clamped to the week's end; on a
  # Sunday that is today itself (due-by is inclusive), so "due this week" is never empty.
  dow=$(date +%u); left=$((7 - dow)); [ "$left" -gt 2 ] && left=2
  d_due=$(date -v+"${left}"d +%F 2>/dev/null || date -d "${left} days" +%F)
  lw=$(date -v-7d +%V 2>/dev/null || date -d '7 days ago' +%V)      # last ISO week number
  d_lw=$(date -v-7d +%F 2>/dev/null || date -d '7 days ago' +%F)
  cap() { printf '%s\n' "$1" | VT_DIR="$vtdir" VT_DIR_QUIET=1 bash "$PLUGIN_SCRIPTS/vt-store-capture.sh" >/dev/null; }
  cap "$(printf 'WEB\tFix the login redirect loop\tdev\tsupport thread\turgent')"         # CAP-001 urgent
  cap "$(printf 'API\tRate-limit the metrics endpoint\tdev\tnoisy client\ttoday')"        # CAP-002 today
  cap "$(printf 'WEB\tDraft the launch email\tdev\tmarketing asked\t%s' "$d_due")"         # CAP-003 later, due this week
  cap "$(printf 'API\tSpike: OpenTelemetry vs homegrown tracing\tmodeling\t\t')"          # CAP-004 later
  cap "$(printf 'WEB\tClean up the old dashboard branch\tdev\t\t')"                       # CAP-005 later
  VT_DIR="$vtdir" VT_DIR_QUIET=1 bash "$PLUGIN_SCRIPTS/vt-store-expire.sh" --activate-only >/dev/null
  # PRIOR week (5 = at the cap: 4 still open + API-003 already Done → [x]) and yesterday's Today
  # (2, both on the week — today ⊆ week). Written through the real one-shot rail, then BACKDATED:
  # Week → last ISO week, Today → yesterday. Both stale ⇒ the orientation gate is ACTIVE on
  # launch, and /week opens on "last week: 1 done · 4 carried" with 1 slot free (cap 5).
  VT_DIR="$vtdir" VT_DIR_QUIET=1 bash "$PLUGIN_SCRIPTS/vt-week.sh" set WEB-001 API-001 WEB-003 API-003 CAP-001 --today WEB-001 API-001 >/dev/null 2>&1
  # Today is ALWAYS backdated to yesterday (stale ⇒ gate active). The WEEK stamp is the
  # variant switch:
  #   default   → backdate the week to last ISO week ⇒ MODE new-week, look-back = last week.
  #   --midweek → leave the week on the CURRENT ISO week ⇒ MODE follow-up ("not Monday"),
  #               look-back = since yesterday, not a week dump. This is the Tue+ shape.
  if [ "$midweek" != 1 ]; then
    perl -pi -e "s/^## Week \d+ /## Week $lw /" "$vtdir/current-priorities.md"
    perl -pi -e "s/^\d{4}-\d{2}-\d{2}(T\S+\tweek\t)/${d_lw}\$1/" "$vtdir/priorities.log"
  fi
  perl -pi -e "s/^## Today \(\d{4}-\d{2}-\d{2}\)/## Today ($d_yest)/" "$vtdir/current-priorities.md"
  perl -pi -e "s/^\d{4}-\d{2}-\d{2}(T\S+\ttoday\t)/${d_yest}\$1/" "$vtdir/priorities.log"
  rm -rf "$vtdir/.cleared"; mkdir -p "$vtdir/.cleared"   # stale stamps + armed = gate active on launch
}

# The Real C accept walk (Packet 005 dogfood) — printed for `demo c` INSTEAD of the beta A/B
# walks, and written into the workspace as DOGFOOD-REAL-C.md so it's visible in the session cwd.
REALC_RUNBOOK="$HOME/Ship/bls/stories/vibe-table/16-v2.5-orientation-loop/tracks/C-prioritize.md"

# The MIDWEEK (Tue+) variant of the accept walk — same store/board seed, but the Week stamp is
# the CURRENT ISO week, so /4loops:week opens in follow-up mode: look-back since yesterday.
realc_walk_midweek() {  # <yesterday> <week-number>
  local d_yest="$1" wk="$2"
  cat <<EOF
# Real C accept walk — MIDWEEK (Tue+) variant (Packet 007)

Same seed as \`demo c\`, with ONE difference: the Week stamp is the CURRENT ISO week (Week ${wk}),
only Today is stale (${d_yest}). That is the "it is not Monday" shape — the week is already set,
you are opening the day. Nothing marked done since yesterday, which is exactly the state that
used to kill the orientation print (Packet 007 fix).

  1. Ask Claude to edit web-app/src/components/Dashboard.jsx → DENIED with the ORIENTATION copy
     (Today is stale ⇒ the gate is active even though the week is current).
  2. /4loops:week → ONE print, and check the shape:
       · MODE: follow-up            (not new-week)
       · Look-back · since ${d_yest} — yesterday's Today (WEB-001 API-001), NOT a last-week dump
       · no "Look-back · last week" line, no done/carried tally
       · the print RUNS TO THE END: WEEK_ACTIVE / WEEK_CAP_LEFT / WEEK_SUGGESTED / TODAY_SUGGESTED
         are all present (with an empty done-set — the Packet 007 regression)
       · Week pick is cap-aware against the week you already have (4 open → up to 1 new)
     Then the today pick (2–3 from the week) → ONE rail call → gate clears.
  3. /4loops:prioritize add "some new thing" → store (lever=today) + Today + Week.
  4. cat .4loops/current-priorities.md — the Week section still reads Week ${wk}; only Today moved.

  ACCEPT = /4loops:week completes with no crash, the look-back is since-yesterday (a day, not a
  week), and the machine lines print.

Story runbook: ${REALC_RUNBOOK}
EOF
}
realc_walk() {  # [midweek] → stdout (markdown-ish plain text)
  local midweek="${1:-0}" d_yest lw wk
  d_yest=$(date -v-1d +%F 2>/dev/null || date -d 'yesterday' +%F)
  lw=$(date -v-7d +%V 2>/dev/null || date -d '7 days ago' +%V)
  wk=$(date +%V)
  if [ "$midweek" = 1 ]; then realc_walk_midweek "$d_yest" "$wk"; return 0; fi
  cat <<EOF
# Real C accept walk — Packet 006 dogfood (one-shot /week · checkbox priorities)

This sandbox is ALREADY CONFIGURED. Skip /4loops:configure, skip virgin onboarding, skip the
Track A/B beta arcs. Evaluate the ONE-SHOT orientation only:

  Seeded: mid-week board (WEB-*, API-*) · store CAP-001..005 (urgent / today / later, one due this
  week) · a PRIOR Week (Week ${lw}) at the cap — WEB-001 API-001 WEB-003 CAP-001 open, API-003 [x]
  done · yesterday's (${d_yest}) Today = WEB-001 API-001 (today ⊆ week). Both stamps are stale ⇒
  the gate is ACTIVE. The priorities file is plain checkboxes: cat .4loops/current-priorities.md

  1. Ask Claude to edit web-app/src/components/Dashboard.jsx → DENIED with the ORIENTATION copy
     ("run /4loops:week: one shot … lifts the gate"). No "move something on the board" nudge.
  2. /4loops:week → ONE print: the checkbox file · LOOK-BACK (last week: 1 done · 4 carried, what
     moved — no task-state moves) · WEEK PICK from the store (cap 5: 4 open → up to 1 new; urgent
     CAP-001 is already on, CAP-002 today / CAP-003 due this week are the candidates) · TODAY PICK
     (2–3 from that week; yesterday's carry first). Two multi-select questions, then ONE rail call
     (vt-week.sh set … --today …). The file prints back. GATE CLEARS HERE — no /4loops:today needed.
     Try naming 2 new week items → the rail refuses with the cap arithmetic (4 on → at most 1 new).
     Try picking a today item that is NOT on the week → it is promoted onto the week (no orphans).
  3. Re-run /4loops:week later the same day → MODE: follow-up, look-back is "since ${d_yest}", not a
     week replay; today is a pull from the current week. (This is the Tue+ shape.)
  4. /4loops:prioritize add "some new thing"  → lands in the store (lever=today) AND on Today AND on
     the Week (day-add ⇒ week-add). /4loops:prioritize done <ID> → [x] on both lists.
  5. /4loops:today is OPTIONAL — a mid-day re-pull of 2–3 from the week. It is never required for
     the gate.
  6. Ask "what did we do yesterday?" (via /4loops:sync) → vt-today.sh --yesterday.
  7. cat .4loops/current-priorities.md and .4loops/priorities.log (living checkbox doc + history).

  ACCEPT = 2 feels like orientation (look back → this week → today), one shot, no Keep/Edit/Skip
  board theater; the file is checkboxes; board.md untouched throughout.

## Track D walk — the board is pure active state (Packet 008)

Same sandbox, second pass. Here the question is the BOARD, not the orientation: it holds only
committed work moving through state, and Done is short-lived.

  Seeded for this: four active columns (no Backlog anywhere) · API-004 went Done nine days ago,
  past the 7-day dwell, while API-003 went Done today and is still dwelling.

  1. /4loops:board → four columns, Planning | In Progress | Testing | Done. There is no intake
     column to dump into.
  2. Say "new task: rotate the API keys" in /4loops:sync → it lands in the STORE (CAP-006), and
     the board does not change. Confirm: ls .4loops/store/items && git diff --stat (board.md clean).
  3. /4loops:manage flush → dry-run first. API-004 is ripe, API-003 is still dwelling. Run it:
     Done shrinks, .4loops/archive/<month>/closed.md gains the row. Then
     vt-flush.sh --restore API-004 puts it back — every exit off this board is reversible.
  4. Task CRUD: /4loops:manage edit WEB-002 --title "Rewrite the pricing page" ; then
     /4loops:manage merge <a> <b> or remove <id>. Re-render from disk as the proof.
  5. Key ops: vt-key.sh rename API SVC → every ID, the Projects row, the counter and the archive
     trail move together. Renaming onto an existing key is refused (IDs would collide).
  6. Legacy check: on a board that predates v2.5, vt-migrate-backlog.sh --dry-run shows what would
     move; without the flag it sends the parked rows to the store on lever \`later\` (or
     --to planning for work already committed). Never hand-edit board.md.

  ACCEPT = capture never touches the board · no rail offers a Backlog target · Done shrinks on a
  flush and the archive grows · at least one CRUD path lands and re-renders from disk.

Story runbook: ${REALC_RUNBOOK}
EOF
}

write_settings() {  # <config-dir> — injection settings (directory-source marketplace)
  local cfg="$1"
  mkdir -p "$cfg"
  cat > "$cfg/sandbox-settings.json" <<EOF
{
  "extraKnownMarketplaces": {
    "$MARKETPLACE": { "source": { "source": "directory", "path": "$REPO" } }
  },
  "enabledPlugins": { "4loops@$MARKETPLACE": true }
}
EOF
}

write_meta() {  # <root>
  cat > "$1/.sandbox-meta" <<EOF
MODE=$MODE
INSTALL=$INSTALL
EMPTY=$EMPTY
REPO=$REPO
CREATED=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
}

print_launch() {  # <root> <workspace>
  local root="$1" ws="$2"
  echo
  echo "✓ sandbox '$NAME' ready  (${MODE}${INSTALL:+/$INSTALL}$([ "$EMPTY" = true ] && echo ', empty'))"
  echo "  root: $root"
  echo
  echo "Launch:"
  case "$MODE/$INSTALL" in
    light/*)
      echo "  cd \"$ws\" && claude --plugin-dir \"$PLUGIN_DIR\""
      ;;
    isolated/inject)
      echo "  cd \"$ws\" && claude --bare --settings \"$root/config/sandbox-settings.json\" --strict-mcp-config"
      echo
      echo "  ⚠  --bare SKIPS OAuth + keychain (CC docs) → a Max/Pro subscription shows"
      echo "     'Not logged in'. Authenticate with ANTHROPIC_API_KEY (or an apiKeyHelper in"
      echo "     the settings file). For an authenticated run with no setup, use --light."
      [ -z "${ANTHROPIC_API_KEY:-}" ] && echo "     (ANTHROPIC_API_KEY is not set in this shell.)"
      ;;
    isolated/real)
      echo "  export HOME=\"$root/config\""
      echo "  claude plugin marketplace add \"$REPO\""
      echo "  claude plugin install 4loops@$MARKETPLACE"
      echo "  cd \"$ws\" && HOME=\"$root/config\" claude"
      echo
      echo "  ⚠  \$HOME override may not resolve the macOS login keychain → if it shows"
      echo "     'Not logged in', run /login inside the session (one-time, into this config)."
      ;;
  esac
  echo
  if [ "$EMPTY" = true ]; then
    echo "Walk (virgin onboarding — the new-user first hour):"
    echo "       · confirm 4loops is SILENT (no .4loops yet — no board, no nagging)"
    echo "       · /4loops:configure → it detects web-app + api-service (git repos) as Projects,"
    echo "         docs/ as an Area; you confirm, pick a week-start, confirm gated, then brain-dump"
    echo "         this week's anchors → it spawns them onto the board and lands on a live kanban."
    echo "       · then drive: /4loops:week (first, on a new week) → /4loops:today, and /nav to just talk."
  else
    echo "Walk (seeded — a believable mid-week board, drive the real loop):"
    echo "       · sentinel renders the board on session start; drift LEADS with overdue / due-soon"
    echo "       · ATTEMPT an Edit to web-app/src/components/Dashboard.jsx (a gated Project; don't"
    echo "         pre-judge it) → the PreToolUse hook DENIES it = the gate, the thesis"
    echo "       · edit docs/notes.md → allowed (an untracked Area); study/reading.md → always allowed"
    echo "       · /4loops:today on a fresh week is REFUSED → run /4loops:week first (week-before-today)"
    echo "       · /4loops:week THEN /4loops:today → see-then-pick; retry the gated edit → now ALLOWED"
    echo "       · /nav → opens the priority-annotated board (★ focus · ! overdue · ⏳ due-soon), then"
    echo "         just TALK: 'metrics endpoint is done, start the pricing copy, add rate limiting Fri'"
    echo "       · note ◆ on the modeling story (API-002) + the due dates on the cells"
    if [ "$INSTALL" = real ]; then
      echo "       · bump version → /plugin update → /reload-plugins → new hooks run (B4)"
    fi
  fi
  return 0
}

# ── Commands ──────────────────────────────────────────────────────────────────
parse_new_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --light)        MODE=light ;;
      --isolated)     MODE=isolated ;;
      --real-install) INSTALL=real ;;
      --inject)       INSTALL=inject ;;
      --empty)        EMPTY=true ;;
      --seeded)       EMPTY=false ;;
      -*)             die "unknown flag: $1" ;;
      *)              [ -z "$NAME" ] && NAME="$1" || die "unexpected arg: $1" ;;
    esac
    shift
  done
  [ -z "$NAME" ] && NAME="demo"
  case "$NAME" in *[!A-Za-z0-9._-]*) die "name must be [A-Za-z0-9._-]: $NAME" ;; esac
  if [ "$MODE" = light ]; then
    [ "$INSTALL" = real ] && echo "sandbox: --real-install ignored in --light (uses --plugin-dir)" >&2
    INSTALL=""
  fi
}

cmd_new() {
  local root ws
  root="$(sandbox_root "$MODE" "$NAME")"
  [ -e "$root" ] && die "sandbox '$NAME' already exists at $root (use 'refresh' or 'rm')"
  ws="$root/workspace"
  mkdir -p "$ws"
  scaffold_mock "$ws"
  [ "$EMPTY" = false ] && seed_board "$ws/.4loops"
  write_meta "$root"
  case "$MODE/$INSTALL" in
    isolated/inject) write_settings "$root/config" ;;
    isolated/real)   mkdir -p "$root/config" ;;
  esac
  print_launch "$root" "$ws"
}

# One-shot: build a FRESH, uniquely-named sandbox for a track and launch Claude in it.
# No dependency on any prior workspace — run it any time, even right after `prune`.
#   sandbox.sh demo a   → Track A (empty: install → /configure → …)
#   sandbox.sh demo b   → Track B (seeded mid-week, fresh ISO week)
#   sandbox.sh demo c   → v2.5 Real C (b + store levers + prior Week + yesterday's Today; prints the
#                          Real C accept walk, not the beta A/B walks; writes DOGFOOD-REAL-C.md)
#   sandbox.sh demo c --midweek → the Tue+ shape: the Week stamp stays on the CURRENT ISO week
#                          (only Today is stale) → /4loops:week opens in follow-up mode and the
#                          look-back is since YESTERDAY, not a last-week dump.
#   sandbox.sh demo <a|b|c> --no-launch   → just build + print the launch command
cmd_demo() {
  local track="${1:-}" launch=1 bypass=0 midweek=0 ts seed root ws
  shift || true
  while [ $# -gt 0 ]; do
    case "$1" in --no-launch) launch=0 ;; --bypass) bypass=1 ;; --midweek|--tue) midweek=1 ;; -*) die "unknown flag: $1" ;; *) die "unexpected arg: $1" ;; esac
    shift
  done
  if [ "$midweek" = 1 ]; then
    case "$track" in c|C|realc|store) ;; *) die "--midweek applies to demo c only" ;; esac
  fi
  case "$track" in
    a|A|fresh|empty)    EMPTY=true;  seed=fresh ;;
    b|B|seeded|midweek) EMPTY=false; seed=midweek ;;
    c|C|realc|store)    EMPTY=false; seed=realc ;;
    *) die "usage: sandbox demo <a|b|c> [--no-launch]  (a = empty/onboarding, b = seeded board, c = Real C: seeded board + store + prior week + yesterday focus)" ;;
  esac
  MODE=light; INSTALL=""
  ts=$(date +%Y%m%d-%H%M%S)
  local mw_sfx="" mw_note=""
  if [ "$midweek" = 1 ]; then mw_sfx="-midweek"; mw_note="  [midweek / Tue+ shape]"; fi
  NAME="beta-${seed}${mw_sfx}-${ts}"
  root="$(sandbox_root light "$NAME")"; ws="$root/workspace"
  mkdir -p "$ws"
  scaffold_mock "$ws"
  [ "$EMPTY" = false ] && seed_board "$ws/.4loops"
  if [ "$seed" = realc ]; then
    seed_store "$ws/.4loops" "$midweek"
    realc_walk "$midweek" > "$ws/DOGFOOD-REAL-C.md"
  fi
  write_meta "$root"
  echo "✓ fresh sandbox '$NAME'  ($root)${mw_note}" >&2
  if [ "$seed" = realc ]; then
    echo >&2; realc_walk "$midweek" >&2; echo >&2
    echo "  (this walk is also at $ws/DOGFOOD-REAL-C.md)" >&2
  fi
  if [ "$launch" = 1 ]; then
    if [ "$bypass" = 1 ]; then
      echo "  launching in BYPASS mode (VT_ALLOW_STALE_GATE=1) — the gate is OFF this whole session…" >&2
      cd "$ws" && exec env VT_DIR="$ws/.4loops" VT_ALLOW_STALE_GATE=1 claude --plugin-dir "$PLUGIN_DIR"
    fi
    echo "  launching Claude Code with the 4loops plugin (VT_DIR pinned to $ws/.4loops) — type /4loops to see the menu…" >&2
    cd "$ws" && exec env VT_DIR="$ws/.4loops" claude --plugin-dir "$PLUGIN_DIR"
  fi
  echo "  launch:  cd \"$ws\" && VT_DIR=\"$ws/.4loops\" claude --plugin-dir \"$PLUGIN_DIR\"" >&2
}

cmd_refresh() {
  local name="${1:-}" root ws
  [ -z "$name" ] && die "usage: sandbox refresh <name>"
  root="$(find_sandbox "$name")" || die "no sandbox '$name'"
  # shellcheck disable=SC1091
  . "$root/.sandbox-meta"   # restores MODE/INSTALL/EMPTY/REPO
  ws="$root/workspace"
  rm -rf "$ws/.4loops"
  [ "${EMPTY:-false}" = false ] && seed_board "$ws/.4loops"
  echo "✓ refreshed '$name' — board reset to seed ($root)"
}

cmd_expire() {  # backdate Today's stamp so a reconciled board reads stale → gate active
  local name="${1:-}" root vt pri y
  if [ -n "$name" ]; then root="$(find_sandbox "$name")" || die "no sandbox '$name'"
  else root="$(latest_sandbox)" || die "no sandboxes yet — run: sandbox demo a"; fi
  name="$(basename "$root")"; name="${name#vt-sandbox-}"
  vt="$root/workspace/.4loops"
  pri="$vt/current-priorities.md"
  [ -f "$pri" ] || die "no current-priorities.md in '$name' — run /4loops:configure (or /4loops:today) first"
  y=$(date -v-1d +%F 2>/dev/null || date -d 'yesterday' +%F)
  # Backdate ONLY Today (leave Week current) so a single /4loops:today lifts the gate
  # again — the clean B1 (blocked) → B2 (allowed-same-session) demo.
  sed -i.bak -E "s/## Today \([0-9-]+\)/## Today ($y)/" "$pri" && rm -f "$pri.bak"
  : > "$vt/.armed"   # the gate only enforces once armed
  echo "✓ expired '$name' — Today backdated to $y; the rail is now ACTIVE for any NEW session."
  echo "  Now reopen it fresh:  sandbox relaunch    (then attempt a gated Edit → BLOCKED; /4loops:today → ALLOWED)"
}

cmd_relaunch() {  # reopen a sandbox in a FRESH Claude session (defaults to the latest one)
  local name="" bypass=0 root ws    # --bypass = launch with VT_ALLOW_STALE_GATE=1 in the env
  while [ $# -gt 0 ]; do
    case "$1" in --bypass) bypass=1 ;; -*) die "unknown flag: $1" ;; *) name="$1" ;; esac
    shift
  done
  if [ -n "$name" ]; then root="$(find_sandbox "$name")" || die "no sandbox '$name'"
  else root="$(latest_sandbox)" || die "no sandboxes yet — run: sandbox demo a"; fi
  ws="$root/workspace"
  if [ "$bypass" = 1 ]; then
    echo "↻ relaunching $(basename "$root") in BYPASS mode (VT_ALLOW_STALE_GATE=1) — gate OFF this session…" >&2
    cd "$ws" && exec env VT_DIR="$ws/.4loops" VT_ALLOW_STALE_GATE=1 claude --plugin-dir "$PLUGIN_DIR"
  fi
  echo "↻ relaunching $(basename "$root") (VT_DIR pinned) — type /4loops for the menu…" >&2
  cd "$ws" && exec env VT_DIR="$ws/.4loops" claude --plugin-dir "$PLUGIN_DIR"
}

cmd_list() {
  local found=0 d
  for d in "$PERSIST_BASE"/*/ "$TMP_BASE"/vt-sandbox-*/; do
    [ -f "${d}.sandbox-meta" ] || continue
    found=1
    ( # shellcheck disable=SC1091
      . "${d}.sandbox-meta"
      nm="$(basename "$d")"; [ "$MODE" = light ] && nm="${nm#vt-sandbox-}"
      printf '  %-16s %-9s %-7s %s\n' "$nm" "$MODE" "${INSTALL:--}" "$d" )
  done
  [ "$found" = 0 ] && echo "  (no sandboxes)"
}

cmd_rm() {
  local name="${1:-}" root
  [ -z "$name" ] && die "usage: sandbox rm <name>"
  root="$(find_sandbox "$name")" || die "no sandbox '$name'"
  case "$root" in
    "$PERSIST_BASE"/?*|"$TMP_BASE"/vt-sandbox-?*) ;;
    *) die "refusing to rm outside sandbox bases: $root" ;;
  esac
  rm -rf "$root"
  echo "✓ removed '$name' ($root)"
}

cmd_prune() {  # remove ALL sandboxes in both bases — the "clean up dead workspaces" reset.
  local found=0 d
  for d in "$PERSIST_BASE"/*/ "$TMP_BASE"/vt-sandbox-*/; do
    [ -f "${d}.sandbox-meta" ] || continue   # only real sandboxes (marker present)
    case "$d" in
      "$PERSIST_BASE"/?*/|"$TMP_BASE"/vt-sandbox-?*/) found=1; rm -rf "$d" && echo "✓ removed $(basename "$d")" ;;
    esac
  done
  [ "$found" = 0 ] && echo "  (no sandboxes to prune)"
}

# ── Dispatch ──────────────────────────────────────────────────────────────────
case "${1:-}" in
  demo)              shift; cmd_demo "$@" ;;
  relaunch|open)     shift; cmd_relaunch "$@" ;;
  new)               shift; parse_new_args "$@"; cmd_new ;;
  refresh)           shift; cmd_refresh "${1:-}" ;;
  expire)            shift; cmd_expire "${1:-}" ;;
  list)              cmd_list ;;
  rm)                shift; cmd_rm "${1:-}" ;;
  prune)             cmd_prune ;;
  ""|-h|--help|help) usage ;;
  *)                 die "unknown subcommand: $1 (try: demo|relaunch|new|refresh|expire|list|rm|prune)" ;;
esac
