#!/usr/bin/env bash
# vt-repack.sh [exclude-id ...]
# Rewrite board.md's kanban body as a DENSE grid: row i holds the i-th story of
# each column, all columns top-aligned (no staircase). Optionally omit the given
# story IDs (used by the weekly rollover to drop archived stories). Idempotent —
# repacking an already-dense board is a no-op.
#
# Everything above the kanban header (title, Counts, Projects table, ---) and the
# header+separator are passed through untouched; only the body rows are re-gridded.
set -euo pipefail

VT_DIR="${VT_DIR:-./.4loops}"
BOARD="$VT_DIR/board.md"
[ -f "$BOARD" ] || exit 0

EXCLUDE=" $* "   # space-delimited id list, "" when no excludes

awk -v exclude="$EXCLUDE" '
  function excluded(c,   id) {
    if (match(c, /\*\*[A-Za-z0-9]+-[0-9]+\*\*/)) {
      id = substr(c, RSTART + 2, RLENGTH - 4)
      return index(exclude, " " id " ") > 0
    }
    return 0
  }
  BEGIN { FS = "|" }
  /^\| Backlog \| Planning \| In Progress \| Testing \| Done \|$/ { print; hdr = 1; next }
  hdr && /^\| --/ { print; inbody = 1; next }
  inbody && /^\|/ {
    for (i = 2; i <= 6; i++) {
      c = $i; gsub(/^ +| +$/, "", c)
      if (c != "" && !excluded(c)) cells[i-1, ++n[i-1]] = c
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
' "$BOARD" > "$BOARD.tmp" && mv "$BOARD.tmp" "$BOARD"
