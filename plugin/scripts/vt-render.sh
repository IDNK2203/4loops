#!/usr/bin/env bash
# vt-render.sh — pass through header + Projects table, then emit display table.
# Default: single full-width 5-column kanban table.
#
# Usage:
#   vt-render.sh                          full board, 5-col table, cap 5 per state
#   vt-render.sh <state>                  single column for <state>, 5 rows
#   vt-render.sh <state> <count>          single column for <state>, <count> rows
#   vt-render.sh --project <P>            filter rows to project (combinable)
#   vt-render.sh --all                    no per-state cap (overrides count)
#
# <state> is one of: backlog | planning | in-progress | testing | done
set -euo pipefail

VT_DIR="${VT_DIR:-./.vibe-table}"
BOARD="$VT_DIR/board.md"

if [ ! -f "$BOARD" ]; then
  echo "No board yet. Run /vt:draft <title> --project <P> to create your first story." >&2
  exit 0
fi

STATE=""
COUNT=5
PROJECT=""
SHOW_ALL=false

while [ $# -gt 0 ]; do
  case "$1" in
    --project)  PROJECT="$2"; shift 2 ;;
    --all)      SHOW_ALL=true; shift ;;
    --count)    COUNT="$2"; shift 2 ;;
    backlog|planning|in-progress|testing|done) STATE="$1"; shift ;;
    [0-9]*)     COUNT="$1"; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

$SHOW_ALL && COUNT=99999

case "$STATE" in
  backlog)     COL=1 ;;
  planning)    COL=2 ;;
  in-progress) COL=3 ;;
  testing)     COL=4 ;;
  done)        COL=5 ;;
  "")          COL=0 ;;
esac

awk -F'|' \
  -v col="$COL" -v cap="$COUNT" -v project="$PROJECT" \
  '
  BEGIN {
    state_names[1] = "Backlog"
    state_names[2] = "Planning"
    state_names[3] = "In Progress"
    state_names[4] = "Testing"
    state_names[5] = "Done"
  }

  /^\| Backlog \| Planning \| In Progress \| Testing \| Done \|$/ { in_kanban = 1; next }
  in_kanban && /^\| --/ { in_body = 1; next }
  in_body && /^\|/ {
    for (i = 2; i <= 6; i++) {
      cell = $i
      gsub(/^ +| +$/, "", cell)
      if (cell == "") continue
      if (project != "") {
        pattern = "\\[" project "\\]"
        if (cell !~ pattern) continue
      }
      idx = i - 1
      cells[idx, ++count[idx]] = cell
    }
    next
  }
  !in_kanban { print }

  END {
    print ""

    if (col != 0) {
      # Single-state render
      print "| " state_names[col] " |"
      print "| --- |"
      n = (count[col] < cap) ? count[col] : cap
      if (n == 0) { print "| _(empty)_ |"; exit }
      for (i = 1; i <= n; i++) {
        printf "| %s |\n", cells[col, i]
      }
      exit
    }

    # Full board — single 5-column table
    print "| Backlog | Planning | In Progress | Testing | Done |"
    print "| ------- | -------- | ----------- | ------- | ---- |"
    n1 = (count[1] < cap) ? count[1] : cap
    n2 = (count[2] < cap) ? count[2] : cap
    n3 = (count[3] < cap) ? count[3] : cap
    n4 = (count[4] < cap) ? count[4] : cap
    n5 = (count[5] < cap) ? count[5] : cap
    rows = n1
    if (n2 > rows) rows = n2
    if (n3 > rows) rows = n3
    if (n4 > rows) rows = n4
    if (n5 > rows) rows = n5
    if (rows == 0) {
      print "| _(empty)_ | _(empty)_ | _(empty)_ | _(empty)_ | _(empty)_ |"
    } else {
      for (i = 1; i <= rows; i++) {
        c1 = (i <= n1) ? cells[1, i] : ""
        c2 = (i <= n2) ? cells[2, i] : ""
        c3 = (i <= n3) ? cells[3, i] : ""
        c4 = (i <= n4) ? cells[4, i] : ""
        c5 = (i <= n5) ? cells[5, i] : ""
        printf "| %s | %s | %s | %s | %s |\n", c1, c2, c3, c4, c5
      }
    }
  }
' "$BOARD"
