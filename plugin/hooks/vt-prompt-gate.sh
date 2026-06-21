#!/usr/bin/env bash
# vt-prompt-gate.sh — UserPromptSubmit one-shot nudge.
#
# Catches work that never touches a gated file (browser/SaaS/physical). On the
# FIRST prompt of a stale day — gate active, session not cleared, rail armed —
# it INJECTS the ritual directive into Claude's context (additionalContext),
# then writes a per-day marker so it never re-fires that day. We inject rather
# than hard-block (UserPromptSubmit blocking is less battle-tested, and
# discarding the user's prompt is hostile); the hard STOP lives on the
# PreToolUse file-write guards where it's reliable.
#
# FAIL-OPEN: any error → allow.
set -uo pipefail

HOOK_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCRIPTS_DIR="$HOOK_DIR/../scripts"
# shellcheck source=../scripts/vt-guard-lib.sh
source "$SCRIPTS_DIR/vt-guard-lib.sh" 2>/dev/null || exit 0

input=$(cat 2>/dev/null || printf '{}')
sid=$(vt_json_field "$input" '.session_id')
cwd=$(vt_json_field "$input" '.cwd')

# No target path on a prompt → resolve the workspace from cwd.
root=$(vt_find_workspace_root "${cwd:-$PWD}") || exit 0
[ -z "$root" ] && exit 0
export VT_DIR="$root/.4loops"
# shellcheck source=../scripts/vt-priorities-lib.sh
source "$SCRIPTS_DIR/vt-priorities-lib.sh" 2>/dev/null || exit 0

vt_rail_armed            || exit 0   # on-ramp grace
vt_session_cleared "$sid" && exit 0  # this session already reconciled
vt_gate_active           || exit 0   # gate clear → nothing to nudge

marker="$VT_DIR/.prompt-nudged-$(iso_today)"
[ -f "$marker" ] && exit 0           # already nudged once today → step aside
: > "$marker" 2>/dev/null || true

reason="$(vt_gate_directive)"
if command -v jq >/dev/null 2>&1; then
  jq -n --arg r "$reason" \
    '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$r}}'
else
  printf '%s\n' "$reason"            # UserPromptSubmit exit-0 stdout → context
fi
exit 0
