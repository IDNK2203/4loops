#!/usr/bin/env bash
# vt-gate.sh — PreToolUse guard for Edit | Write | NotebookEdit.
#
# Blocks writes to the gated product surface while today's/this week's focus is
# stale — UNLESS: the rail isn't armed yet (first-run on-ramp), the target is
# exempt, the surface isn't gated, this session already cleared the gate
# (carries across midnight/resume), or a logged per-action override is set.
#
# FAIL-OPEN: any error → allow (a guard bug must never brick real work).
set -uo pipefail

HOOK_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCRIPTS_DIR="$HOOK_DIR/../scripts"
# shellcheck source=../scripts/vt-guard-lib.sh
source "$SCRIPTS_DIR/vt-guard-lib.sh" 2>/dev/null || exit 0

input=$(cat 2>/dev/null || printf '{}')
target=$(vt_json_field "$input" '.tool_input.file_path')
[ -z "$target" ] && target=$(vt_json_field "$input" '.tool_input.notebook_path')
[ -z "$target" ] && exit 0          # no path → not our concern
sid=$(vt_json_field "$input" '.session_id')
cwd=$(vt_json_field "$input" '.cwd')

abs=$(vt_resolve_abs "$target" "${cwd:-$PWD}")
root=$(vt_find_workspace_root "$abs") || exit 0
[ -z "$root" ] && exit 0            # not a 4loops workspace

export VT_DIR="$root/.4loops"
# shellcheck source=../scripts/vt-priorities-lib.sh
source "$SCRIPTS_DIR/vt-priorities-lib.sh" 2>/dev/null || exit 0

# W4: rail-owned records are user-only. Block direct hand-edits regardless of
# gate/armed state (the rails write them via their own scripts, never as a tool
# write-target). Override (logged): VT_ALLOW_RECORD_WRITE=1.
if vt_is_rail_record "$abs"; then
  if [ "${VT_ALLOW_RECORD_WRITE:-}" = "1" ]; then vt_log_record_override "$abs" "$sid"; exit 0; fi
  vt_emit_deny "$(vt_record_deny_reason)"
fi

vt_rail_armed || exit 0             # first-run on-ramp: not armed → allow
vt_is_exempt "$abs" "$root" && exit 0
vt_is_gated  "$abs" "$root" || exit 0   # narrow-default: only the product surface

# Gate clear (board reconciled today) → allow + record this session so it
# carries its clearance across a midnight boundary.
if ! vt_gate_active; then
  vt_mark_session_cleared "$sid"
  exit 0
fi

# This session already cleared (continuous work / resumed session) → allow.
vt_session_cleared "$sid" && exit 0

# Per-action logged override → allow once; re-arms on the next action.
if [ "${VT_ALLOW_STALE_GATE:-}" = "1" ]; then
  vt_log_override "$abs" "$sid"
  exit 0
fi

vt_emit_deny "$(vt_gate_directive)"
