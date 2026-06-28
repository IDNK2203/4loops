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
# The rail is "armed" once the first ritual (/4loops:today) has run. Until then the
# guard allows (one-time install grace) so a fresh workspace doesn't block from
# minute one. The sentinel renders the "rail arms after your first /4loops:today"
# notice during grace. VT_DIR must be set before calling.
vt_rail_armed() { [ -f "$VT_DIR/.armed" ]; }
vt_arm_rail()   { : > "$VT_DIR/.armed" 2>/dev/null || true; }

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
  local cfg="$VT_DIR/config" globs=""
  [ -f "$cfg" ] && globs=$(awk -F': *' '/^gated:/ {print $2}' "$cfg" 2>/dev/null)
  if [ -n "$globs" ]; then
    printf '%s\n' $globs
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
  printf '%s' "4loops: the board records (board.md / current-priorities.md) are rail-owned — hand-editing desyncs counts + transitions.log. Do NOT hand-edit them yourself. Just talk to /4loops:sync (say what's new, what moved, what's done) and it moves the board for you; or run the rituals /4loops:today and /4loops:week. Hand-editing is the USER's decision alone — only if THEY explicitly ask (it's logged)."
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
    lead="It's a new week — run /4loops:week, then /4loops:today, to reconcile the board and set focus."
  else
    lead="Today's focus is stale — run /4loops:today to reconcile the board and set today's focus."
  fi
  printf '%s' "4loops gate (focus stale). ${lead} STOP here — do NOT edit this gated surface, and do NOT work around the gate yourself (no override, no shelling out, no alternate tool). You cannot reconcile for the user: the rituals are user-invoked by design. Surface this, ask them to run the command above, and wait — that reconciliation IS their priority-setting and it lifts the gate. Reading, search, and notes (.4loops/, study/, learnings/, inbox/) are never blocked, so do whatever non-gated work you can meanwhile. Bypassing is the USER's decision alone — only if THEY explicitly tell you to (it's logged)."
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
