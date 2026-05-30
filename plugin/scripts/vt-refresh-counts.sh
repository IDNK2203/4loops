#!/usr/bin/env bash
# vt-refresh-counts.sh — scan kanban rows in board.md and update **Counts:** line.
set -euo pipefail

VT_DIR="${VT_DIR:-./.vibe-table}"
BOARD="$VT_DIR/board.md"

[ ! -f "$BOARD" ] && exit 0

COUNTS=$(awk -F'|' '
  /^\| Backlog \| Planning \| In Progress \| Testing \| Done \|$/ { in_kanban = 1; next }
  in_kanban && /^\| --/ { in_body = 1; next }
  in_body && /^\|/ {
    for (i = 2; i <= 6; i++) {
      cell = $i
      gsub(/^ +| +$/, "", cell)
      if (cell != "") states[i-1]++
    }
  }
  END {
    printf "Backlog %d · Planning %d · In Progress %d · Testing %d · Done %d",
      states[1]+0, states[2]+0, states[3]+0, states[4]+0, states[5]+0
  }
' "$BOARD")

# BSD/macOS-compatible in-place edit
sed -i.bak "s|^\*\*Counts:\*\*.*|**Counts:** ${COUNTS}|" "$BOARD"
rm -f "${BOARD}.bak"
