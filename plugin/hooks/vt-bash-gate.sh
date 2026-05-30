#!/usr/bin/env bash
# vt-bash-gate.sh — PreToolUse guard for Bash.
#
# A path-only Edit/Write guard is trivially bypassed by shelling out
# (echo >> file, sed -i, tee). This re-derives write targets from the command
# string and runs the IDENTICAL gate check per target, blocking on the first
# gated target. Known blind spot (inherited from DevOS, documented): mv / cp /
# python -c "open(...)" / node -e writes are not detected.
#
# FAIL-OPEN: any error → allow.
set -uo pipefail

HOOK_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCRIPTS_DIR="$HOOK_DIR/../scripts"
# shellcheck source=../scripts/vt-guard-lib.sh
source "$SCRIPTS_DIR/vt-guard-lib.sh" 2>/dev/null || exit 0

input=$(cat 2>/dev/null || printf '{}')
cmd=$(vt_json_field "$input" '.tool_input.command')
[ -z "$cmd" ] && exit 0
sid=$(vt_json_field "$input" '.session_id')
cwd=$(vt_json_field "$input" '.cwd')

# Inline `VAR=1 cmd` prefixes never reach the hook's env — grep the command too.
override=0
[ "${VT_ALLOW_STALE_GATE:-}" = "1" ] && override=1
case "$cmd" in *VT_ALLOW_STALE_GATE=1*) override=1 ;; esac

# Extract candidate write targets: > / >> redirects, tee [-a] files, sed -i.
extract_targets() {
  # redirects ( > file , >> file ) — exclude >& and >(...) process subs
  printf '%s\n' "$cmd" | grep -oE '>>?[[:space:]]*[^[:space:]|&;<>()]+' \
    | sed -E 's/^>>?[[:space:]]*//'
  # tee [-a] file ...
  if printf '%s' "$cmd" | grep -qE '(^|[|;&[:space:]])tee([[:space:]]+-a)?[[:space:]]'; then
    printf '%s\n' "$cmd" | grep -oE 'tee([[:space:]]+-a)?[[:space:]]+[^|&;<>]+' \
      | sed -E 's/^tee([[:space:]]+-a)?[[:space:]]+//' | tr ' ' '\n'
  fi
  # sed -i … <file> : take the last token of the command (BSD/GNU both vary)
  if printf '%s' "$cmd" | grep -qE '(^|[|;&[:space:]])sed[[:space:]]+-i'; then
    printf '%s\n' "$cmd" | awk '{print $NF}'
  fi
}

targets=$(extract_targets | awk 'NF' | sort -u)
[ -z "$targets" ] && exit 0

base="${cwd:-$PWD}"
while IFS= read -r t; do
  [ -z "$t" ] && continue
  # skip tokens with shell-expansion / quoting chars (false-positive prone)
  case "$t" in *['"'\$\`\\\*]*) continue ;; esac
  abs=$(vt_resolve_abs "$t" "$base")
  root=$(vt_find_workspace_root "$abs") || continue
  [ -z "$root" ] && continue
  export VT_DIR="$root/.vibe-table"
  # shellcheck source=../scripts/vt-priorities-lib.sh
  source "$SCRIPTS_DIR/vt-priorities-lib.sh" 2>/dev/null || continue
  vt_rail_armed || continue
  vt_is_exempt "$abs" "$root" && continue
  vt_is_gated  "$abs" "$root" || continue
  if ! vt_gate_active; then vt_mark_session_cleared "$sid"; continue; fi
  vt_session_cleared "$sid" && continue
  if [ "$override" = "1" ]; then vt_log_override "$abs" "$sid"; continue; fi
  # gated + active + not cleared + no override → block.
  vt_emit_deny "$(vt_gate_directive)"
done <<EOF
$targets
EOF

exit 0
