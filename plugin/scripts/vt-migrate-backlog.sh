#!/usr/bin/env bash
# vt-migrate-backlog.sh [--to store|planning] [--only <id> ...] [--dry-run]
#
# The scripted path off the LEGACY Backlog column (v2.5 Track D · Manage).
#
# The board is now the ACTIVE pipeline — Planning → In Progress → Testing → Done —
# and intake is closed: capture lives in the detached store, commitment lives in
# current-priorities.md. Boards written by v1/v2 still carry a Backlog pen full of
# uncommitted work. This moves those cells off it, one of two ways:
#
#   --to store     (default) each cell becomes a store item with lever `later`,
#                  keeping project · title · type · why · deadline. The board row
#                  is dropped and an archive record is written, so nothing is lost.
#   --to planning  the cell is promoted into Planning — for work already committed.
#
# Either way the pen empties, and the board re-renders in the 4-column shape on the
# next write. Never hand-edit board.md; this is the rail.
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=./vt-priorities-lib.sh
source "$SCRIPT_DIR/vt-priorities-lib.sh"
# shellcheck source=./vt-drift-lib.sh
source "$SCRIPT_DIR/vt-drift-lib.sh"
# shellcheck source=./vt-board-lib.sh
source "$SCRIPT_DIR/vt-board-lib.sh"
# shellcheck source=./vt-store-lib.sh
source "$SCRIPT_DIR/vt-store-lib.sh"

TO="store"; DRY=0; ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --to)      TO="${2:-store}"; shift 2 ;;
    --only)    ONLY="${ONLY} ${2:-}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    *) echo "usage: vt-migrate-backlog.sh [--to store|planning] [--only <id> ...] [--dry-run]" >&2; exit 1 ;;
  esac
done
case "$TO" in store|planning) ;; *) echo "--to must be store|planning" >&2; exit 1 ;; esac

[ -f "$BOARD" ] || { echo "No board yet — nothing to migrate." >&2; exit 0; }

if ! vt_board_is_legacy "$BOARD"; then
  echo "migrate: board already has no Backlog column (nothing to do)."
  exit 0
fi

# One "<id>\t<cell>" line per Backlog cell, in grid order.
rows=$(board_rows | awk -F'\t' '$2=="backlog"{print $1 "\t" $3}')
if [ -z "$rows" ]; then
  # Pen is present but empty — a repack drops the column and we are done.
  [ "$DRY" = 1 ] && { echo "migrate: Backlog column is empty; a repack would drop it."; exit 0; }
  "$SCRIPT_DIR/vt-repack.sh"
  "$SCRIPT_DIR/vt-refresh-counts.sh"
  echo "migrate: Backlog column was empty — dropped. Board is the active pipeline now."
  exit 0
fi

# Pull the pieces back out of a rendered cell: [PROJ] **ID** Title — why: … — type: … — due: …
cell_field() { printf '%s' "$1" | sed -nE "s/.* — $2: ([^—]*)( — .*)?$/\\1/p" | sed -E 's/ +$//' | head -1; }
cell_project() { printf '%s' "$1" | sed -nE 's/^\[([^]]*)\].*/\1/p'; }

TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
today=$(iso_today); month=${today:0:7}
afile="$VT_DIR/archive/$month/migrated.md"
moved=""; n=0

while IFS=$'\t' read -r id cell; do
  [ -z "$id" ] && continue
  case "$ONLY" in "") ;; *) case " $ONLY " in *" $id "*) ;; *) continue ;; esac ;; esac
  proj=$(cell_project "$cell"); [ -z "$proj" ] && proj="$(default_project_key)"
  title=$(story_title "$id")
  why=$(cell_field "$cell" why)
  typ=$(story_type "$id"); [ -z "$typ" ] && typ=dev
  due=$(story_deadline "$id")

  if [ "$DRY" = 1 ]; then
    printf -- '- %s → %s  [%s] %s%s%s\n' "$id" "$TO" "$proj" "$title" \
      "${due:+ (due $due)}" "${why:+ — why: $why}"
    n=$((n + 1)); continue
  fi

  if [ "$TO" = "planning" ]; then
    "$SCRIPT_DIR/vt-transition.sh" "$id" planning >/dev/null
    printf '%s\t%s\t%s\n' "$TS" "$id" "backlog→planning (migrate)" >> "$VT_DIR/transitions.log"
  else
    # Store first, board second — a failed capture must not lose the row. Written
    # through the store lib rather than the TSV rail: bash collapses empty tab
    # fields, so a cell with no `why` would slide its deadline into the wrong slot.
    STORE_PROJECT="$proj"; STORE_TITLE="$title"; STORE_TYPE="$typ"
    STORE_WHY="$why"; STORE_DEADLINE="$due"; STORE_LEVER="later"
    vt_store_write_new >/dev/null
    mkdir -p "$(dirname "$afile")"
    [ -f "$afile" ] || printf '# Archive — migrated off Backlog\n\n' > "$afile"
    printf -- '- %s · migrated→store %s\n' "$cell" "$today" >> "$afile"
    _remove_board_rows "$id"
    printf '%s\t%s\t%s\n' "$TS" "$id" "backlog→store (migrate)" >> "$VT_DIR/transitions.log"
  fi
  moved="${moved}${moved:+ }${id}"; n=$((n + 1))
done <<< "$rows"

if [ "$DRY" = 1 ]; then
  echo "migrate (dry-run): ${n} Backlog cell(s) would move → ${TO}."
  exit 0
fi

"$SCRIPT_DIR/vt-repack.sh"
"$SCRIPT_DIR/vt-refresh-counts.sh"
refresh_priorities_activity

left=$(vt_board_backlog_count "$BOARD")
printf 'migrate: %d story(ies) → %s%s. Backlog cells left: %d.\n' \
  "$n" "$TO" "${moved:+ (${moved})}" "$left"
[ "$TO" = "store" ] && [ "$n" -gt 0 ] \
  && echo "  reversible: records kept at archive/${month}/migrated.md; store items carry lever \`later\`."
exit 0
