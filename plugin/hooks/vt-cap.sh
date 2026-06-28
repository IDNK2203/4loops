#!/usr/bin/env bash
# vt-cap.sh — UserPromptExpansion capability minter (v2.4).
#
# The ONLY un-forgeable "the USER initiated this" signal is a user-typed slash
# command: it fires UserPromptExpansion carrying command_name + command_source,
# whereas the agent's skill route is PreToolUse tool_name=Skill — which does NOT
# fire this hook (verified by hand-test 2026-06-28). On a user-typed /4loops:<cmd>
# we record <cmd> as this session's capability; the bash-gate then allows a
# rail-script invocation only if a fresh grant covers it. The token lives at
# .4loops/.cap/<session_id>, a W4 rail-record, so the agent can't forge it.
#
# FAIL-OPEN: any error → write nothing, exit 0 (never block expansion).
set -uo pipefail

HOOK_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCRIPTS_DIR="$HOOK_DIR/../scripts"
# shellcheck source=../scripts/vt-guard-lib.sh
source "$SCRIPTS_DIR/vt-guard-lib.sh" 2>/dev/null || exit 0

input=$(cat 2>/dev/null || printf '{}')
sid=$(vt_json_field "$input" '.session_id')
cwd=$(vt_json_field "$input" '.cwd')
cmd=$(vt_json_field "$input" '.command_name')

[ -z "$cmd" ] && exit 0                       # not a command expansion → nothing to grant
case "$cmd" in 4loops:*) ;; *) exit 0 ;; esac # only our plugin's commands grant capability

root=$(vt_find_workspace_root "${cwd:-$PWD}") || exit 0
[ -z "$root" ] && exit 0
export VT_DIR="$root/.4loops"

vt_write_cap "$sid" "${cmd#4loops:}"          # store the bare command (today|week|sync|capture|…)
exit 0
