#!/usr/bin/env bash
# vt-render.sh — pass through header + Projects table, then emit display.
# Default: single full-width 5-column kanban table with COMPACT cells (ID + title).
# Full why/context is shown in single-state views; --list gives a vertical view.
#
# Usage:
#   vt-render.sh                          full board, compact 5-col kanban, cap 5/state
#   vt-render.sh <state>                  single column for <state> (FULL cells), 5 rows
#   vt-render.sh <state> <count>          single column for <state>, <count> rows
#   vt-render.sh --list                   vertical list (state headers + full cells)
#   vt-render.sh --project <P>            filter rows to project (combinable)
#   vt-render.sh --all                    no per-state cap (overrides count)
#
# <state> is one of: backlog | planning | in-progress | testing | done
set -euo pipefail

VT_DIR="${VT_DIR:-./.4loops}"
BOARD="$VT_DIR/board.md"

if [ ! -f "$BOARD" ]; then
  echo "No board yet. Run /4loops:configure to set up your projects, gates, and this week's focus." >&2
  exit 0
fi

STATE=""
COUNT=5
PROJECT=""
SHOW_ALL=false
LIST=false

while [ $# -gt 0 ]; do
  case "$1" in
    --project)  PROJECT="$2"; shift 2 ;;
    --all)      SHOW_ALL=true; shift ;;
    --count)    COUNT="$2"; shift 2 ;;
    --list)     LIST=true; shift ;;
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
  -v col="$COL" -v cap="$COUNT" -v project="$PROJECT" -v list="$LIST" \
  '
  BEGIN {
    state_names[1] = "Backlog"
    state_names[2] = "Planning"
    state_names[3] = "In Progress"
    state_names[4] = "Testing"
    state_names[5] = "Done"
    MAXTITLE = 28
  }

  # Compact a board cell to "[PROJ] **ID** Title" with the title truncated,
  # dropping the — why: / — context: tail. Preserves the bold **ID** so the
  # truncation never splits a markdown marker.
  function compact(c,   p, t, mark) {
    # A modeling story gets a ◆ glance-marker so the board reads honestly at a
    # glance (detected before the metadata tail is stripped).
    mark = (c ~ /type: modeling/) ? "◆ " : ""
    sub(/ — (why|context|type|due):.*/, "", c)
    if (match(c, /^\[[^]]*\] \*\*[^*]*\*\* /)) {
      p = substr(c, 1, RLENGTH); t = substr(c, RLENGTH + 1)
      if (length(t) > MAXTITLE) t = substr(t, 1, MAXTITLE - 1) "…"
      return p mark t
    }
    return (length(c) > 44) ? substr(c, 1, 43) "…" : c
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

    # Vertical list view — state headers + bulleted FULL cells.
    if (list == "true" && col == 0) {
      for (s = 1; s <= 5; s++) {
        print "**" state_names[s] "**"
        n = (count[s] < cap) ? count[s] : cap
        if (n == 0) { print "- _(empty)_"; print ""; continue }
        for (i = 1; i <= n; i++) print "- " cells[s, i]
        print ""
      }
      exit
    }

    if (col != 0) {
      # Single-state render — FULL cells (this is where why/context lives).
      print "| " state_names[col] " |"
      print "| --- |"
      n = (count[col] < cap) ? count[col] : cap
      if (n == 0) { print "| _(empty)_ |"; exit }
      for (i = 1; i <= n; i++) {
        printf "| %s |\n", cells[col, i]
      }
      exit
    }

    # Full board — single 5-column kanban table with COMPACT cells.
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
        c1 = (i <= n1) ? compact(cells[1, i]) : ""
        c2 = (i <= n2) ? compact(cells[2, i]) : ""
        c3 = (i <= n3) ? compact(cells[3, i]) : ""
        c4 = (i <= n4) ? compact(cells[4, i]) : ""
        c5 = (i <= n5) ? compact(cells[5, i]) : ""
        printf "| %s | %s | %s | %s | %s |\n", c1, c2, c3, c4, c5
      }
    }
  }
' "$BOARD"
