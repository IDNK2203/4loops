#!/usr/bin/env bash
# vt-scope-list.sh [PROJECT-KEY|all] — list ephemeral scope docs (read-only).
# Default: all projects under $VT_DIR/tasks/.
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=./vt-store-lib.sh
source "$SCRIPT_DIR/vt-store-lib.sh"
SCRIPT_DIR_SCOPE="$SCRIPT_DIR"
# shellcheck source=./vt-scope-lib.sh
source "$SCRIPT_DIR/vt-scope-lib.sh"

VT_DIR="${VT_DIR:-./.4loops}"
FILTER="${1:-all}"
vt_scope_ensure
d=$(vt_tasks_dir)

list_one() {
  local path="$1" id proj title due impact resource promoted
  id=$(vt_scope_get "$path" id)
  proj=$(vt_scope_get "$path" project)
  title=$(vt_scope_get "$path" title)
  due=$(vt_scope_get "$path" deadline)
  impact=$(vt_scope_get "$path" impact)
  resource=$(vt_scope_get "$path" resource)
  promoted=$(vt_scope_get "$path" promoted_at)
  # trim long fields for table
  impact_short="${impact:0:40}"
  [ "${#impact}" -gt 40 ] && impact_short="${impact_short}…"
  printf '%-8s %-6s  due=%-10s  res=%-12s  %s\n' \
    "${id:-?}" "${proj:-?}" "${due:--}" "${resource:--}" "${title:-?}"
  printf '         impact: %s\n' "${impact_short:--}"
}

shopt -s nullglob
found=0
case "$FILTER" in
  all|'')
    for f in "$d"/*/*.md; do
      list_one "$f"
      found=1
    done
    ;;
  *)
    if [ ! -d "$d/$FILTER" ]; then
      echo "no scope docs for project: $FILTER" >&2
      exit 0
    fi
    for f in "$d/$FILTER"/*.md; do
      list_one "$f"
      found=1
    done
    ;;
esac

if [ "$found" = 0 ]; then
  echo "(no scope docs under $d)"
fi
