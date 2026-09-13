#!/usr/bin/env bash
# vt-remove.sh <id> [--reason "..."] [--backdate YYYY-MM-DD]
#
# Task CRUD · remove (v2.5 Track D · P0-048). Pulls a story off the grid because it
# should never have been a story — a duplicate, a mis-capture, a typo row. That is
# NOT the same as `abandoned` (real work you decided to drop) or `superseded`
# (replaced by another story), which keep their own archive trail.
#
# Append-only and reversible, like every other exit from the board:
#   record → archive/<month>/removed.md ;  put it back with `vt-flush.sh --restore <id>`.
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=./vt-priorities-lib.sh
source "$SCRIPT_DIR/vt-priorities-lib.sh"
# shellcheck source=./vt-drift-lib.sh
source "$SCRIPT_DIR/vt-drift-lib.sh"
# shellcheck source=./vt-board-lib.sh
source "$SCRIPT_DIR/vt-board-lib.sh"

ID=""; REASON=""; BACKDATE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --reason)   REASON="${2:-}"; shift 2 ;;
    --backdate) BACKDATE="${2:-}"; shift 2 ;;
    *) [ -z "$ID" ] && ID="$1"; shift ;;
  esac
done
[ -n "$ID" ] || { echo "usage: vt-remove.sh <id> [--reason \"...\"] [--backdate YYYY-MM-DD]" >&2; exit 1; }
[ -f "$BOARD" ] || { echo "No board yet — run /4loops:configure first." >&2; exit 1; }

STATE=$(story_state "$ID")
[ -n "$STATE" ] || { echo "Story ${ID} not found in board" >&2; exit 1; }

TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
if [ -n "$BACKDATE" ]; then
  BTS=$(vt_backdate_ts "$BACKDATE"); if [ -n "$BTS" ]; then TS="$BTS"; else BACKDATE=""; fi
fi
recdate="${BACKDATE:-$(iso_today)}"
month=${recdate:0:7}

CELL=$(vt_cell_get "$ID"); [ -z "$CELL" ] && CELL="**$ID**"
REASON="${REASON//|/│}"
afile="$VT_DIR/archive/$month/removed.md"
mkdir -p "$(dirname "$afile")"
[ -f "$afile" ] || printf '# Archive — removed\n\n' > "$afile"
printf -- '- %s · removed %s%s\n' "$CELL" "$recdate" "${REASON:+ (${REASON})}" >> "$afile"

_remove_board_rows "$ID"
refresh_counts
printf '%s\t%s\t%s\n' "$TS" "$ID" "${STATE}→removed${REASON:+ reason:${REASON}}" >> "$VT_DIR/transitions.log"
refresh_priorities_activity

echo "${ID}: ${STATE} → removed (archived → archive/${month}/removed.md)"
echo "  reversible: vt-flush.sh --restore ${ID} --to ${STATE}"
