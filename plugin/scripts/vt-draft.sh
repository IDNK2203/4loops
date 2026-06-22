#!/usr/bin/env bash
# vt-draft.sh <project> <title> [why] [context] [--type dev|modeling]
# Creates a new story-draft row in the Backlog column of the kanban table.
# Auto-registers the project in the Projects table if first time seen.
#
# --type sets the story's objective shape (v2 / W1):
#   dev      — objective fixed + testable; DONE = tests pass / shipped (default).
#   modeling — objective fluid; DONE = a coherent + traceable decision log.
# Default `dev` rows are written byte-identical to v1 (no type token) for back-compat.
set -euo pipefail

# Pull the --type flag out of anywhere in the arg list; the rest stay positional.
TYPE="dev"
ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --type) TYPE="${2:-dev}"; shift 2 ;;
    *)      ARGS+=("$1"); shift ;;
  esac
done
set -- ${ARGS[@]+"${ARGS[@]}"}

PROJECT="${1:?usage: vt-draft <project> <title> [why] [context] [--type dev|modeling]}"
TITLE="${2:?usage: vt-draft <project> <title> [why] [context] [--type dev|modeling]}"
WHY="${3:-}"
CONTEXT="${4:-}"
case "$TYPE" in dev|modeling) ;; *) TYPE="dev" ;; esac

# The board is parsed with awk -F'|', so a real '|' in any field — even
# backslash-escaped — splits the row and truncates the cell (+ its archive
# record). Swap it for the vertical-bar lookalike │ (U+2502): renders the same,
# never splits. Applies to the board cell, story_title, and the archive record.
PROJECT="${PROJECT//|/│}"
TITLE="${TITLE//|/│}"
WHY="${WHY//|/│}"
CONTEXT="${CONTEXT//|/│}"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
"$SCRIPT_DIR/vt-init.sh" >/dev/null

VT_DIR="${VT_DIR:-./.4loops}"
BOARD="$VT_DIR/board.md"

ID=$("$SCRIPT_DIR/vt-next-id.sh" "$PROJECT")

CELL="[${PROJECT}] **${ID}** ${TITLE}"
[ "$TYPE" != "dev" ] && CELL="${CELL} — type: ${TYPE}"
[ -n "$WHY" ] && CELL="${CELL} — why: ${WHY}"
[ -n "$CONTEXT" ] && CELL="${CELL} — context: \`${CONTEXT}\`"

# Auto-register project in Projects table if not already present
PROJECT_EXISTS=$(awk -v proj="$PROJECT" -F'|' '
  /^## Projects$/ { in_projects = 1; next }
  /^---$/ && in_projects { exit }
  in_projects && /^\|/ {
    key = $2
    gsub(/^ +| +$/, "", key)
    if (key == proj) { print "yes"; exit }
  }
' "$BOARD")

if [ "$PROJECT_EXISTS" != "yes" ]; then
  # Insert the new project row at the end of the Projects table body
  # (right before the trailing blank line that precedes "---").
  awk -v proj="$PROJECT" '
    /^## Projects$/ { in_projects = 1; print; next }
    in_projects && /^\| -+/ { in_body = 1; print; next }
    in_body && /^$/ {
      printf "| %s | TBD | — |\n", proj
      in_body = 0
      in_projects = 0
    }
    { print }
  ' "$BOARD" > "${BOARD}.tmp" && mv "${BOARD}.tmp" "$BOARD"
fi

# Append a new row to the kanban; story in Backlog (col 1), empty elsewhere
NEW_ROW="| ${CELL} |  |  |  |  |"
echo "$NEW_ROW" >> "$BOARD"

# Densify: collapse the appended sparse row into the top-aligned grid.
"$SCRIPT_DIR/vt-repack.sh"
"$SCRIPT_DIR/vt-refresh-counts.sh"

TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
printf "%s\t%s\t%s\n" "$TS" "$ID" "∅→backlog" >> "$VT_DIR/transitions.log"

echo "Created ${ID}: ${TITLE}"
