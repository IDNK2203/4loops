#!/usr/bin/env bash
# vt-repack.sh [exclude-id ...]
# Rewrite board.md's kanban body as a DENSE grid: row i holds the i-th story of
# each column, all columns top-aligned (no staircase). Optionally omit the given
# story IDs (used by the weekly rollover to drop archived stories). Idempotent —
# repacking an already-dense board is a no-op.
#
# Shape (v2.5 Track D): the board is the ACTIVE pipeline — Planning | In Progress |
# Testing | Done. A legacy Backlog column is preserved only while it still holds
# cells (so repacking is never lossy); the moment it empties, the board is written
# out in the 4-column shape. `vt-migrate-backlog.sh` is the scripted way off it.
#
# Everything above the kanban header (title, Counts, Projects table, ---) is passed
# through untouched; the header + separator are re-emitted in the surviving shape.
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
  $0 == "| Backlog | Planning | In Progress | Testing | Done |" { legacy = 1; hdr = 1; next }
  $0 == "| Planning | In Progress | Testing | Done |"           { legacy = 0; hdr = 1; next }
  hdr && /^\| --/ { inbody = 1; next }
  inbody && /^\|/ {
    hi = legacy ? 6 : 5
    for (i = 2; i <= hi; i++) {
      c = $i; gsub(/^ +| +$/, "", c)
      if (c != "" && !excluded(c)) { col = legacy ? i - 1 : i; cells[col, ++n[col]] = c }
    }
    next
  }
  !inbody { print }
  END {
    if (!hdr) exit                       # no kanban header seen — pass the file through untouched
    lo = (n[1] + 0 > 0) ? 1 : 2          # keep the legacy pen only while it holds work
    if (lo == 1) {
      print "| Backlog | Planning | In Progress | Testing | Done |"
      print "| ------- | -------- | ----------- | ------- | ---- |"
    } else {
      print "| Planning | In Progress | Testing | Done |"
      print "| -------- | ----------- | ------- | ---- |"
    }
    rows = 0
    for (col = lo; col <= 5; col++) if (n[col] > rows) rows = n[col]
    for (i = 1; i <= rows; i++) {
      line = "|"
      for (col = lo; col <= 5; col++) {
        c = (i <= n[col]) ? cells[col, i] : ""
        line = line " " c " |"
      }
      print line
    }
  }
' "$BOARD" > "$BOARD.tmp" && mv "$BOARD.tmp" "$BOARD"
