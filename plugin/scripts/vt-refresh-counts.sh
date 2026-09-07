#!/usr/bin/env bash
# vt-refresh-counts.sh — scan kanban rows in board.md and update **Counts:** line.
# The board is the active pipeline (Planning · In Progress · Testing · Done); a
# legacy Backlog column is counted only while it still holds cells, so a
# pre-migration board never hides work.
set -euo pipefail

VT_DIR="${VT_DIR:-./.4loops}"
BOARD="$VT_DIR/board.md"

[ ! -f "$BOARD" ] && exit 0

COUNTS=$(awk -F'|' '
  $0 == "| Backlog | Planning | In Progress | Testing | Done |" { legacy = 1; in_kanban = 1; next }
  $0 == "| Planning | In Progress | Testing | Done |"           { legacy = 0; in_kanban = 1; next }
  in_kanban && /^\| --/ { in_body = 1; next }
  in_body && /^\|/ {
    hi = legacy ? 6 : 5
    for (i = 2; i <= hi; i++) {
      cell = $i
      gsub(/^ +| +$/, "", cell)
      if (cell != "") states[legacy ? i - 1 : i]++
    }
  }
  END {
    if (states[1] + 0 > 0) printf "Backlog %d · ", states[1]
    printf "Planning %d · In Progress %d · Testing %d · Done %d",
      states[2]+0, states[3]+0, states[4]+0, states[5]+0
  }
' "$BOARD")

# BSD/macOS-compatible in-place edit
sed -i.bak "s|^\*\*Counts:\*\*.*|**Counts:** ${COUNTS}|" "$BOARD"
rm -f "${BOARD}.bak"
