#!/usr/bin/env bash
# vt-bash-gate.sh — PreToolUse guard for Bash.
#
# A path-only Edit/Write guard is trivially bypassed by shelling out
# (echo >> file, sed -i, tee, rm, mv, cp). This re-derives write targets from the
# command string and runs the IDENTICAL gate check per target, blocking on the
# first gated target. Honors a leading `cd <dir> &&` so relative targets resolve
# in the right place. Residual blind spots (fail-open): glob/quoted args, mid-
# command cd chains & subshells, and arbitrary-code writers (python -c, node -e).
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
  # rm / mv / cp / touch / ln / mkdir — file mutators the redirect parser misses.
  # Grab every arg after the command up to the next separator; flags and
  # non-gated / glob / quoted tokens are filtered out by the per-target check below.
  if printf '%s' "$cmd" | grep -qE '(^|[|;&[:space:]])(rm|mv|cp|touch|ln|mkdir)[[:space:]]'; then
    printf '%s\n' "$cmd" \
      | grep -oE '(^|[|;&[:space:]])(rm|mv|cp|touch|ln|mkdir)[[:space:]]+[^|;&<>]+' \
      | sed -E 's/^[|;&[:space:]]*(rm|mv|cp|touch|ln|mkdir)[[:space:]]+//' \
      | tr ' ' '\n'
  fi
}

targets=$(extract_targets | awk 'NF' | sort -u)
[ -z "$targets" ] && exit 0

base="${cwd:-$PWD}"
# Honor a leading `cd <dir> &&/;` so relative targets resolve in the right place
# (e.g. `cd apps/x && rm public/y`). Best-effort — first cd only.
cd_into=$(printf '%s' "$cmd" | grep -oE '^[[:space:]]*cd[[:space:]]+[^[:space:];&|]+' \
  | sed -E 's/^[[:space:]]*cd[[:space:]]+//' | head -1)
if [ -n "$cd_into" ]; then
  case "$cd_into" in
    /*) base="$cd_into" ;;
    *)  base="${base%/}/$cd_into" ;;
  esac
fi
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
