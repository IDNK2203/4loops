#!/usr/bin/env bash
# vt-transition.sh <id> <new-state>
# Finds the row with <id> in the kanban table and moves its content
# from the current state column to the target state column. Refreshes counts.
set -euo pipefail

ID="${1:?usage: vt-transition <id> <new-state>}"
NEW_STATE="${2:?usage: vt-transition <id> <new-state>}"

case "$NEW_STATE" in
  backlog|planning|in-progress|testing|done) ;;
  *) echo "Invalid state: $NEW_STATE (valid: backlog|planning|in-progress|testing|done)" >&2; exit 1 ;;
esac

case "$NEW_STATE" in
  backlog)     NEW_COL=1 ;;
  planning)    NEW_COL=2 ;;
  in-progress) NEW_COL=3 ;;
  testing)     NEW_COL=4 ;;
  done)        NEW_COL=5 ;;
esac

VT_DIR="${VT_DIR:-./.vibe-table}"
BOARD="$VT_DIR/board.md"

if [ ! -f "$BOARD" ]; then
  echo "No board yet — run /vt:configure first to set up your board." >&2; exit 1
fi

# Find the row + identify current state column + extract content
RESULT=$(awk -v id="$ID" -F'|' '
  /^\| Backlog \| Planning \| In Progress \| Testing \| Done \|$/ { in_kanban = 1; next }
  in_kanban && /^\| --/ { in_body = 1; next }
  in_body && /^\|/ && index($0, "**" id "**") {
    for (i = 2; i <= 6; i++) {
      cell = $i
      gsub(/^ +| +$/, "", cell)
      if (index(cell, "**" id "**")) {
        print (i - 1) "|" cell
        exit
      }
    }
  }
' "$BOARD")

if [ -z "$RESULT" ]; then
  echo "Story ${ID} not found in board" >&2; exit 1
fi

OLD_COL="${RESULT%%|*}"
CONTENT="${RESULT#*|}"

case "$OLD_COL" in
  1) OLD_STATE="backlog" ;;
  2) OLD_STATE="planning" ;;
  3) OLD_STATE="in-progress" ;;
  4) OLD_STATE="testing" ;;
  5) OLD_STATE="done" ;;
esac

if [ "$OLD_COL" = "$NEW_COL" ]; then
  echo "${ID} already in ${NEW_STATE}" >&2; exit 0
fi

# Rebuild the board as a DENSE grid, moving ID's cell to NEW_COL. Co-located
# stories on ID's row are preserved (dense storage = many stories per row), so we
# can't just replace the row — we re-grid the whole body.
awk -v id="$ID" -v newcol="$NEW_COL" '
  BEGIN { FS = "|" }
  /^\| Backlog \| Planning \| In Progress \| Testing \| Done \|$/ { print; hdr = 1; next }
  hdr && /^\| --/ { print; inbody = 1; next }
  inbody && /^\|/ {
    for (i = 2; i <= 6; i++) {
      c = $i; gsub(/^ +| +$/, "", c)
      if (c == "") continue
      col = (index(c, "**" id "**") > 0) ? newcol : (i - 1)
      cells[col, ++n[col]] = c
    }
    next
  }
  !inbody { print }
  END {
    rows = 0
    for (col = 1; col <= 5; col++) if (n[col] > rows) rows = n[col]
    for (i = 1; i <= rows; i++) {
      line = "|"
      for (col = 1; col <= 5; col++) {
        c = (i <= n[col]) ? cells[col, i] : ""
        line = line " " c " |"
      }
      print line
    }
  }
' "$BOARD" > "${BOARD}.tmp" && mv "${BOARD}.tmp" "$BOARD"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
"$SCRIPT_DIR/vt-refresh-counts.sh"

TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
printf "%s\t%s\t%s→%s\n" "$TS" "$ID" "$OLD_STATE" "$NEW_STATE" >> "$VT_DIR/transitions.log"

# Refresh activity slices in current-priorities.md so it doesn't lie between /vt:today runs.
# No-op if priorities file doesn't exist yet. Preserves existing stamps + focus.
# shellcheck source=./vt-priorities-lib.sh
source "$SCRIPT_DIR/vt-priorities-lib.sh"
refresh_priorities_activity

echo "${ID}: ${OLD_STATE} → ${NEW_STATE}"
