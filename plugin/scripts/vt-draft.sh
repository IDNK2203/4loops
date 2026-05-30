#!/usr/bin/env bash
# vt-draft.sh <project> <title> [why] [context]
# Creates a new story-draft row in the Backlog column of the kanban table.
# Auto-registers the project in the Projects table if first time seen.
set -euo pipefail

PROJECT="${1:?usage: vt-draft <project> <title> [why] [context]}"
TITLE="${2:?usage: vt-draft <project> <title> [why] [context]}"
WHY="${3:-}"
CONTEXT="${4:-}"

# Escape pipe chars so they don't break the markdown table
PROJECT="${PROJECT//|/\\|}"
TITLE="${TITLE//|/\\|}"
WHY="${WHY//|/\\|}"
CONTEXT="${CONTEXT//|/\\|}"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
"$SCRIPT_DIR/vt-init.sh" >/dev/null

VT_DIR="${VT_DIR:-./.vibe-table}"
BOARD="$VT_DIR/board.md"

ID=$("$SCRIPT_DIR/vt-next-id.sh" "$PROJECT")

CELL="[${PROJECT}] **${ID}** ${TITLE}"
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

"$SCRIPT_DIR/vt-refresh-counts.sh"

TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
printf "%s\t%s\t%s\n" "$TS" "$ID" "∅→backlog" >> "$VT_DIR/transitions.log"

echo "Created ${ID}: ${TITLE}"
