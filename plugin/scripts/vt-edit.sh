#!/usr/bin/env bash
# vt-edit.sh <id> [--title T] [--why W] [--context C] [--type dev|modeling]
#                 [--due YYYY-MM-DD] [--branch B] [--clear why|context|due|branch|type ...]
#
# Task CRUD · edit (v2.5 Track D · P0-048). Rewrites a story's CONTENT in place —
# title, why, context, type, deadline, branch — without touching its column. State
# moves stay vt-transition.sh's job; this is the "I worded that badly" rail, so you
# never reach for a hand-edit of board.md.
#
# Proof is a re-render from disk: the file is the source of truth, not the summary.
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=./vt-priorities-lib.sh
source "$SCRIPT_DIR/vt-priorities-lib.sh"
# shellcheck source=./vt-board-lib.sh
source "$SCRIPT_DIR/vt-board-lib.sh"

ID=""; SET_TITLE=""; SET_WHY=""; SET_CTX=""; SET_TYPE=""; SET_DUE=""; SET_BRANCH=""; CLEAR=""
have() { case " $HAVE " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
HAVE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --title)   SET_TITLE="${2:-}"; HAVE="$HAVE title";   shift 2 ;;
    --why)     SET_WHY="${2:-}";   HAVE="$HAVE why";     shift 2 ;;
    --context) SET_CTX="${2:-}";   HAVE="$HAVE context"; shift 2 ;;
    --type)    SET_TYPE="${2:-}";  HAVE="$HAVE type";    shift 2 ;;
    --due)     SET_DUE="${2:-}";   HAVE="$HAVE due";     shift 2 ;;
    --branch)  SET_BRANCH="${2:-}";HAVE="$HAVE branch";  shift 2 ;;
    --clear)   CLEAR="$CLEAR ${2:-}"; shift 2 ;;
    -*) echo "unknown flag: $1" >&2; exit 1 ;;
    *) [ -z "$ID" ] && ID="$1"; shift ;;
  esac
done
[ -n "$ID" ] || { echo "usage: vt-edit.sh <id> [--title T] [--why W] [--context C] [--type dev|modeling] [--due YYYY-MM-DD] [--branch B] [--clear <field> ...]" >&2; exit 1; }
[ -n "$HAVE$CLEAR" ] || { echo "vt-edit: nothing to change — pass at least one --title/--why/--context/--type/--due/--branch/--clear." >&2; exit 1; }

[ -f "$BOARD" ] || { echo "No board yet — run /4loops:configure first." >&2; exit 1; }
CELL=$(vt_cell_get "$ID")
[ -n "$CELL" ] || { echo "Story ${ID} not found in board" >&2; exit 1; }

# The board is parsed with awk -F'|' — a real pipe would split the cell.
sanitize() { printf '%s' "${1//|/│}"; }

PROJ=$(vt_cell_project "$CELL")
TITLE=$(vt_cell_title "$CELL")
TYPE=$(vt_cell_field "$CELL" type)
DUE=$(vt_cell_field "$CELL" due)
WHY=$(vt_cell_field "$CELL" why)
CTX=$(vt_cell_field "$CELL" context)
BRANCH=$(vt_cell_field "$CELL" branch)

have title   && TITLE=$(sanitize "$SET_TITLE")
have why     && WHY=$(sanitize "$SET_WHY")
have branch  && BRANCH=$(sanitize "$SET_BRANCH")
have context && CTX=$(vt_ctx_render "$(sanitize "$SET_CTX")")
if have type; then
  case "$SET_TYPE" in dev|modeling) TYPE="$SET_TYPE" ;;
    *) echo "--type must be dev|modeling (got '$SET_TYPE')" >&2; exit 1 ;; esac
fi
if have due; then
  case "$SET_DUE" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) DUE="$SET_DUE" ;;
    *) echo "--due wants YYYY-MM-DD (got '$SET_DUE'); use --clear due to drop it." >&2; exit 1 ;; esac
fi
for f in $CLEAR; do
  case "$f" in
    why) WHY="" ;; context) CTX="" ;; due) DUE="" ;; branch) BRANCH="" ;; type) TYPE="dev" ;;
    *) echo "--clear takes why|context|due|branch|type (got '$f')" >&2; exit 1 ;;
  esac
done
[ -n "$TITLE" ] || { echo "vt-edit: a story needs a title." >&2; exit 1; }

NEW=$(vt_cell_build "$PROJ" "$ID" "$TITLE" "$TYPE" "$DUE" "$WHY" "$CTX" "$BRANCH")
[ "$NEW" = "$CELL" ] && { echo "${ID}: no change."; exit 0; }

vt_cell_replace "$ID" "$NEW"
"$SCRIPT_DIR/vt-refresh-counts.sh"
printf '%s\t%s\t%s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$ID" "edited" >> "$VT_DIR/transitions.log"
refresh_priorities_activity

echo "${ID}: edited"
echo "  was: ${CELL}"
echo "  now: ${NEW}"
