#!/usr/bin/env bash
# vt-priorities-lib.sh — sourced library used by vt-week.sh, vt-today.sh and
# vt-priority.sh. Not directly invocable; do not chmod +x.
#
# v2.5 Packet 006 (LOCKED orientation UX):
#   • current-priorities.md = Today + Week as plain markdown checkboxes —
#     `- [ ] ID  title` (open) / `- [x] ID  title` (done). No activity columns.
#   • Week ≤ 5 open items, picked from the store (primary) — board IDs allowed.
#   • Today 2–3, ONLY from the week; a day-add is promoted onto the week.
#   • /week is the ONE-SHOT orientation: print the file → look-back (last week on a
#     new week, since-yesterday otherwise) → set week → set today → gate clears.
#     Standalone /today is a mid-day pull-from-week only.
#   • Board is a separate state check — nothing here writes board.md.
#
# Centralizes: workspace (VT_DIR) resolution, date helpers, priorities file
# read/write, board + store lookups, caps + add rules, orientation renders.

# ── Workspace resolution (Packet 006: VT_DIR / cwd mixup fix) ─────────────────
# Rails must read/write the SAME .4loops the hooks gate on. Hooks walk up from
# the cwd; the rails used to trust a bare relative `./.4loops` (breaks from a
# subdirectory) or whatever VT_DIR the launching shell happened to export (the
# Packet 005 dogfood wrote priorities into a stale mktemp VT_DIR while the gate
# watched the sandbox). Rule: an explicit VT_DIR wins (dry-runs rely on it) but
# is made absolute and cross-checked against the cwd workspace with a loud
# warning on mismatch (VT_DIR_QUIET=1 silences); an unset VT_DIR resolves by
# walking up from the cwd exactly like the hooks do.
_vt_find_up() {
  local d="$1"
  while [ -n "$d" ] && [ "$d" != "/" ] && [ "$d" != "." ]; do
    [ -d "$d/.4loops" ] && { printf '%s' "$d/.4loops"; return 0; }
    d=$(dirname "$d")
  done
  [ -d "/.4loops" ] && { printf '/.4loops'; return 0; }
  return 1
}
_vt_canon() { ( cd "$1" 2>/dev/null && pwd -P ) || printf '%s' "$1"; }
vt_resolve_vt_dir() {
  local cwd_vt="" want="${VT_DIR:-}"
  cwd_vt=$(_vt_find_up "$PWD") || cwd_vt=""
  if [ -z "$want" ]; then
    VT_DIR="${cwd_vt:-$PWD/.4loops}"
  else
    case "$want" in /*) ;; *) want="$PWD/${want#./}" ;; esac      # absolutize
    if [ ! -d "$want" ] && [ -n "$cwd_vt" ] && [ "${VT_DIR}" = "./.4loops" ]; then
      # A script's own relative default, run from a subdirectory: use the workspace.
      want="$cwd_vt"
    fi
    VT_DIR="$want"
    if [ -n "$cwd_vt" ] && [ "${VT_DIR_QUIET:-0}" != "1" ] \
       && [ "$(_vt_canon "$VT_DIR")" != "$(_vt_canon "$cwd_vt")" ]; then
      echo "4loops: VT_DIR=$VT_DIR but this workspace's records are at $cwd_vt — the rails read/write VT_DIR while the gate watches the workspace. Unset VT_DIR (or VT_DIR_QUIET=1 if intended)." >&2
    fi
  fi
  export VT_DIR
}
vt_resolve_vt_dir

BOARD="$VT_DIR/board.md"
PRIORITIES="$VT_DIR/current-priorities.md"
TRANSITIONS="$VT_DIR/transitions.log"
# Append-only focus history (one line per Today/Week/done commit) — "history via
# transitions", NOT a per-day archive file.
PRIORITIES_LOG="$VT_DIR/priorities.log"

# Caps (LOCKED): week ≤ 5 open · today 2–3 (max hard, min advisory).
VT_WEEK_CAP="${VT_WEEK_CAP:-5}"
VT_TODAY_MAX="${VT_TODAY_MAX:-3}"
VT_TODAY_MIN="${VT_TODAY_MIN:-2}"

# Workspace name for the doc title — from the records' location, never the cwd.
vt_workspace_name() { basename "$(cd "$VT_DIR/.." 2>/dev/null && pwd || pwd)"; }

# Focus lines may hold detached-store items (CAP-NNN) next to board stories, so
# the priorities lib needs the store helpers.
# shellcheck source=./vt-store-lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/vt-store-lib.sh"

# Date helpers (BSD/macOS-compatible)
iso_today()      { date +"%Y-%m-%d"; }
iso_week_num()   { date +"%V"; }
iso_year()       { date +"%G"; }

# Validate a YYYY-MM-DD backdate and echo an ISO timestamp at noon UTC for it.
# Echoes nothing + warns to stderr when malformed (caller falls back to "now").
# Noon avoids any tz/DST edge nudging the calendar date. (W2: closes the
# no-backdate gap — retroactive stories/transitions stamp the real date.)
vt_backdate_ts() {
  case "$1" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) printf '%sT12:00:00Z' "$1" ;;
    *) echo "warn: ignoring invalid --backdate '$1' (want YYYY-MM-DD); using now." >&2 ;;
  esac
}

# ── Week-start config (mon default | sun) ─────────────────────────────────────
# The first day of the week is configurable per workspace via .4loops/config
# (`week-start: mon|sun`). Default is Monday (ISO). Everything that needs a week
# boundary — the range label, the staleness number, the rollover marker — routes
# through the helpers below so the two modes stay coherent.
vt_week_start() {
  local cfg="$VT_DIR/config" v=""
  [ -f "$cfg" ] && v=$(awk -F': *' '/^week-start:/{print tolower($2); exit}' "$cfg" 2>/dev/null)
  case "$v" in sun|sunday) echo sun ;; *) echo mon ;; esac
}

# Days to subtract from today to reach the first day of the current week.
_week_back() {
  local dow; dow=$(date +"%u")          # 1=Mon ... 7=Sun
  if [ "$(vt_week_start)" = sun ]; then
    echo $(( dow % 7 ))                  # Sun(7)→0, Mon(1)→1 ... Sat(6)→6
  else
    echo $(( dow - 1 ))                  # Mon(1)→0 ... Sun(7)→6
  fi
}

# Date (YYYY-MM-DD) of the first day of the current week, honoring week-start.
week_start_date() {
  local back; back=$(_week_back)
  date -v-"${back}"d +"%Y-%m-%d" 2>/dev/null || date -d "today -${back} days" +"%Y-%m-%d"
}

# Date (YYYY-MM-DD) of the last day of the current week, honoring week-start.
week_end_date() {
  local back; back=$(_week_back)
  date -v-"${back}"d -v+6d +"%Y-%m-%d" 2>/dev/null || date -d "today -${back} days +6 days" +"%Y-%m-%d"
}

# Week-of-year number for the CURRENT week, honoring week-start. Mon routes
# through iso_week_num (so test stubs of iso_week_num still apply); Sun uses the
# Sunday-based %U. This is the number stamped into current-priorities.md and
# compared by week_stamp_current.
week_num_current() {
  if [ "$(vt_week_start)" = sun ]; then date +"%U"; else iso_week_num; fi
}

# Stable per-week identity for the rollover marker. Mon keeps the exact legacy
# "<isoyear>-W<isoweek>" form (no marker churn / double-rollover on upgrade);
# Sun uses "<year>-U<sunweek>".
week_marker_id() {
  if [ "$(vt_week_start)" = sun ]; then
    echo "$(date +%Y)-U$(date +%U)"
  else
    echo "$(iso_year)-W$(iso_week_num)"
  fi
}

# Returns "YYYY-MM-DD → MM-DD" for the current week (start → end), honoring
# week-start.
iso_week_range() {
  local back start end end_short
  back=$(_week_back)
  start=$(date -v-"${back}"d +"%Y-%m-%d" 2>/dev/null || date -d "today -${back} days" +"%Y-%m-%d")
  end=$(date -v-"${back}"d -v+6d +"%Y-%m-%d" 2>/dev/null || date -d "today -${back} days +6 days" +"%Y-%m-%d")
  end_short=${end#????-}     # strip the year, keep MM-DD
  echo "${start} → ${end_short}"
}

# Read current state of a story from board.md.
# Echoes one of: planning | in-progress | testing | done | "" (not found).
# `backlog` only comes back on a pre-migration board that still carries the
# legacy pen — see vt-migrate-backlog.sh.
story_state() {
  local id="$1"
  [ ! -f "$BOARD" ] && return
  awk -v id="$id" -F'|' '
    BEGIN { states[1] = "backlog"; states[2] = "planning"; states[3] = "in-progress"
            states[4] = "testing"; states[5] = "done" }
    $0 == "| Backlog | Planning | In Progress | Testing | Done |" { legacy = 1; in_kanban = 1; next }
    $0 == "| Planning | In Progress | Testing | Done |"           { legacy = 0; in_kanban = 1; next }
    in_kanban && /^\| --/ { in_body = 1; next }
    in_body && /^\|/ && index($0, "**" id "**") {
      hi = legacy ? 6 : 5
      for (i = 2; i <= hi; i++) {
        cell = $i
        gsub(/^ +| +$/, "", cell)
        if (index(cell, "**" id "**")) {
          print states[legacy ? i - 1 : i]
          exit
        }
      }
    }
  ' "$BOARD"
}

# Return the short title of a story from its row in board.md.
# Strips the leading "[PROJ] **ID** " prefix and any "— why: ..." / "— context: ..." suffix.
story_title() {
  local id="$1"
  [ ! -f "$BOARD" ] && return
  awk -v id="$id" '
    index($0, "**" id "**") {
      # Find the cell containing the ID, then extract title
      n = split($0, cells, "|")
      for (i = 1; i <= n; i++) {
        if (index(cells[i], "**" id "**")) {
          cell = cells[i]
          # Strip leading " [PROJ] **ID** "
          sub(/^ *\[[^]]*\] \*\*[^*]*\*\* */, "", cell)
          # Strip trailing metadata: " — why:/context:/type:/due:/branch: ..."
          sub(/ — (why|context|type|due|branch):.*/, "", cell)
          gsub(/^ +| +$/, "", cell)
          print cell
          exit
        }
      }
    }
  ' "$BOARD"
}

# Return a story's objective type (dev|modeling). Defaults to "dev" when no type
# token is present (v1 rows, and v2 dev rows which omit the token). The matched
# tail is pure ASCII ("type: <word>"), so RSTART/RLENGTH offsets stay byte-safe
# despite the multibyte em-dash elsewhere in the cell.
# CELL-SCOPED: the dense grid packs many stories on one physical line, so we
# isolate THIS story's |-delimited cell before matching — a line scan would grab
# a neighbouring cell's token (the `**id**` anchor makes prefix collisions safe).
story_type() {
  local id="$1"
  [ ! -f "$BOARD" ] && { echo dev; return; }
  awk -v id="$id" '
    index($0, "**" id "**") {
      n = split($0, cells, "|")
      for (i = 1; i <= n; i++) if (index(cells[i], "**" id "**")) {
        if (match(cells[i], /type: [a-z]+/)) {
          t = substr(cells[i], RSTART + 6, RLENGTH - 6)   # "type: " = 6 ASCII bytes
          if (t == "dev" || t == "modeling") { print t; exit }
        }
        print "dev"; exit
      }
      print "dev"; exit
    }
  ' "$BOARD"
}

# Return a story's deadline (YYYY-MM-DD) or empty. ASCII-anchored match keeps
# RSTART/RLENGTH byte-safe past the multibyte em-dash. (W7: deadlines drive
# prioritization + drift.) CELL-SCOPED for the same reason as story_type — the
# dense grid co-locates stories on one line, so match within this cell only.
story_deadline() {
  local id="$1"
  [ ! -f "$BOARD" ] && return
  awk -v id="$id" '
    index($0, "**" id "**") {
      n = split($0, cells, "|")
      for (i = 1; i <= n; i++) if (index(cells[i], "**" id "**")) {
        if (match(cells[i], /due: [0-9]+-[0-9]+-[0-9]+/)) print substr(cells[i], RSTART + 5, 10)  # "due: " = 5 ASCII
        exit
      }
      exit
    }
  ' "$BOARD"
}

# Return a story's bound git branch, or empty. The value is appended as the last
# cell field by vt-draft --branch / vt-transition --branch; it has no spaces (git
# refs don't), so it reads cleanly until the next space or end-of-cell. "branch: "
# is 8 ASCII bytes → RSTART/RLENGTH offsets stay byte-safe past the em-dash.
# CELL-SCOPED for the same reason as story_type — match within THIS story's cell.
# (Build-rail seam: the rail binds its branch check to this instead of plan frontmatter.)
story_branch() {
  local id="$1"
  [ ! -f "$BOARD" ] && return
  awk -v id="$id" '
    index($0, "**" id "**") {
      n = split($0, cells, "|")
      for (i = 1; i <= n; i++) if (index(cells[i], "**" id "**")) {
        if (match(cells[i], /branch: [^ ]+/)) print substr(cells[i], RSTART + 8, RLENGTH - 8)
        exit
      }
      exit
    }
  ' "$BOARD"
}

# Reverse lookup: given a branch name, return the story ID bound to it (or empty).
# The build rail calls this with the current git branch to find the owning story,
# then composes with story_state to enforce "this branch belongs to an active story".
# First match wins; scans the kanban rows (Projects rows carry no branch field).
story_id_by_branch() {
  local want="$1"
  [ -z "$want" ] && return
  [ ! -f "$BOARD" ] && return
  awk -v want="$want" '
    /^\|/ {
      n = split($0, cells, "|")
      for (i = 1; i <= n; i++) {
        c = cells[i]
        if (match(c, /branch: [^ ]+/)) {
          b = substr(c, RSTART + 8, RLENGTH - 8)
          if (b == want && match(c, /\*\*[A-Z0-9]+-[0-9]+\*\*/)) {
            print substr(c, RSTART + 2, RLENGTH - 4); exit
          }
        }
      }
    }
  ' "$BOARD"
}

# Stories that got a transition on/after <date> and are currently active (not
# done / not off-board), minus a space-delimited exclude list. One "<id>  <title>"
# per line. Used by midweek reconciliation (W3) to surface "what landed since you
# last set focus" so priority gets reconsidered, not silently outrun by new work.
stories_since() {
  local since="$1" exclude=" ${2:-} " id t st
  [ -f "$TRANSITIONS" ] || return 0
  awk -F'\t' -v since="$since" '{ d=substr($1,1,10); if (d >= since) print $2 }' "$TRANSITIONS" \
    | awk '!seen[$0]++' \
    | while read -r id; do
        [ -z "$id" ] && continue
        case "$exclude" in *" $id "*) continue ;; esac
        st=$(story_state "$id")
        case "$st" in done|"") continue ;; esac
        t=$(story_title "$id")
        if [ -n "$t" ]; then echo "${id}  ${t}"; else echo "$id"; fi
      done
}


# ── current-priorities.md — read ──────────────────────────────────────────────
# File shape (Packet 006):
#   # Current Priorities — <workspace>
#
#   ## Today (YYYY-MM-DD)
#   - [ ] ID  title
#   - [x] ID  title
#
#   ## Week NN (start → end)
#   - [ ] ID  title
# An empty section renders `- (none)`. An empty stamp (`## Today ()`) = stale.

# Read the date stamp from "## Today (YYYY-MM-DD)" — returns YYYY-MM-DD or empty.
# Uses [(] / [)] character classes — BSD awk rejects literal/escaped parens in regex.
read_today_stamp() {
  [ ! -f "$PRIORITIES" ] && return
  awk '/^## Today [(]/ { match($0, /[(][0-9]+-[0-9]+-[0-9]+[)]/); if (RSTART) print substr($0, RSTART+1, 10); exit }' "$PRIORITIES"
}

# Read the week number from "## Week NN (...)" — returns NN or empty.
read_week_stamp() {
  [ ! -f "$PRIORITIES" ] && return
  awk '/^## Week / { match($0, /Week [0-9]+/); if (RSTART) print substr($0, RSTART+5, RLENGTH-5); exit }' "$PRIORITIES"
}

_section_header_pattern() {
  case "$1" in
    today) printf '^## Today [(]' ;;
    week)  printf '^## Week ' ;;
    *) echo "bad section $1" >&2; return 1 ;;
  esac
}

# Raw lines of a section (between its header and the next "## ").
_section_lines() {
  local hdr; hdr=$(_section_header_pattern "$1") || return 1
  [ ! -f "$PRIORITIES" ] && return 0
  awk -v hdr="$hdr" '$0 ~ hdr { s = 1; next } s && /^## / { exit } s { print }' "$PRIORITIES"
}

# IDs listed in a section (open AND done), in file order. Space-separated.
# Legacy (pre-006) files carried a `Focus: A · B` line — still readable, so an
# upgrade never loses the current focus.
read_focus() {
  local section="$1" ids
  ids=$(_section_lines "$section" | awk '
    /^- \[[ xX]\] / { sub(/^- \[[ xX]\] +/, ""); split($0, a, /[ \t]+/); print a[1] }
  ' | tr '\n' ' ')
  ids="${ids% }"
  if [ -z "$ids" ]; then
    ids=$(_section_lines "$section" | awk '/^Focus: / { sub(/^Focus: /, ""); gsub(/ · /, " "); gsub(/^—$/, ""); print; exit }')
  fi
  printf '%s' "$ids"
}

# IDs checked [x] in a section, in file order.
read_done() {
  _section_lines "$1" | awk '/^- \[[xX]\] / { sub(/^- \[[xX]\] +/, ""); split($0, a, /[ \t]+/); print a[1] }' | tr '\n' ' ' | sed 's/ $//'
}

# ── Store-aware focus items ───────────────────────────────────────────────────
vt_is_cap_id() { case "$1" in CAP-[0-9]*) return 0 ;; *) return 1 ;; esac; }

# Board story IDs in the given columns (space-separated names), in grid order.
board_ids_in() {
  local want=" $* "
  [ -f "$BOARD" ] || return 0
  awk -F'|' -v want="$want" '
    BEGIN { names[1]="backlog"; names[2]="planning"; names[3]="in-progress"; names[4]="testing"; names[5]="done" }
    $0 == "| Backlog | Planning | In Progress | Testing | Done |" { legacy = 1; in_kanban = 1; next }
    $0 == "| Planning | In Progress | Testing | Done |"           { legacy = 0; in_kanban = 1; next }
    in_kanban && /^\| --/ { in_body = 1; next }
    in_body && /^\|/ {
      hi = legacy ? 6 : 5
      for (i = 2; i <= hi; i++) {
        col = legacy ? i - 1 : i
        if (index(want, " " names[col] " ") == 0) continue
        cell = $i; gsub(/^ +| +$/, "", cell)
        if (cell != "" && match(cell, /\*\*[A-Z0-9]+-[0-9]+\*\*/)) print substr(cell, RSTART+2, RLENGTH-4)
      }
    }
  ' "$BOARD" 2>/dev/null
}

# Title for any focus ID (store title for CAP, board title otherwise).
focus_title() {
  local id="$1" p t=""
  if vt_is_cap_id "$id"; then
    p=$(vt_store_item_path "$id")
    if [ -f "$p" ]; then t=$(vt_store_get "$p" title); fi
  else
    t=$(story_title "$id")
  fi
  # A story the weekly rollover archived is off the board but still sits on the week as
  # [x] — fall back to the title the priorities file already recorded, so the look-back
  # reads "[x] API-003  Set up CI", not "[x] API-003  ?".
  if [ -z "$t" ] && [ -f "$PRIORITIES" ]; then
    t=$(awk -v id="$id" '$0 ~ "^- \\[.\\] " id "  " { sub(/^- \[.\] [^ ]+  /, ""); print; exit }' "$PRIORITIES")
  fi
  printf '%s\n' "$t"
}

# Deadline (YYYY-MM-DD) for any focus ID, or empty.
focus_deadline() {
  local id="$1" p
  if vt_is_cap_id "$id"; then
    p=$(vt_store_item_path "$id"); [ -f "$p" ] && vt_store_get "$p" deadline
  else
    story_deadline "$id"
  fi
}

# Short state tag for any focus ID:
#   board → planning|in-progress|testing|done|off-board (backlog: legacy pen only)
#   store → store·<lever> (live) | store·done | store·expired | store·cleared | store·missing
focus_state() {
  local id="$1" p st
  if vt_is_cap_id "$id"; then
    p=$(vt_store_item_path "$id")
    [ -f "$p" ] || { echo "store·missing"; return; }
    st=$(vt_store_get "$p" state)
    case "$st" in
      captured|active) echo "store·$(vt_store_get_lever "$p")" ;;
      *) echo "store·${st:-missing}" ;;
    esac
  else
    st=$(story_state "$id"); echo "${st:-off-board}"
  fi
}

# 0 iff the item is still alive work: a board story in planning/in-progress/
# testing, or a live (captured|active) store item.
focus_alive() {
  case "$(focus_state "$1")" in
    planning|in-progress|testing|store·urgent|store·today|store·later) return 0 ;;
    *) return 1 ;;
  esac
}

# 0 iff the item is still OPEN work — not done and not gone. A legacy Backlog
# cell still counts as open until it is migrated; done / archived / expired /
# cleared / off-board do not. This is what the caps count and what carries forward.
focus_open() {
  focus_done "$1" && return 1
  case "$(focus_state "$1")" in
    backlog|planning|in-progress|testing|store·urgent|store·today|store·later) return 0 ;;
    *) return 1 ;;
  esac
}

# 0 iff the item is DONE: checked [x] in the file (either section — a mark
# persists across rewrites), or the board story is in Done, or the store item
# was marked done. Rollover archives Done stories off the board, which is why
# the checkmark is persisted in the file rather than re-derived only.
focus_done() {
  local id="$1"
  case " $(read_done today) $(read_done week) " in *" $id "*) return 0 ;; esac
  case "$(focus_state "$id")" in done|store·done) return 0 ;; esac
  return 1
}

# Live store IDs with a given lever, in ID order.
store_ids_by_lever() {
  local want="$1" d f st
  d=$(vt_store_dir)
  [ -d "$d/items" ] || return 0
  for f in "$d"/items/CAP-*; do
    [ -f "$f" ] || continue
    st=$(vt_store_get "$f" state)
    case "$st" in captured|active) ;; *) continue ;; esac
    [ "$(vt_store_get_lever "$f")" = "$want" ] && basename "$f"
  done
}

# Live store IDs whose deadline falls on/before <date> (YYYY-MM-DD), in ID order.
store_ids_due_by() {
  local by="$1" d f st due
  d=$(vt_store_dir)
  [ -d "$d/items" ] || return 0
  for f in "$d"/items/CAP-*; do
    [ -f "$f" ] || continue
    st=$(vt_store_get "$f" state)
    case "$st" in captured|active) ;; *) continue ;; esac
    due=$(vt_store_get "$f" deadline)
    [ -n "$due" ] || continue
    if [[ "$due" < "$by" || "$due" == "$by" ]]; then basename "$f"; fi
  done
}

# Mark a store item done (captured|active → done). Stays under items/ with
# state=done so it leaves every live pull; logged in store/transitions.log.
vt_store_mark_done() {
  local id="$1" reason="${2:-done}" path from ts
  path=$(vt_store_item_path "$id")
  [ -f "$path" ] || { echo "error: store item not found: $id" >&2; return 1; }
  from=$(vt_store_get "$path" state)
  case "$from" in
    captured|active) ;;
    done) return 0 ;;
    *) echo "error: $id is $from — only a live store item can be marked done." >&2; return 1 ;;
  esac
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  vt_store_set_field "$path" state done
  vt_store_set_field "$path" done_at "$ts"
  vt_store_log_transition "$id" "$from" "done" "$reason"
}

# Append IDs to a space-separated list, skipping duplicates. Echoes the new list.
_merge_ids() {
  local list="$1"; shift
  local id
  for id in "$@"; do
    [ -z "$id" ] && continue
    case " $list " in *" $id "*) ;; *) list="${list:+$list }$id" ;; esac
  done
  printf '%s' "$list"
}

# Remove IDs ($2..) from a space-separated list ($1). Echoes the new list.
_without_ids() {
  local list="$1"; shift
  local out="" id
  for id in $list; do
    case " $* " in *" $id "*) ;; *) out="${out:+$out }$id" ;; esac
  done
  printf '%s' "$out"
}

# First N IDs of a list.
_head_ids() {
  local n="$1" list="$2" out="" id i=0
  for id in $list; do
    [ "$i" -ge "$n" ] && break
    out="${out:+$out }$id"; i=$((i+1))
  done
  printf '%s' "$out"
}
_count_ids() { local n=0 id; for id in $1; do n=$((n+1)); done; printf '%s' "$n"; }

# Open (not done, not gone) IDs of a section, in file order.
open_ids() {
  local out="" id
  for id in $(read_focus "$1"); do focus_open "$id" && out="${out:+$out }$id"; done
  printf '%s' "$out"
}

# Carry-forward = a section's open items. What /week offers first, what a
# follow-up day continues from.
compute_carry_forward() { open_ids "$1"; }

# ── Caps + add rules (LOCKED) ─────────────────────────────────────────────────
# Week: ≤ VT_WEEK_CAP open. $1 = total open after the change, $2 = how many of
# those were already on the week, $3 = how many are new.
_week_cap_ok() {
  local n="$1" already="$2" new="$3" room
  if [ "$n" -gt "$VT_WEEK_CAP" ]; then
    room=$(( VT_WEEK_CAP - already )); [ "$room" -lt 0 ] && room=0
    echo "4loops: week cap is ${VT_WEEK_CAP} open items — ${already} already on the week, so at most ${room} new (you named ${new}). Trim the list, or mark something done first (vt-priority.sh done <ID>)." >&2
    return 1
  fi
  return 0
}

# Check a proposed week list ($1) of resolved IDs against the cap.
check_week_cap() {
  local ids="$1" n=0 id already=0 new=0
  for id in $ids; do
    focus_done "$id" && continue
    n=$((n+1))
    case " $(read_focus week) " in *" $id "*) already=$((already+1)) ;; *) new=$((new+1)) ;; esac
  done
  _week_cap_ok "$n" "$already" "$new"
}

week_cap_left() {
  local left=$(( VT_WEEK_CAP - $(_count_ids "$(open_ids week)") ))
  [ "$left" -lt 0 ] && left=0
  printf '%s' "$left"
}

# Today: max VT_TODAY_MAX (hard), min VT_TODAY_MIN (advisory, stderr). $1 = open count.
_today_size_ok() {
  local n="$1"
  if [ "$n" -gt "$VT_TODAY_MAX" ]; then
    echo "4loops: today holds ${VT_TODAY_MIN}–${VT_TODAY_MAX} items (you named ${n}). Pick the ${VT_TODAY_MAX} that matter; the rest stay on the week." >&2
    return 1
  fi
  if [ "$n" -gt 0 ] && [ "$n" -lt "$VT_TODAY_MIN" ]; then
    echo "note: today has ${n} item — the target is ${VT_TODAY_MIN}–${VT_TODAY_MAX} (add one from the week with vt-priority.sh add <ID>)." >&2
  fi
  return 0
}

# Check a resolved today list ($1) against the size rule.
check_today_size() {
  local ids="$1" n=0 id
  for id in $ids; do focus_done "$id" || n=$((n+1)); done
  _today_size_ok "$n"
}

# Count raw tokens ($2..) that would be NEW to list $1 — an ID not on the list,
# or any free text (always new). Lets the rails refuse a cap BEFORE creating
# store items for free text, so a refusal has no side effects.
_count_new_tokens() {
  local list=" $1 "; shift
  local n=0 tok
  for tok in "$@"; do
    [ -z "$tok" ] && continue
    if [[ "$tok" =~ ^[A-Z][A-Z0-9]*-[0-9]+$ ]]; then
      case "$list" in *" $tok "*) ;; *) n=$((n+1)) ;; esac
    else n=$((n+1)); fi
  done
  printf '%s' "$n"
}

# Pre-flight for a today change from raw tokens. $1 = add|set, rest = tokens.
# Checks today's size AND the week cap for the promotions, before any store write.
precheck_today_tokens() {
  local mode="$1"; shift
  local base_today="" n_today n_week new_w
  [ "$mode" = add ] && base_today=$(open_ids today)
  n_today=$(( $(_count_ids "$base_today") + $(_count_new_tokens "$(read_focus today)" "$@") ))
  [ "$mode" = set ] && n_today=$(_count_new_tokens "" "$@")
  _today_size_ok "$n_today" || return 1
  new_w=$(_count_new_tokens "$(read_focus week)" "$@")
  n_week=$(( $(_count_ids "$(open_ids week)") + new_w ))
  _week_cap_ok "$n_week" "$(_count_ids "$(open_ids week)")" "$new_w"
}

# Pre-flight for a week change from raw tokens. $1 = add|set, rest = tokens.
precheck_week_tokens() {
  local mode="$1"; shift
  local already new n
  if [ "$mode" = add ]; then
    already=$(_count_ids "$(open_ids week)"); new=$(_count_new_tokens "$(read_focus week)" "$@")
  else
    already=0; new=$(_count_new_tokens "" "$@")
    local tok; for tok in "$@"; do case " $(read_focus week) " in *" $tok "*) already=$((already+1)); new=$((new-1)) ;; esac; done
  fi
  n=$(( already + new ))
  _week_cap_ok "$n" "$already" "$new"
}

# Today ⊆ Week: any today ID not on the week is PROMOTED onto it (no orphan
# today items). Echoes the resulting week list; fails on the week cap.
week_with_today() {
  local today_ids="$1" week_ids="${2:-$(read_focus week)}" id promoted=""
  for id in $today_ids; do
    case " $week_ids " in *" $id "*) ;; *) promoted="${promoted:+$promoted }$id" ;; esac
  done
  week_ids=$(_merge_ids "$week_ids" $promoted)
  check_week_cap "$week_ids" || return 1
  [ -n "$promoted" ] && echo "promoted to the week (today ⊆ week): ${promoted}" >&2
  printf '%s' "$week_ids"
}

# ── Store pull + suggestions ──────────────────────────────────────────────────
# Store candidates for the week, in pick order: urgent → today → due this week
# → the rest of later. Excludes IDs already on the week.
store_week_candidates() {
  local s="" on=" $(read_focus week) " id out=""
  s=$(_merge_ids "" $(store_ids_by_lever urgent))
  s=$(_merge_ids "$s" $(store_ids_by_lever today))
  s=$(_merge_ids "$s" $(store_ids_due_by "$(week_end_date)"))
  s=$(_merge_ids "$s" $(store_ids_by_lever later))
  for id in $s; do case "$on" in *" $id "*) ;; *) out="${out:+$out }$id" ;; esac; done
  printf '%s' "$out"
}

# Suggested week: carry (open items already on the week) + store pull, cut to cap.
suggest_week() {
  local s
  s=$(compute_carry_forward week)
  s=$(_merge_ids "$s" $(store_ids_by_lever urgent))
  s=$(_merge_ids "$s" $(store_ids_by_lever today))
  s=$(_merge_ids "$s" $(store_ids_due_by "$(week_end_date)"))
  _head_ids "$VT_WEEK_CAP" "$s"
}

# Suggested today (2–3, from the week only): today's open carry that is on the
# week, then the week's urgent store items, then board in-progress, then the
# rest of the week in order. $1 = the week list to draw from (default: current
# week; on a new week, /week passes its suggestion).
suggest_today() {
  local week="${1:-$(read_focus week)}" s="" id
  [ -z "$week" ] && { printf ''; return 0; }
  for id in $(compute_carry_forward today); do case " $week " in *" $id "*) s=$(_merge_ids "$s" "$id") ;; esac; done
  for id in $week; do focus_open "$id" && [ "$(focus_state "$id")" = "store·urgent" ] && s=$(_merge_ids "$s" "$id"); done
  for id in $week; do focus_open "$id" && [ "$(focus_state "$id")" = "in-progress" ] && s=$(_merge_ids "$s" "$id"); done
  for id in $week; do focus_open "$id" && s=$(_merge_ids "$s" "$id"); done
  _head_ids "$VT_TODAY_MAX" "$s"
}

# Keep store levers coherent with the committed Today: a live CAP on today
# becomes lever=today; a live CAP that was lever=today but is no longer on
# today goes back to later (an honest park, logged — history, not deletion).
# Board stories are untouched.
sync_store_levers_today() {
  local focus=" $1 " id
  for id in $(store_ids_by_lever urgent) $(store_ids_by_lever later); do
    case "$focus" in *" $id "*) vt_store_set_lever "$id" today "today-focus" >/dev/null ;; esac
  done
  for id in $(store_ids_by_lever today); do
    case "$focus" in *" $id "*) ;; *) vt_store_set_lever "$id" later "dropped-from-today" >/dev/null ;; esac
  done
}

# Default project key for a direct-add store item: first Projects row on the
# board, else GEN.
default_project_key() {
  local k=""
  [ -f "$BOARD" ] && k=$(awk -F'|' '
    /^## Projects/ { p = 1; next }
    /^---$/        { p = 0 }
    p && /^\| ---/ { h = 1; next }
    p && h && /^\|/ { c = $2; gsub(/^ +| +$/, "", c); if (c != "") { print c; exit } }
  ' "$BOARD")
  printf '%s' "${k:-GEN}"
}

# Resolve mixed args into focus IDs. Tokens shaped like an ID (P0-12, CAP-003)
# pass through (unknown IDs warn, but are kept — the operator decides). Anything
# else is FREE TEXT: a new store item is created on the spot (state active,
# lever = today for the today section, later for week). Echoes the IDs;
# creation notices go to stderr. $1 = today|week, $2 = project key (may be
# empty → default), rest = tokens.
resolve_focus_tokens() {
  local section="$1" proj="$2"; shift 2
  local out="" tok id lever
  [ "$section" = today ] && lever=today || lever=later
  [ -z "$proj" ] && proj=$(default_project_key)
  for tok in "$@"; do
    [ -z "$tok" ] && continue
    if [[ "$tok" =~ ^[A-Z][A-Z0-9]*-[0-9]+$ ]]; then
      case "$(focus_state "$tok")" in
        off-board|store·missing) echo "warn: $tok is not on the board or in the store (kept as typed)." >&2 ;;
      esac
      out=$(_merge_ids "$out" "$tok")
    else
      vt_store_ensure
      id=$( STORE_PROJECT="$proj"; STORE_TITLE="$tok"; STORE_TYPE=dev; STORE_WHY="direct-add:$section"
            STORE_DEADLINE=""; STORE_LEVER="$lever"; vt_store_write_new )
      vt_store_transition "$id" active "direct-add" >/dev/null
      echo "added: $id [$proj] $tok  (store, lever=$lever)" >&2
      out=$(_merge_ids "$out" "$id")
    fi
  done
  printf '%s' "$out"
}

# Append one line to priorities.log: <ts>\t<section>\t<ids>\t<reason>
log_priorities() {
  local section="$1" ids="$2" reason="${3:-set}" ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  printf '%s\t%s\t%s\t%s\n' "$ts" "$section" "${ids:--}" "$reason" >> "$PRIORITIES_LOG" 2>/dev/null || true
}

# ── current-priorities.md — render + write ────────────────────────────────────
# Checkbox lines for an ID list: `- [ ] ID  title` / `- [x] ID  title`.
# $2 = space-separated set of IDs to force-check (persisted marks).
render_checkbox_items() {
  local ids="$1" done_set=" ${2:-} " id t box
  [ -z "$ids" ] && { echo "- (none)"; return 0; }
  for id in $ids; do
    [ -z "$id" ] && continue
    t=$(focus_title "$id")
    box="[ ]"
    case "$done_set" in *" $id "*) box="[x]" ;; esac
    case "$(focus_state "$id")" in done|store·done) box="[x]" ;; esac
    printf -- '- %s %s  %s\n' "$box" "$id" "${t:-?}"
  done
}

# Render the Today section. Args: ids, stamp (explicit — empty = stale), done_set.
render_today_section() {
  local ids="$1" stamp done_set="${3:-}"
  if [ "$#" -ge 2 ]; then stamp="$2"; else stamp="$(iso_today)"; fi
  echo "## Today (${stamp})"
  render_checkbox_items "$ids" "$done_set"
}

# Render the Week section. Args: ids, week_num (explicit — empty = stale), done_set.
render_week_section() {
  local ids="$1" week_num done_set="${3:-}"
  if [ "$#" -ge 2 ]; then week_num="$2"; else week_num="$(week_num_current)"; fi
  echo "## Week ${week_num} ($(iso_week_range))"
  render_checkbox_items "$ids" "$done_set"
}

# Write the whole file. Args: today_ids today_stamp week_ids week_stamp [extra_done].
# Persisted [x] marks (both sections) survive every rewrite; extra_done adds more.
_write_priorities_file() {
  local today_ids="$1" today_stamp="$2" week_ids="$3" week_stamp="$4" extra="${5:-}" done_set tmp
  done_set=$(_merge_ids "$(read_done today)" $(read_done week) $extra)
  mkdir -p "$VT_DIR"
  tmp="${PRIORITIES}.tmp.$$"
  {
    echo "# Current Priorities — $(vt_workspace_name)"
    echo ""
    render_today_section "$today_ids" "$today_stamp" "$done_set"
    echo ""
    render_week_section "$week_ids" "$week_stamp" "$done_set"
  } > "$tmp" && mv "$tmp" "$PRIORITIES"
}

# Write ONE section with a fresh stamp, preserving the other section verbatim
# (its stamp too — empty stays empty = stale). Args: which=today|week, ids,
# [reason] (→ priorities.log).
write_focus_section() {
  local which="$1" new_focus="$2" reason="${3:-set}"
  local today_focus today_stamp week_focus week_stamp
  today_focus=$(read_focus today); today_stamp=$(read_today_stamp)
  week_focus=$(read_focus week);   week_stamp=$(read_week_stamp)
  case "$which" in
    today) today_focus="$new_focus"; today_stamp=$(iso_today) ;;
    week)  week_focus="$new_focus";  week_stamp=$(week_num_current) ;;
    *) echo "write_focus_section: bad section $which" >&2; return 1 ;;
  esac
  _write_priorities_file "$today_focus" "$today_stamp" "$week_focus" "$week_stamp"
  log_priorities "$which" "$new_focus" "$reason"
}

# Legacy helper: write both sections with fresh stamps.
write_priorities() { write_orientation "$2" "$1" "set"; }

# The one-shot commit: week + today in one write, both stamps fresh, both
# logged. Args: week_ids today_ids [reason]. Assumes rules were checked.
write_orientation() {
  local week_ids="$1" today_ids="$2" reason="${3:-week}"
  _write_priorities_file "$today_ids" "$(iso_today)" "$week_ids" "$(week_num_current)"
  log_priorities week  "$week_ids"  "$reason"
  log_priorities today "$today_ids" "$reason"
}

# Update the week list WITHOUT touching its stamp (a day-add promoting onto a
# stale week must not fake a week orientation). Today untouched.
write_week_list_keep_stamp() {
  local week_ids="$1" reason="${2:-promote}"
  _write_priorities_file "$(read_focus today)" "$(read_today_stamp)" "$week_ids" "$(read_week_stamp)"
  log_priorities week "$week_ids" "$reason"
}

# Mark IDs done: persist [x] in the file (both sections), store items → done.
# Stamps untouched. Logged as section "done".
mark_done() {
  local ids="$1" id
  for id in $ids; do vt_is_cap_id "$id" && vt_store_mark_done "$id" "done" || true; done
  _write_priorities_file "$(read_focus today)" "$(read_today_stamp)" "$(read_focus week)" "$(read_week_stamp)" "$ids"
  log_priorities done "$ids" "done"
}

# Re-render the file preserving stamps + lists (called by vt-transition.sh after
# every state change so a Done story shows [x] without a ritual). No-op if the
# file doesn't exist yet.
refresh_priorities_activity() {
  [ ! -f "$PRIORITIES" ] && return
  local today_stamp week_stamp
  today_stamp=$(read_today_stamp); week_stamp=$(read_week_stamp)
  [ -z "$today_stamp" ] && [ -z "$week_stamp" ] && return
  _write_priorities_file "$(read_focus today)" "$today_stamp" "$(read_focus week)" "$week_stamp"
}

# Print the priorities file (the main surface). Never gated.
print_priorities() {
  if [ -f "$PRIORITIES" ]; then cat "$PRIORITIES"; else echo "(no current-priorities.md yet — $PRIORITIES)"; fi
}

# ── Activity (kept for the look-back): IDs that transitioned INTO done since
# a date, or the focus IDs currently in-progress ────────────────────────────
activity_lines() {
  local window="$1" slice="$2" focus_ids="${3:-}"
  local ids="" id
  case "$slice" in
    completed)
      [ ! -f "$TRANSITIONS" ] && { echo "- (none)"; return; }
      local date_filter
      case "$window" in
        today) date_filter=$(iso_today) ;;
        week)  date_filter=$(week_start_date) ;;
        *) echo "activity_lines: bad window $window" >&2; return 1 ;;
      esac
      ids=$(awk -v start="$date_filter" -F'\t' '{ d = substr($1, 1, 10); if (d >= start && $3 ~ /→done$/) print $2 }' "$TRANSITIONS" | awk '!seen[$0]++')
      ;;
    in-progress)
      for id in $focus_ids; do
        [ -z "$id" ] && continue
        [ "$(story_state "$id")" = "in-progress" ] && ids="${ids}${id}"$'\n'
      done
      ;;
    *) echo "activity_lines: bad slice $slice" >&2; return 1 ;;
  esac
  if [ -z "$ids" ]; then echo "- (none)"; return; fi
  local title
  for id in $ids; do
    [ -z "$id" ] && continue
    title=$(story_title "$id")
    if [ -n "$title" ]; then echo "- ${id}  ${title}"; else echo "- ${id}"; fi
  done
}

# ── Gate predicate (THE shared code path: sentinel + PreToolUse guards) ───────
# Returns 0 (gate ACTIVE) if today's OR this week's stamp is stale — "stale"
# includes "never set". This is the ONE function the sentinel and every guard
# call. Drift never enters here.
# True (0) iff a week-number stamp matches the current week, tolerant of
# zero-padding ("Week 5" == "05"). Empty / non-numeric → not current.
week_stamp_current() {
  local ws="$1" iw
  case "$ws" in ''|*[!0-9]*) return 1 ;; esac
  iw=$(week_num_current)
  [ "$((10#$ws))" = "$((10#$iw))" ]
}

vt_gate_active() {
  [ "$(read_today_stamp)" != "$(iso_today)" ] && return 0
  week_stamp_current "$(read_week_stamp)" || return 0
  return 1
}

# "  [ ] ID  title" lines for a section (sentinel dashboard), or "  (none set)".
render_focus_lines() {
  local section="$1" ids id t box
  ids=$(read_focus "$section")
  if [ -z "$ids" ]; then echo "  (none set)"; return 0; fi
  for id in $ids; do
    [ -z "$id" ] && continue
    t=$(focus_title "$id")
    if focus_done "$id"; then box="[x]"; else box="[ ]"; fi
    echo "  ${box} ${id}  ${t:-?}"
  done
}

# ── Orientation renders ───────────────────────────────────────────────────────
# "  ID  title  [state]" lines for an ID list, or "  (none)".
_orient_lines() {
  local ids="$1" id t due
  [ -z "$ids" ] && { echo "  (none)"; return 0; }
  for id in $ids; do
    [ -z "$id" ] && continue
    t=$(focus_title "$id"); due=$(focus_deadline "$id")
    printf '  %s  %s  [%s]%s\n' "$id" "${t:-?}" "$(focus_state "$id")" "${due:+  due $due}"
  done
}

# Checkbox-style lines for a look-back list: "  [x] ID  title" / "  [ ] ID  title  (carried)".
_lookback_lines() {
  local ids="$1" id t
  [ -z "$ids" ] && { echo "  (none)"; return 0; }
  for id in $ids; do
    [ -z "$id" ] && continue
    t=$(focus_title "$id")
    if focus_done "$id"; then printf '  [x] %s  %s\n' "$id" "${t:-?}"
    elif focus_open "$id"; then printf '  [ ] %s  %s  (carried)\n' "$id" "${t:-?}"
    else printf '  [ ] %s  %s  (gone: %s)\n' "$id" "${t:-?}" "$(focus_state "$id")"; fi
  done
}

# Board + store transitions on/after a date (the "what moved" part of a look-back).
_transitions_since() {
  local since="$1"
  echo "  board moves since ${since}:"
  if [ -f "$TRANSITIONS" ]; then
    awk -F'\t' -v d="$since" 'substr($1,1,10) >= d {printf "    %s  %s\n", $2, $3}' "$TRANSITIONS" | { grep . || echo "    (none)"; }
  else echo "    (none)"; fi
  echo "  store moves since ${since}:"
  if [ -f "$(vt_store_dir)/transitions.log" ]; then
    awk -v d="$since" 'substr($1,1,10) >= d && $0 !~ /auto-activate|lever:/ {sub(/^[^|]*\| /, ""); print "    " $0}' "$(vt_store_dir)/transitions.log" | { grep . || echo "    (none)"; }
  else echo "    (none)"; fi
  if [ -f "$PRIORITIES_LOG" ]; then
    local d; d=$(awk -F'\t' -v s="$since" '$2=="done" && substr($1,1,10) >= s {printf "%s ", $3}' "$PRIORITIES_LOG")
    # `if`, not `[ … ] &&`: an empty done-set must not make this function return 1 —
    # the callers run under `set -e`, which would kill the orientation print here,
    # before WEEK_SUGGESTED / TODAY_SUGGESTED (the 2026-09-07 dogfood crash).
    if [ -n "$d" ]; then
      echo "  marked done since ${since}:"
      _orient_lines "$(_merge_ids "" $d)" | sed 's/^/  /'
    fi
  fi
  return 0
}

# Look-back for a NEW week (Monday): last week's checkboxes — done vs carried —
# and what moved. No task-state moves.
render_lookback_week() {
  local wk_stamp="$1" ids done=0 open=0 id since
  ids=$(read_focus week)
  for id in $ids; do if focus_done "$id"; then done=$((done+1)); elif focus_open "$id"; then open=$((open+1)); fi; done
  echo "Look-back · last week${wk_stamp:+ (Week ${wk_stamp})}: ${done} done · ${open} carried"
  _lookback_lines "$ids"
  local t_stamp; t_stamp=$(read_today_stamp)
  if [ -n "$t_stamp" ]; then
    echo "  last Today (${t_stamp}):"
    _lookback_lines "$(read_focus today)" | sed 's/^/  /'
  fi
  since=$(date -v-7d +%F 2>/dev/null || date -d '7 days ago' +%F)
  _transitions_since "$since"
}

# Look-back for a FOLLOW-UP day (Tue+): since the last Today stamp (yesterday),
# not a full week replay.
render_lookback_since() {
  local since="$1" ids stamp
  ids=$(read_focus today); stamp=$(read_today_stamp)
  echo "Look-back · since ${since}:"
  if [ "$stamp" = "$(iso_today)" ]; then echo "  today so far (${stamp}):"; else echo "  last Today (${stamp:-$since}):"; fi
  _lookback_lines "$ids" | sed 's/^/  /'
  _transitions_since "$since"
}

# The ONE-SHOT /week orientation. Prints: the priorities file → look-back (new
# week vs since-yesterday) → week pick list from the store (cap-aware) → today
# pick (2–3 from the week). Ends with machine lines the skill reads:
#   WEEK_ACTIVE / WEEK_CAP_LEFT / WEEK_SUGGESTED / TODAY_SUGGESTED / MODE
render_week_orient() {
  local wk wk_stamp new_week=0 t_stamp today mode week_sugg today_sugg id left cands n
  wk=$(week_num_current); wk_stamp=$(read_week_stamp); today=$(iso_today); t_stamp=$(read_today_stamp)
  week_stamp_current "$wk_stamp" || new_week=1
  if [ "$new_week" = 1 ]; then mode="new-week"; else mode="follow-up"; fi
  echo "Orientation · $(date +%A) ${today} · Week ${wk} ($(iso_week_range)) · ${mode}${wk_stamp:+ (last stamp: Week ${wk_stamp})}"
  echo ""
  echo "── Priorities (${PRIORITIES#"$VT_DIR/"}) ──"
  print_priorities
  echo ""
  echo "── Look-back ──"
  if [ "$new_week" = 1 ]; then
    render_lookback_week "$wk_stamp"
  else
    local since="$t_stamp"
    if [ -z "$since" ] || [ "$since" = "$today" ]; then
      since=$(date -v-1d +%F 2>/dev/null || date -d 'yesterday' +%F)
    fi
    render_lookback_since "$since"
  fi
  echo ""
  left=$(week_cap_left)
  echo "── Week ${wk} — pick from the store (cap ${VT_WEEK_CAP}: $(_count_ids "$(open_ids week)") open on the week → up to ${left} new) ──"
  echo "  on the week now (open):"; _orient_lines "$(open_ids week)" | sed 's/^/  /'
  echo "  store pull (not on the week yet):"
  local on_week=" $(read_focus week) " due_ids urg tod lat
  _not_on_week() { local id out=""; for id in "$@"; do case "$on_week" in *" $id "*) ;; *) out="${out:+$out }$id" ;; esac; done; printf '%s' "$out"; }
  urg=$(_not_on_week $(store_ids_by_lever urgent)); tod=$(_not_on_week $(store_ids_by_lever today))
  due_ids=$(_not_on_week $(store_ids_due_by "$(week_end_date)"))
  echo "    urgent:";         _orient_lines "$urg" | sed 's/^/    /'
  echo "    today:";          _orient_lines "$tod" | sed 's/^/    /'
  echo "    due this week:";  _orient_lines "$due_ids" | sed 's/^/    /'
  lat=$(_without_ids "$(_not_on_week $(store_ids_by_lever later))" $due_ids); n=$(_count_ids "$lat")
  echo "    later (${n} parked):"; _orient_lines "$(_head_ids 8 "$lat")" | sed 's/^/    /'
  [ "$n" -gt 8 ] && echo "      … +$((n-8)) more (vt-store-list.sh later)"
  echo "  board work in flight (also pickable):"; _orient_lines "$(_merge_ids "" $(board_ids_in in-progress testing))" | sed 's/^/  /'
  echo ""
  week_sugg=$(suggest_week)
  today_sugg=$(suggest_today "$week_sugg")
  echo "── Today ${today} — pick ${VT_TODAY_MIN}–${VT_TODAY_MAX} from the week ──"
  echo "  carry from last Today${t_stamp:+ (${t_stamp})}:"; _orient_lines "$(compute_carry_forward today)" | sed 's/^/  /'
  echo "  (a pick that isn't on the week is promoted onto it — no orphan today items)"
  echo ""
  echo "MODE: ${mode}"
  echo "WEEK_ACTIVE: $(open_ids week)"
  echo "WEEK_CAP_LEFT: ${left}"
  echo "WEEK_SUGGESTED: ${week_sugg:-—}"
  echo "TODAY_SUGGESTED: ${today_sugg:-—}"
}

# The mid-day /today orientation: the file, then the week to pull from.
render_today_orient() {
  local today stamp wk wk_stamp wk_state sugg
  today=$(iso_today); stamp=$(read_today_stamp)
  wk=$(week_num_current); wk_stamp=$(read_week_stamp)
  if week_stamp_current "$wk_stamp"; then wk_state="current"; else wk_state="STALE — run /4loops:week (one-shot orientation, includes today)"; fi
  echo "Today ${today} · Week ${wk} (${wk_state})"
  if [ -z "$stamp" ]; then echo "Today stamp: none yet"
  elif [ "$stamp" = "$today" ]; then echo "Today stamp: ${stamp} (fresh — mid-day pull)"
  else echo "Today stamp: ${stamp} (stale)"; fi
  echo ""
  print_priorities
  echo ""
  echo "Pull from the week (open):"
  _orient_lines "$(open_ids week)"
  echo ""
  sugg=$(suggest_today)
  echo "TODAY_SUGGESTED: ${sugg:-—}"
}

# "What did we do yesterday?" — derived from transitions, not an archive.
render_yesterday() {
  local today date ids line
  today=$(iso_today)
  if [ -f "$PRIORITIES_LOG" ]; then
    line=$(awk -F'\t' -v t="$today" '$2=="today" && substr($1,1,10) < t {l=$0} END{print l}' "$PRIORITIES_LOG")
  fi
  if [ -n "${line:-}" ]; then
    date=$(printf '%s' "$line" | cut -f1 | cut -c1-10); ids=$(printf '%s' "$line" | cut -f3)
    [ "$ids" = "-" ] && ids=""
  else
    date=$(read_today_stamp)
    [ -n "$date" ] && [ "$date" != "$today" ] && ids=$(read_focus today) || { date=""; ids=""; }
  fi
  if [ -z "$date" ]; then echo "No earlier Today focus on record yet."; return 0; fi
  echo "Last Today (${date}) focus:"
  _lookback_lines "$ids"
  echo ""
  echo "Board transitions on ${date}:"
  if [ -f "$TRANSITIONS" ]; then
    awk -F'\t' -v d="$date" 'substr($1,1,10)==d {printf "  %s  %s\n", $2, $3}' "$TRANSITIONS" | { grep . || echo "  (none)"; }
  else echo "  (none)"; fi
  echo ""
  echo "Store transitions on ${date}:"
  if [ -f "$(vt_store_dir)/transitions.log" ]; then
    awk -v d="$date" 'substr($1,1,10)==d {sub(/^[^|]*\| /, ""); print "  " $0}' "$(vt_store_dir)/transitions.log" | { grep . || echo "  (none)"; }
  else echo "  (none)"; fi
}
