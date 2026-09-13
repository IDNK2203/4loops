#!/usr/bin/env bash
# vt-board-lib.sh — the board's SHAPE, in one place (v2.5 Track D · Manage).
#
# The board is the ACTIVE pipeline only: Planning → In Progress → Testing → Done.
# There is no Backlog column: capture lives in the detached store (.4loops/store/),
# commitment lives in current-priorities.md, and only committed work is on the grid.
#
# v1/v2 boards carried a 5th leading Backlog column. Readers still parse those
# (so you can SEE what needs migrating); writers keep the legacy column only while
# it still holds cells, and drop it the moment it is empty. `vt-migrate-backlog.sh`
# is the scripted path off it. NOT directly invocable.

VT_BOARD_HDR='| Planning | In Progress | Testing | Done |'
VT_BOARD_SEP='| -------- | ----------- | ------- | ---- |'
VT_BOARD_HDR_LEGACY='| Backlog | Planning | In Progress | Testing | Done |'
VT_BOARD_SEP_LEGACY='| ------- | -------- | ----------- | ------- | ---- |'

# 0 iff the board still carries the legacy Backlog column.
vt_board_is_legacy() {
  local b="${1:-${BOARD:-${VT_DIR:-./.4loops}/board.md}}"
  [ -f "$b" ] || return 1
  grep -qxF "$VT_BOARD_HDR_LEGACY" "$b"
}

# How many cells sit in the legacy Backlog column (0 when there is no such column).
vt_board_backlog_count() {
  local b="${1:-${BOARD:-${VT_DIR:-./.4loops}/board.md}}"
  [ -f "$b" ] || { echo 0; return 0; }
  awk -F'|' '
    $0 == "| Backlog | Planning | In Progress | Testing | Done |" { hdr = 1; next }
    hdr && /^\| --/ { body = 1; next }
    body && /^\|/ { c = $2; gsub(/^ +| +$/, "", c); if (c != "") n++ }
    END { print n + 0 }
  ' "$b"
}

# One-line nudge when the legacy pen still holds work (empty otherwise).
vt_board_backlog_notice() {
  local n; n=$(vt_board_backlog_count "${1:-}")
  [ "$n" -gt 0 ] || return 0
  printf '> %d story(ies) still sit in the legacy Backlog column — board intake is closed. Run `vt-migrate-backlog.sh` (→ store, or `--to planning` for committed work).\n' "$n"
}

# ── Cell read / write (task CRUD rails · P0-048) ──────────────────────────────
# A board cell is "[PROJ] **ID** Title" plus an ordered metadata tail of
# " — <key>: <value>" segments (type · due · why · context · branch). These read
# and rewrite it in place — the column never moves, so CRUD is not a transition.

# Full cell text for <id>, or empty.
vt_cell_get() {
  local id="$1" b="${2:-${BOARD:-${VT_DIR:-./.4loops}/board.md}}"
  [ -f "$b" ] || return 0
  awk -F'|' -v id="$id" '
    /^\|/ { for (i = 2; i < NF; i++) { c = $i; gsub(/^ +| +$/, "", c)
              if (index(c, "**" id "**")) { print c; exit } } }
  ' "$b"
}

# One metadata field out of a cell: vt_cell_field "<cell>" why|context|type|due|branch
vt_cell_field() {
  awk -v want="$2" '
    BEGIN { n = split(ARGV[1], seg, / — /); ARGV[1] = ""
            for (i = 2; i <= n; i++) {
              s = seg[i]
              if (match(s, /^[a-z]+: /)) {
                k = substr(s, 1, RSTART + RLENGTH - 3)
                if (k == want) { print substr(s, RLENGTH + 1); exit }
              }
            } }
  ' "$1"
}

# Title (no [PROJ] prefix, no metadata tail) out of a cell.
vt_cell_title() {
  printf '%s' "$1" | sed -E 's/^\[[^]]*\] \*\*[^*]*\*\* //; s/ — (type|due|why|context|branch):.*$//'
}

# Project key out of a cell.
vt_cell_project() { printf '%s' "$1" | sed -nE 's/^\[([^]]*)\].*/\1/p'; }

# Replace the cell holding <id> with <new-cell>, in place, same column.
vt_cell_replace() {
  local id="$1" new="$2" b="${3:-${BOARD:-${VT_DIR:-./.4loops}/board.md}}"
  [ -f "$b" ] || return 1
  awk -F'|' -v id="$id" -v new="$new" '
    /^\|/ {
      # A table row "| a | b |" splits to NF fields with an empty $1 and an empty
      # $NF (the text after the trailing pipe) — the cells are 2..NF-1.
      out = "|"; hit = 0
      for (i = 2; i < NF; i++) {
        c = $i; gsub(/^ +| +$/, "", c)
        if (index(c, "**" id "**")) { c = new; hit = 1 }
        out = out " " c " |"
      }
      if (hit) { print out; next }
    }
    { print }
  ' "$b" > "$b.tmp" && mv "$b.tmp" "$b"
}

# Render a context value: a doc path / URL becomes a markdown link, else a code span.
vt_ctx_render() {
  local p="$1" base
  case "$p" in
    '') return 0 ;;
    \[*\]\(*\)|\`*\`) printf '%s' "$p"; return 0 ;;   # already rendered — keep as is
    */*|http*|*.md|*.markdown|*.txt)
      p="${p%/}"; base="${p##*/}"
      case "$base" in README*|readme*|index*|INDEX*) base="${p%/*}"; base="${base##*/}" ;; esac
      base="${base%.*}"; [ -z "$base" ] && base="link"
      printf '[%s](%s)' "$base" "$1" ;;
    *) printf '`%s`' "$1" ;;
  esac
}

# Assemble a cell from its parts, in the canonical order the renderers expect.
vt_cell_build() {  # <proj> <id> <title> <type> <due> <why> <context> <branch>
  local proj="$1" id="$2" title="$3" type="$4" due="$5" why="$6" ctx="$7" branch="$8" c
  c="[${proj}] **${id}** ${title}"
  [ -n "$type" ] && [ "$type" != "dev" ] && c="${c} — type: ${type}"
  [ -n "$due" ]    && c="${c} — due: ${due}"
  [ -n "$why" ]    && c="${c} — why: ${why}"
  [ -n "$ctx" ]    && c="${c} — context: ${ctx}"
  [ -n "$branch" ] && c="${c} — branch: ${branch}"
  printf '%s' "$c"
}
