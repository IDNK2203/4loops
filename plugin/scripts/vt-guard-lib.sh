#!/usr/bin/env bash
# vt-guard-lib.sh — enforcement helpers for the 4loops hard rail.
# Sourced by the PreToolUse guards (vt-gate.sh, vt-bash-gate.sh) and the
# UserPromptSubmit nudge (vt-prompt-gate.sh). NOT directly invocable.
#
# Division of labour (see BRIEF §6):
#   - vt_gate_active() lives in vt-priorities-lib.sh — THE shared predicate the
#     sentinel and the guards both call. One code path.
#   - These helpers are the enforcement layer: resolve the workspace root from a
#     tool's TARGET path (not cwd), decide gated-vs-exempt, track per-session
#     clearance (carries across midnight / resume), log overrides, emit deny.
#
# FAIL-OPEN: any resolution failure → caller allows. A guard bug must never
# brick the user's ability to work.

# ── JSON field extraction (jq if present, crude sed fallback) ────────────────
# $1 = json string, $2 = dotted path (e.g. .session_id, .tool_input.file_path)
vt_json_field() {
  local json="$1" path="$2" out=""
  if command -v jq >/dev/null 2>&1; then
    out=$(printf '%s' "$json" | jq -r "$path // empty" 2>/dev/null) || out=""
  else
    # Fallback: match the leaf key's string value, first occurrence.
    local key="${path##*.}"
    out=$(printf '%s' "$json" \
      | grep -o "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" 2>/dev/null \
      | head -1 | sed -E 's/.*:[[:space:]]*"//; s/"$//') || out=""
  fi
  printf '%s' "$out"
  return 0
}

# ── Workspace root resolution ────────────────────────────────────────────────
# Walk UP from a target path until a directory containing .4loops/ is found.
# Echoes the workspace root, or returns 1 if none (→ not a VT workspace).
# Resolves from the TARGET (a PreToolUse hook's file may be outside cwd).
vt_find_workspace_root() {
  local p="$1" d
  [ -z "$p" ] && return 1
  if [ -d "$p" ]; then d="$p"; else d="$(dirname "$p")"; fi
  while [ -n "$d" ] && [ "$d" != "/" ] && [ "$d" != "." ]; do
    [ -d "$d/.4loops" ] && { printf '%s' "$d"; return 0; }
    d="$(dirname "$d")"
  done
  [ -d "/.4loops" ] && { printf '%s' "/"; return 0; }
  return 1
}

# Resolve a possibly-relative path to absolute, against a base dir ($2, def PWD).
vt_resolve_abs() {
  local p="$1" base="${2:-$PWD}"
  case "$p" in
    /*) printf '%s' "$p" ;;
    *)  printf '%s' "${base%/}/$p" ;;
  esac
}

# ── First-run on-ramp (rail-armed state) ─────────────────────────────────────
# The rail is "armed" once the first orientation (/4loops:week) has run. Until then the
# guard allows (one-time install grace) so a fresh workspace doesn't block from
# minute one. The sentinel renders the "rail arms after your first /4loops:week"
# notice during grace. VT_DIR must be set before calling.
vt_rail_armed() { [ -f "$VT_DIR/.armed" ]; }
vt_arm_rail()   { : > "$VT_DIR/.armed" 2>/dev/null || true; }

# ── Workspace opt-out (v2.5 Packet 010: Surround) ─────────────────────────────
# `.4loops/disabled` is this workspace's FULL opt-out of 4loops enforcement. While
# the flag exists every hook steps aside: the orientation gate (C), the rail
# capability check (B1), the rail-owned record protection (B2) and the prompt
# nudge. Full opt-out is deliberate (Surround plan, decision for build) — a
# half-disabled rail that still refused a board hand-edit would be worse than
# either honest state.
#
# ORDERING IS LOAD-BEARING: every hook must test vt_is_disabled BEFORE its
# record check, or the opt-out would still block hand-edits of board.md.
#
# The flag is itself a B2 rail-record (vt_is_rail_record, below), so the AGENT
# cannot create it with an Edit/Write or a shell redirect and thereby switch off
# its own gate. The only ways in are the user-invoked `/4loops:disable` skill —
# which mints the `disable` capability that vt-disable.sh's `on` mode requires —
# and the user's own hands outside Claude. Opting out is the USER's call alone.
#
# Opting out DELETES NOTHING: board.md, current-priorities.md, store/ and
# archive/ survive untouched, so re-enabling resumes the same board.
vt_is_disabled()   { [ -f "$VT_DIR/disabled" ]; }
vt_disable_flag()  { printf '%s' "$VT_DIR/disabled"; }

# ── Per-session clearance (carries across midnight + resume) ──────────────────
# A session that has seen the gate clear (ran the ritual, or started/acted on a
# fresh day) is marked; it is NEVER re-blocked for its lifetime, even past
# midnight. This is the precise replacement for DevOS's blunt 18h grace.
# Marker = empty file .4loops/.cleared/<session_id> (mtime = when cleared).
# session_id is stable across `claude -r`/--continue (verified); /fork mints a
# new id and correctly re-gates.
vt_cleared_dir() { printf '%s' "$VT_DIR/.cleared"; }

vt_session_cleared() {
  local sid="$1"
  [ -z "$sid" ] && return 1
  [ -f "$(vt_cleared_dir)/$sid" ]
}

vt_mark_session_cleared() {
  local sid="$1"
  [ -z "$sid" ] && return 0
  # session ids are uuids; strip anything outside a safe filename charset.
  sid=$(printf '%s' "$sid" | tr -cd 'A-Za-z0-9._-')
  [ -z "$sid" ] && return 0
  mkdir -p "$(vt_cleared_dir)" 2>/dev/null || return 0
  : > "$(vt_cleared_dir)/$sid" 2>/dev/null || true
}

# Prune cleared-session markers older than 3 days (dead sessions). Best-effort.
vt_prune_cleared() {
  local dir; dir="$(vt_cleared_dir)"
  [ -d "$dir" ] || return 0
  find "$dir" -type f -mtime +3 -delete 2>/dev/null || true
}

# ── File-growth GC (W5): replicating markers → "latest only" ─────────────────
# Idempotency markers replicate one-per-period and never self-clean:
#   .weekly-rolled-*  → keep only the CURRENT week's (older weeks are dead weight)
#   .prompt-nudged-*  → keep only today's
#   .cleared/*        → drop markers older than 3 days (dead sessions)
# These are pure guards (no history), so pruning is safe. Best-effort + fail-open.
# Requires week_marker_id + iso_today (vt-priorities-lib.sh) sourced.
vt_gc_markers() {
  local cur_week today
  cur_week=".weekly-rolled-$(week_marker_id 2>/dev/null)"
  today=".prompt-nudged-$(iso_today 2>/dev/null)"
  find "$VT_DIR" -maxdepth 1 -name '.weekly-rolled-*' ! -name "$cur_week" -delete 2>/dev/null || true
  find "$VT_DIR" -maxdepth 1 -name '.prompt-nudged-*' ! -name "$today" -delete 2>/dev/null || true
  vt_prune_cleared
}

# ── Gated vs exempt surface (narrow-default) ─────────────────────────────────
# Only the named product surfaces are gated; everything else is allowed. The
# exempt list is a HARD always-allow (even if config widens the gated set), so
# the ritual can never block itself and exploration/research is never blocked.
#
# SCOPE OF THE ORIENTATION GATE (locked by Ese 2026-09-13, v2.5 Packet 009b):
# stale orientation blocks EXACTLY these gated product surfaces, via Edit/Write
# (vt-gate.sh) and their shell equivalents (vt-bash-gate.sh). It does NOT gate
# the board. Board/store mutation is guarded by a different, unrelated check —
# the per-session rail capability (vt_cap_allows, below) — and .4loops/ is on
# the exempt list, so a session holding a capability may drive the board rails
# whether or not orientation is fresh. Do not couple the two.

# Exempt = always writable, even gate-up.
vt_is_exempt() {
  local abs="$1" root="$2" rel="${1#"$2"/}"
  case "$abs" in
    "$root"/.4loops|"$root"/.4loops/*) return 0 ;;
    "$root"/.claude|"$root"/.claude/*)          return 0 ;;
    "$root"/inbox/*|"$root"/reviews/*)          return 0 ;;
  esac
  case "$rel" in
    study/*|*/study/*|learnings/*|*/learnings/*) return 0 ;;  # research surfaces
    ARTIFACTS.md|*/ARTIFACTS.md)                 return 0 ;;  # per-project spine
    .gitignore|*/.gitignore|.env|*/.env|.env.*|*/.env.*) return 0 ;;
  esac
  # workspace-root-level docs only (CLAUDE.md, PLAN.md, …) — no slash in rel.
  case "$rel" in
    */*)  : ;;            # has a subdir → not a root doc
    *.md) return 0 ;;
  esac
  return 1
}

# The gated globs (product/deliverable surfaces), root-relative. Default =
# Build + Share. Overridable per workspace via .4loops/config (`gated: <glob>`
# lines) — config may narrow/widen but the exempt list above always wins.
vt_gated_globs() {
  local cfg="$VT_DIR/config" globs="" noglob_was_off=0
  [ -f "$cfg" ] && globs=$(awk -F': *' '/^gated:/ {print $2}' "$cfg" 2>/dev/null)
  if [ -n "$globs" ]; then
    # A configured `gated: web-app/*` is a PATTERN, not a directory listing.
    # Unquoted $globs gets word-splitting (wanted: several globs on one line)
    # AND pathname expansion (NOT wanted: `web-app/*` becomes web-app/README.md,
    # web-app/src, … against the guard's cwd, so web-app/src/components/x.jsx
    # matched nothing and the orientation gate silently stopped gating nested
    # product files — v2.5 Packet 009b dogfood). `set -f` keeps the splitting
    # and kills the expansion; restore the caller's flag either way.
    case "$-" in *f*) : ;; *) noglob_was_off=1 ;; esac
    set -f
    # shellcheck disable=SC2086  # intentional split-only expansion (noglob is on)
    printf '%s\n' $globs
    [ "$noglob_was_off" = 1 ] && set +f
    return 0
  else
    printf '%s\n' "projects/*/repo-scaffolding/*" "projects/*/content/*" "projects/*/gists/*"
  fi
}

# Returns 0 if abs is a gated product surface under root (and not exempt).
vt_is_gated() {
  local abs="$1" root="$2" rel g
  case "$abs" in "$root"/*) ;; *) return 1 ;; esac   # outside workspace → not ours
  vt_is_exempt "$abs" "$root" && return 1            # hard-exempt wins
  rel="${abs#"$root"/}"
  while IFS= read -r g; do
    [ -z "$g" ] && continue
    # shellcheck disable=SC2254  # $g is an intentional glob
    case "$rel" in $g) return 0 ;; esac
  done < <(vt_gated_globs)
  return 1
}

# ── Rail-owned records (W4: user-only overwrite) ─────────────────────────────
# board.md + current-priorities.md are written ONLY through the rail scripts,
# which keep counts, the dense grid, and transitions.log in sync. A direct
# hand-edit by the agent desyncs them — so direct Edit/Write/Bash writes to these
# two files are blocked (the user overrides with VT_ALLOW_RECORD_WRITE=1). The
# rest of .4loops/ stays freely writable / exempt. NOTE: the rails write these
# files inside their own subprocesses, which never surface as a tool write-target,
# so the rails are never caught by this check — only out-of-band hand-edits are.
vt_is_rail_record() {
  case "$1" in
    */.4loops/board.md|*/.4loops/current-priorities.md) return 0 ;;
    .4loops/board.md|.4loops/current-priorities.md)      return 0 ;;
    */.4loops/.cap/*|.4loops/.cap/*)                     return 0 ;;  # W4+ (v2.4): capability tokens are hook-written, agent-unwritable
    */.4loops/store/*|.4loops/store/*)                   return 0 ;;  # v2.5 Track A: detached backlog store is rail-owned
    */.4loops/tasks/*|.4loops/tasks/*)                   return 0 ;;  # v2.5 Track B: ephemeral scope docs are rail-owned
    */.4loops/disabled|.4loops/disabled)                 return 0 ;;  # v2.5 Packet 010: the opt-out flag is rail-written — an agent-writable flag would be an agent-disablable gate
  esac
  return 1
}

vt_log_record_override() {
  local abs="$1" sid="${2:-<no-sid>}" ts
  ts=$(date "+%Y-%m-%d %H:%M")
  printf '%s | VT_ALLOW_RECORD_WRITE | record | %s | %s\n' \
    "$ts" "$sid" "$abs" >> "$VT_DIR/override.log" 2>/dev/null || true
}

vt_record_deny_reason() {
  printf '%s' "4loops BASH-GATE (rail-owned record — NOT the orientation gate): the board/store records (board.md / current-priorities.md / store/ / tasks/) are rail-owned — hand-editing desyncs counts + transitions.log. Do NOT hand-edit them yourself. Just talk to /4loops:sync (say what's new, what moved, what's done) and it moves the board for you; or run the one-shot orientation /4loops:week. Hand-editing is the USER's decision alone — only if THEY explicitly ask (it's logged)."
}

# ── Per-session capability grant (v2.4: rails are operator-invoked) ──────────
# A user-typed slash command (/4loops:<cmd>) is the ONLY un-forgeable "the USER
# initiated this" signal: it fires UserPromptExpansion with command_name, whereas
# the agent's skill route is PreToolUse tool_name=Skill — which does NOT (verified
# by hand-test 2026-06-28). vt-cap.sh records the invoked command here; the
# bash-gate then allows a rail-script invocation only if a fresh grant covers it.
# The token file is a W4 rail-record (above) so the agent can't forge it by writing.
# Session-scoped, matching /sync's "standing consent for this working session".
#
# ONE capability per session, LAST SLASH WINS — intentional, locked by Ese
# 2026-09-13 (v2.5 Packet 009b). Typing /4loops:week and then /4loops:manage
# leaves the session holding `manage`, and the `week` grant is gone: the second
# command is the user's current intent, and accumulating grants would let a
# long session quietly collect every capability it ever touched. Re-type the
# ritual's own slash command to get its grant back. Do NOT make these additive.
vt_cap_dir()  { printf '%s' "$VT_DIR/.cap"; }
vt_cap_file() { printf '%s' "$VT_DIR/.cap/$1"; }   # $1 = session_id

# Record the user-invoked command for this session (bare name, no "4loops:").
vt_write_cap() {
  local sid="$1" cmd="$2"
  sid=$(printf '%s' "$sid" | tr -cd 'A-Za-z0-9._-')
  cmd=$(printf '%s' "$cmd" | tr -cd 'A-Za-z0-9._-')
  [ -z "$sid" ] && return 0
  mkdir -p "$(vt_cap_dir)" 2>/dev/null || return 0
  printf '%s' "$cmd" > "$(vt_cap_file "$sid")" 2>/dev/null || true
}

# Read the bare command granted this session (strips any "4loops:" prefix).
vt_read_cap() {
  local sid="$1" raw=""
  sid=$(printf '%s' "$sid" | tr -cd 'A-Za-z0-9._-')
  [ -z "$sid" ] && { printf ''; return 0; }
  raw=$(cat "$(vt_cap_file "$sid")" 2>/dev/null) || raw=""
  printf '%s' "${raw#*:}"
}

# Classify a rail script (basename minus .sh) into an enforcement tier:
#   gateclear-today / gateclear-week → the gate-clearing rituals (strict match)
#   mutate   → board-state writers
#   readonly → display/query (never gated)
#   ""       → not one of ours (fail-open → allow)
vt_rail_tier() {
  case "$1" in
    vt-today) printf 'gateclear-today' ;;
    vt-week)  printf 'gateclear-week' ;;
    vt-transition|vt-priority|vt-draft|vt-arrange|vt-close|vt-repack|vt-refresh-counts|vt-gc|vt-init|vt-config|vt-store-capture|vt-store-expire|vt-store-lever|vt-scope-promote) printf 'mutate' ;;
    # v2.5 Track D — board lifecycle writers (task CRUD, Done flush, key ops, migration)
    vt-edit|vt-merge|vt-remove|vt-flush|vt-key|vt-migrate-backlog) printf 'mutate' ;;
    # v2.5 Packet 010 — Surround: the workspace opt-out is its OWN tier, not
    # `mutate`. Typing /4loops:disable should buy exactly one thing (the opt-out
    # flag) and must not hand the session the board rails as a side effect; and
    # conversely a /4loops:sync grant must not be able to switch the rail off.
    vt-disable) printf 'optout' ;;
    vt-render|vt-drift|vt-next-id|vt-detect|vt-store-list|vt-scope-list|vt-scope-read) printf 'readonly' ;;
    *) printf '' ;;
  esac
}

# Tier for a rail AS INVOKED: the gate-clearing rituals have read-only modes
# that other operator commands (/sync, /prioritize, /week) legitimately call to
# orient — those are never gated. Any other invocation keeps the script's tier.
# $1 = rail name, $2 = the full command string.
#
# The mode list is PER RAIL and must match the script's own case dispatch exactly.
# vt-week.sh has no --yesterday (that lives on vt-today.sh) and its dispatch ends
# in a catch-all `set|add|*`, so a flag it doesn't know is parsed as a free-text
# item and WRITES. Listing a mode here that the rail doesn't implement would hand
# a capability-less agent a write disguised as a read (v2.5 Packet 009).
vt_rail_readonly_modes() {
  case "$1" in
    vt-week)  printf 'orient|default|current|print' ;;
    vt-today) printf 'orient|default|current|yesterday|print' ;;
    vt-disable) printf 'status' ;;
    *)        printf '' ;;
  esac
}

vt_rail_tier_for() {
  local rname="$1" cmd="$2" modes total ro
  modes=$(vt_rail_readonly_modes "$rname")
  if [ -n "$modes" ]; then
    # Every mention of the script in the command must be a read-only mode —
    # a chained `--orient; vt-today.sh P0-1` must NOT ride the read-only pass.
    total=$(printf '%s\n' "$cmd" | grep -oE "${rname}\.sh" | wc -l | tr -d ' ')
    ro=$(printf '%s\n' "$cmd" | grep -oE "${rname}\.sh\"?[[:space:]]+--(${modes})([[:space:]]|$)" | wc -l | tr -d ' ')
    if [ "${total:-0}" -gt 0 ] && [ "$total" -eq "${ro:-0}" ]; then
      printf 'readonly'; return 0
    fi
  fi
  vt_rail_tier "$rname"
}

# Does this session's capability (bare cmd) cover the rail's tier?
vt_cap_allows() {
  local cap="$1" tier="$2"
  case "$tier" in
    ''|readonly)     return 0 ;;                                  # not ours / read-only → allow
    gateclear-today) [ "$cap" = "today" ] && return 0 || return 1 ;;
    gateclear-week)  [ "$cap" = "week" ]  && return 0 || return 1 ;;
    # v2.5 Packet 010: only the opt-out command itself. Deliberately NOT part of
    # the `mutate` set below — see vt_rail_tier.
    optout)          [ "$cap" = "disable" ] && return 0 || return 1 ;;
    mutate)
      # The shipped slash skills, exactly. `scope` was dropped with the /scope
      # skill (Track B is dead — v2.5 Packet 009b); no capability can be minted
      # for a command that no longer exists, so listing it would only be stale.
      case "$cap" in
        sync|today|week|capture|manage|prioritize|configure) return 0 ;;
      esac
      return 1 ;;
  esac
  return 1
}

# Deny directive for a bare rail invocation lacking capability. $1 = the rail's
# tier (optional): the opt-out rail gets its own copy, because "you have no
# capability for a mutating rail" would be a confusing thing to say about a
# command whose whole job is to switch the rail OFF.
vt_cap_deny_reason() {
  if [ "${1:-}" = "optout" ]; then
    printf '%s' "4loops BASH-GATE (workspace opt-out — NOT the orientation gate): switching 4loops enforcement off for this workspace is the USER's decision alone, so vt-disable.sh on|off needs a capability minted by the user typing /4loops:disable. Nothing is stale and nothing is broken — you simply were not handed the opt-out. If the rail is in the user's way, say so and suggest THEY run /4loops:disable (it writes .4loops/disabled, deletes no board/store/priorities data, and is undone with rm .4loops/disabled). Do NOT create .4loops/disabled yourself and do NOT work around the gate — an agent that can disable its own gate has no gate. vt-disable.sh --status is read-only and never blocked, so you may always check whether the rail is on."
    return 0
  fi
  printf '%s' "4loops BASH-GATE (rail capability — NOT the orientation gate, and NOT a refusal to help): this session has no capability for a mutating vt-*.sh rail. Rails are operator-invoked: a capability is minted only when the USER types a /4loops:<cmd> slash command, and it covers that session. Nothing is stale and no ritual is overdue — you simply were not handed the rail. To move the board, ask the operator to run /4loops:sync (then just say what changed); to orient, /4loops:week (one shot). Do NOT call mutating rail scripts yourself and do NOT work around this. Read-only rails (vt-render / vt-drift / vt-store-list / vt-week --orient|--print / vt-today --orient|--print|--current|--yesterday) are NEVER blocked — run those freely to answer questions."
}

# ── Override logging (the only escape — per-action, re-arms next call) ────────
vt_log_override() {
  local abs="$1" sid="${2:-<no-sid>}" gate_state="${3:-focus-stale}" ts
  ts=$(date "+%Y-%m-%d %H:%M")
  printf '%s | VT_ALLOW_STALE_GATE | %s | %s | %s\n' \
    "$ts" "$gate_state" "$sid" "$abs" >> "$VT_DIR/override.log" 2>/dev/null || true
}

# ── Block directive + emit ───────────────────────────────────────────────────
# Built from current stamps so it names the right ritual (week-first on a new
# ISO week). Requires vt-priorities-lib.sh sourced (read_*_stamp / iso_*).
vt_gate_directive() {
  local lead
  if ! week_stamp_current "$(read_week_stamp)"; then
    lead="It's a new week — run /4loops:week: one shot (look back at last week, set this week's ≤5 from the store, pick today's 2–3 from it). That single flow lifts the gate."
  else
    lead="Today's priorities are stale — run /4loops:week: one shot (look back since yesterday, refresh the week if needed, pull today's 2–3 from it). That single flow lifts the gate."
  fi
  printf '%s' "4loops ORIENTATION GATE — orientation stale (this is the stale-priorities gate, NOT the rail-capability bash-gate). ${lead} This is orientation, not board churn: no state moves are required to lift it. STOP here — do NOT edit this gated surface, and do NOT work around the gate yourself (no override, no shelling out, no alternate tool). You cannot orient for the user: the rituals are user-invoked by design. Surface this, ask them to run the command above, and wait — that orientation IS their priority-setting and it lifts the gate. This gate covers the CODEBASE ONLY — the configured gated product surfaces. It does not freeze the board: the board rails are capability-gated (a user-typed /4loops:sync or /4loops:manage), never orientation-gated, so with that capability you can still move state, capture, and re-prioritise while orientation is stale. Reading, search, notes (.4loops/, study/, learnings/, inbox/) and every read-only rail (vt-render / vt-drift / vt-store-list / vt-week --orient / vt-today --orient) are never blocked, so do whatever non-gated work you can meanwhile. Bypassing is the USER's decision alone — only if THEY explicitly tell you to (it's logged)."
}

# Emit a PreToolUse deny. Canonical = exit 0 + hookSpecificOutput JSON; falls
# back to exit 2 + stderr when jq is unavailable. Either way the reason reaches
# Claude so it knows to run the ritual. CALLS EXIT.
vt_emit_deny() {
  local reason="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg r "$reason" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
    exit 0
  fi
  printf '%s\n' "$reason" >&2
  exit 2
}
