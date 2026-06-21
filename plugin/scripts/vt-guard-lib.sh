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
  printf '%s' "4loops gate (focus stale). ${lead} That reconciliation IS your priority-setting and it lifts this gate. Reading, search, and notes (.4loops/, study/, learnings/, inbox/) are never blocked. One-time bypass for THIS single action (logged): re-run prefixed with VT_ALLOW_STALE_GATE=1."
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
