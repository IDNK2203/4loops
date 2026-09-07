#!/usr/bin/env bash
# vt-merge.sh <from-id> <into-id> [--backdate YYYY-MM-DD]
#
# Task CRUD · merge (v2.5 Track D · P0-048). Two rows are the same piece of work:
# <from-id> is folded into <into-id> and leaves the grid. The survivor keeps its
# own column and picks up what the merged row was carrying — its title is recorded
# in the survivor's why, and a deadline is kept if it is the tighter of the two.
#
# Append-only and reversible, like abandon: the merged row's full cell goes to
# archive/<month>/merged.md, and `vt-flush.sh --restore <from-id>` puts it back.
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=./vt-priorities-lib.sh
source "$SCRIPT_DIR/vt-priorities-lib.sh"
# shellcheck source=./vt-drift-lib.sh
source "$SCRIPT_DIR/vt-drift-lib.sh"
# shellcheck source=./vt-board-lib.sh
source "$SCRIPT_DIR/vt-board-lib.sh"

FROM=""; INTO=""; BACKDATE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --backdate) BACKDATE="${2:-}"; shift 2 ;;
    *) if [ -z "$FROM" ]; then FROM="$1"; elif [ -z "$INTO" ]; then INTO="$1"; fi; shift ;;
  esac
done
[ -n "$FROM" ] && [ -n "$INTO" ] || { echo "usage: vt-merge.sh <from-id> <into-id> [--backdate YYYY-MM-DD]" >&2; exit 1; }
[ "$FROM" != "$INTO" ] || { echo "vt-merge: a story cannot be merged into itself." >&2; exit 1; }
[ -f "$BOARD" ] || { echo "No board yet — run /4loops:configure first." >&2; exit 1; }

FROM_STATE=$(story_state "$FROM"); [ -n "$FROM_STATE" ] || { echo "Story ${FROM} not found in board" >&2; exit 1; }
INTO_STATE=$(story_state "$INTO"); [ -n "$INTO_STATE" ] || { echo "Story ${INTO} not found in board" >&2; exit 1; }

FROM_CELL=$(vt_cell_get "$FROM")
INTO_CELL=$(vt_cell_get "$INTO")
FROM_TITLE=$(vt_cell_title "$FROM_CELL")
FROM_DUE=$(vt_cell_field "$FROM_CELL" due)

PROJ=$(vt_cell_project "$INTO_CELL")
TITLE=$(vt_cell_title "$INTO_CELL")
TYPE=$(vt_cell_field "$INTO_CELL" type)
DUE=$(vt_cell_field "$INTO_CELL" due)
WHY=$(vt_cell_field "$INTO_CELL" why)
CTX=$(vt_cell_field "$INTO_CELL" context)
BRANCH=$(vt_cell_field "$INTO_CELL" branch)

# Tighter deadline wins — merging must never quietly relax a date you committed to.
if [ -n "$FROM_DUE" ] && { [ -z "$DUE" ] || [ "${FROM_DUE//-/}" -lt "${DUE//-/}" ]; }; then DUE="$FROM_DUE"; fi
note="merged ${FROM}: ${FROM_TITLE}"
WHY="${WHY:+${WHY}; }${note}"
WHY="${WHY//|/│}"

TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
if [ -n "$BACKDATE" ]; then
  BTS=$(vt_backdate_ts "$BACKDATE"); if [ -n "$BTS" ]; then TS="$BTS"; else BACKDATE=""; fi
fi
recdate="${BACKDATE:-$(iso_today)}"; month=${recdate:0:7}

afile="$VT_DIR/archive/$month/merged.md"
mkdir -p "$(dirname "$afile")"
[ -f "$afile" ] || printf '# Archive — merged\n\n' > "$afile"
printf -- '- %s · merged %s (merged-into: %s)\n' "$FROM_CELL" "$recdate" "$INTO" >> "$afile"

NEW=$(vt_cell_build "$PROJ" "$INTO" "$TITLE" "$TYPE" "$DUE" "$WHY" "$CTX" "$BRANCH")
vt_cell_replace "$INTO" "$NEW"
_remove_board_rows "$FROM"
refresh_counts
printf '%s\t%s\t%s\n' "$TS" "$FROM" "${FROM_STATE}→merged into:${INTO}" >> "$VT_DIR/transitions.log"
printf '%s\t%s\t%s\n' "$TS" "$INTO" "absorbed:${FROM}" >> "$VT_DIR/transitions.log"
refresh_priorities_activity

echo "${FROM} → ${INTO}: merged (archived → archive/${month}/merged.md)"
echo "  now: ${NEW}"
echo "  reversible: vt-flush.sh --restore ${FROM} --to ${FROM_STATE}"
