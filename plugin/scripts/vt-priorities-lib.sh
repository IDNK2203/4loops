#!/usr/bin/env bash
# vt-priorities-lib.sh — sourced library used by vt-today.sh and vt-week.sh.
# Not directly invocable; do not chmod +x.
#
# Centralizes: date helpers, current-priorities.md read/write, story-state +
# title lookups from board.md, carry-forward defaults, activity-slice derivation.

VT_DIR="${VT_DIR:-./.4loops}"
BOARD="$VT_DIR/board.md"
PRIORITIES="$VT_DIR/current-priorities.md"
TRANSITIONS="$VT_DIR/transitions.log"
# v2.5 Real C: append-only focus history (one line per Today/Week commit). This
# is the "history via transitions" for priorities — NOT a per-day archive file.
PRIORITIES_LOG="$VT_DIR/priorities.log"

# v2.5 Real C: focus lines may hold detached-store items (CAP-NNN) next to board
# stories, so the priorities lib needs the store helpers.
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
# Echoes one of: backlog | planning | in-progress | testing | done | "" (not found)
story_state() {
  local id="$1"
  [ ! -f "$BOARD" ] && return
  awk -v id="$id" -F'|' '
    /^\| Backlog \| Planning \| In Progress \| Testing \| Done \|$/ { in_kanban = 1; next }
    in_kanban && /^\| --/ { in_body = 1; next }
    in_body && /^\|/ && index($0, "**" id "**") {
      for (i = 2; i <= 6; i++) {
        cell = $i
        gsub(/^ +| +$/, "", cell)
        if (index(cell, "**" id "**")) {
          states[1] = "backlog"; states[2] = "planning"; states[3] = "in-progress"
          states[4] = "testing"; states[5] = "done"
          print states[i-1]
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

# Read the existing focus IDs from a section. Args: today|week
# Returns space-separated ID list.
read_focus() {
  local section="$1"
  local header_pattern
  case "$section" in
    today) header_pattern="^## Today [(]" ;;
    week)  header_pattern="^## Week "     ;;
    *) echo "read_focus: bad section $section" >&2; return 1 ;;
  esac
  [ ! -f "$PRIORITIES" ] && return
  awk -v hdr="$header_pattern" '
    $0 ~ hdr { in_section = 1; next }
    in_section && /^Focus: / {
      sub(/^Focus: /, "")
      gsub(/ · /, " ")
      gsub(/^—$/, "")
      print
      exit
    }
  ' "$PRIORITIES"
}

# ── v2.5 Real C: store-aware focus items ─────────────────────────────────────
# A focus line holds board stories (P0-NNN) AND detached-store items (CAP-NNN).
# These helpers give every focus ID a title / state / liveness regardless of
# which record backs it, so the priorities doc can be the main surface.

vt_is_cap_id() { case "$1" in CAP-[0-9]*) return 0 ;; *) return 1 ;; esac; }

# Board story IDs in the given columns (space-separated names), in grid order.
board_ids_in() {
  local want=" $* "
  [ -f "$BOARD" ] || return 0
  awk -F'|' -v want="$want" '
    BEGIN { names[2]="backlog"; names[3]="planning"; names[4]="in-progress"; names[5]="testing"; names[6]="done" }
    /^\| Backlog \| Planning \| In Progress \| Testing \| Done \|$/ { in_kanban = 1; next }
    in_kanban && /^\| --/ { in_body = 1; next }
    in_body && /^\|/ {
      for (i = 2; i <= 6; i++) {
        if (index(want, " " names[i] " ") == 0) continue
        cell = $i; gsub(/^ +| +$/, "", cell)
        if (cell != "" && match(cell, /\*\*[A-Z0-9]+-[0-9]+\*\*/)) print substr(cell, RSTART+2, RLENGTH-4)
      }
    }
  ' "$BOARD" 2>/dev/null
}

# Title for any focus ID (store title for CAP, board title otherwise).
focus_title() {
  local id="$1" p
  if vt_is_cap_id "$id"; then
    p=$(vt_store_item_path "$id")
    [ -f "$p" ] && vt_store_get "$p" title
  else
    story_title "$id"
  fi
}

# Short state tag for any focus ID:
#   board → backlog|planning|in-progress|testing|done|off-board
#   store → store·<lever> (live) | store·expired | store·cleared | store·missing
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
# testing, or a live (captured|active) store item. Done / archived / expired /
# cleared / backlog all count as "not alive" for carry-forward purposes.
focus_alive() {
  case "$(focus_state "$1")" in
    planning|in-progress|testing|store·urgent|store·today|store·later) return 0 ;;
    *) return 1 ;;
  esac
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

# Carry-forward for either section: previous focus IDs that are still alive
# (board planning/in-progress/testing, or live store items). This is "yesterday's
# still-alive focus" — the default that /today continues from.
compute_carry_forward() {
  local section="$1" prev_ids result="" id
  prev_ids=$(read_focus "$section")
  for id in $prev_ids; do
    focus_alive "$id" && result=$(_merge_ids "$result" "$id")
  done
  printf '%s' "$result"
}

# Suggested Today focus (v2.5 Real C): yesterday carry-forward first, then the
# store pull — urgent levers, then today levers. Board Backlog is NOT a source.
# With no previous focus at all, falls back to board in-progress work so a
# first run still has a starting point.
suggest_today() {
  local s
  s=$(compute_carry_forward today)
  if [ -z "$s" ] && [ -z "$(read_focus today)" ]; then
    s=$(_merge_ids "" $(board_ids_in in-progress))
  fi
  s=$(_merge_ids "$s" $(store_ids_by_lever urgent))
  s=$(_merge_ids "$s" $(store_ids_by_lever today))
  printf '%s' "$s"
}

# Suggested Week anchors: last week's still-alive anchors, then committed board
# work (in-progress + testing), then the store pull (urgent, today, and later
# items due by the end of this week).
suggest_week() {
  local s
  s=$(compute_carry_forward week)
  s=$(_merge_ids "$s" $(board_ids_in in-progress testing))
  s=$(_merge_ids "$s" $(store_ids_by_lever urgent))
  s=$(_merge_ids "$s" $(store_ids_by_lever today))
  s=$(_merge_ids "$s" $(store_ids_due_by "$(week_end_date)"))
  printf '%s' "$s"
}

# Keep store levers coherent with the committed Today focus: a live CAP in
# focus becomes lever=today (urgent absorbed into the day; later pulled in); a
# live CAP that was lever=today but is no longer in focus goes back to later
# (an honest park, logged in store/transitions.log — history, not deletion).
# Board stories are untouched: the board is a state check, not the planning pen.
sync_store_levers_today() {
  local focus=" $1 " id lev
  for id in $(store_ids_by_lever urgent) $(store_ids_by_lever later); do
    case "$focus" in *" $id "*) vt_store_set_lever "$id" today "today-focus" ;; esac
  done
  for id in $(store_ids_by_lever today); do
    case "$focus" in *" $id "*) ;; *) vt_store_set_lever "$id" later "dropped-from-today" ;; esac
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
# lever = today for the today section, later for week) so mid-day work lands in
# priorities without a separate capture step. Echoes the space-separated IDs;
# creation notices go to stderr.  $1 = today|week, $2 = project key (may be
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

# Titled focus bullets for a section body: "- ID  title  [state]".
render_focus_items() {
  local ids="$1" id t
  for id in $ids; do
    [ -z "$id" ] && continue
    t=$(focus_title "$id")
    printf -- '- %s  %s  [%s]\n' "$id" "${t:-?}" "$(focus_state "$id")"
  done
}

# Compute activity slice lines for a window.
# Args: window=today|week, slice=completed|in-progress, [focus_ids] (in-progress only)
# Outputs markdown bullet lines (one per match), or "- (none)" if empty.
#   completed   = punctual journal: IDs that transitioned INTO done this window.
#   in-progress = durative snapshot: the window's FOCUS IDs whose current column
#                 is in-progress (no "touched this window" requirement — a story
#                 started yesterday and still in-progress belongs in today's slice).
activity_lines() {
  local window="$1" slice="$2" focus_ids="${3:-}"
  local ids="" id

  case "$slice" in
    completed)
      [ ! -f "$TRANSITIONS" ] && { echo "- (none)"; return; }
      local date_filter
      case "$window" in
        today) date_filter=$(iso_today) ;;
        week)  date_filter=$(week_start_date) ;;   # honors week-start config
        *) echo "activity_lines: bad window $window" >&2; return 1 ;;
      esac
      ids=$(awk -v start="$date_filter" -F'\t' '
        {
          # $1 is ISO timestamp like 2026-05-28T14:32:00Z; take date prefix
          d = substr($1, 1, 10)
          if (d >= start && $3 ~ /→done$/) print $2
        }
      ' "$TRANSITIONS" | awk '!seen[$0]++')
      ;;
    in-progress)
      for id in $focus_ids; do
        [ -z "$id" ] && continue
        [ "$(story_state "$id")" = "in-progress" ] && ids="${ids}${id}"$'\n'
      done
      ;;
    *) echo "activity_lines: bad slice $slice" >&2; return 1 ;;
  esac

  if [ -z "$ids" ]; then
    echo "- (none)"
    return
  fi
  local title
  for id in $ids; do
    [ -z "$id" ] && continue
    title=$(story_title "$id")
    if [ -n "$title" ]; then
      echo "- ${id}  ${title}"
    else
      echo "- ${id}"
    fi
  done
}

# Render the Today section.
# Args: focus IDs (space-separated), optional stamp (defaults to today's date).
render_today_section() {
  local focus="$1"
  # An explicitly-passed stamp (even empty) is used verbatim — empty renders
  # "## Today ()" which read_today_stamp treats as STALE. Only a stamp arg that
  # is entirely absent defaults to today. This lets one ritual preserve (or
  # leave stale) the other section's stamp.
  local stamp
  if [ "$#" -ge 2 ]; then stamp="$2"; else stamp="$(iso_today)"; fi
  local focus_display
  if [ -z "$focus" ]; then
    focus_display="—"
  else
    focus_display=$(echo "$focus" | sed 's/ / · /g')
  fi
  echo "## Today (${stamp})"
  echo "Focus: ${focus_display}"
  [ -n "$focus" ] && render_focus_items "$focus"
  echo ""
  echo "In progress today:"
  activity_lines today in-progress "$focus"
  echo ""
  echo "Completed today:"
  activity_lines today completed
}

# Render the Week section.
# Args: focus IDs (space-separated), optional week_num, optional week_range.
render_week_section() {
  local focus="$1"
  # Same provided-vs-absent rule as render_today_section: an explicit (even
  # empty) week_num is used verbatim; only an absent arg defaults to current.
  local week_num week_range
  if [ "$#" -ge 2 ]; then week_num="$2"; else week_num="$(week_num_current)"; fi
  if [ "$#" -ge 3 ]; then week_range="$3"; else week_range="$(iso_week_range)"; fi
  local focus_display
  if [ -z "$focus" ]; then
    focus_display="—"
  else
    focus_display=$(echo "$focus" | sed 's/ / · /g')
  fi
  echo "## Week ${week_num} (${week_range})"
  echo "Focus: ${focus_display}"
  [ -n "$focus" ] && render_focus_items "$focus"
  echo ""
  echo "In progress this week:"
  activity_lines week in-progress "$focus"
  echo ""
  echo "Completed this week:"
  activity_lines week completed
}

# Write the whole current-priorities.md file.
# Args: today_focus week_focus
# Uses current date/week stamps. Used by /4loops:today and /4loops:week when the user
# is explicitly setting (or carry-forward-confirming) focus for the current period.
write_priorities() {
  local today_focus="$1"
  local week_focus="$2"
  local workspace
  workspace=$(basename "$(pwd)")
  {
    echo "# Current Priorities — ${workspace}"
    echo ""
    render_today_section "$today_focus"
    echo ""
    echo "---"
    echo ""
    render_week_section "$week_focus"
  } > "$PRIORITIES"
}

# Write current-priorities.md freshening ONLY the named section's stamp, and
# PRESERVING the other section's existing stamp (empty stays empty = stale).
# This is what makes each ritual own its own gate: /4loops:today freshens only Today
# (the week gate is untouched) and /4loops:week freshens only Week (the day gate
# stays active until /4loops:today also runs). Args: which=today|week, new_focus,
# [reason] (logged to priorities.log — the focus history; default "set").
write_focus_section() {
  local which="$1" new_focus="$2" reason="${3:-set}" workspace
  workspace=$(basename "$(pwd)")
  local today_focus today_stamp week_focus week_stamp
  today_focus=$(read_focus today); today_stamp=$(read_today_stamp)
  week_focus=$(read_focus week);   week_stamp=$(read_week_stamp)
  case "$which" in
    today) today_focus="$new_focus"; today_stamp=$(iso_today) ;;
    week)  week_focus="$new_focus";  week_stamp=$(week_num_current) ;;
    *) echo "write_focus_section: bad section $which" >&2; return 1 ;;
  esac
  {
    echo "# Current Priorities — ${workspace}"
    echo ""
    render_today_section "$today_focus" "$today_stamp"   # explicit stamp (may be empty = stale)
    echo ""
    echo "---"
    echo ""
    render_week_section "$week_focus" "$week_stamp"       # explicit stamp (may be empty = stale)
  } > "$PRIORITIES"
  log_priorities "$which" "$new_focus" "$reason"
}

# Refresh ONLY activity slices in current-priorities.md, preserving existing
# Today/Week stamps + focus selections. Called by vt-transition.sh after every
# state change so the file doesn't lie between /4loops:today invocations.
# No-op if current-priorities.md doesn't exist yet.
refresh_priorities_activity() {
  [ ! -f "$PRIORITIES" ] && return
  local today_stamp today_focus week_stamp week_focus
  today_stamp=$(read_today_stamp)
  today_focus=$(read_focus today)
  week_stamp=$(read_week_stamp)
  week_focus=$(read_focus week)
  # If existing file has neither stamp set, nothing meaningful to preserve.
  [ -z "$today_stamp" ] && [ -z "$week_stamp" ] && return

  local workspace
  workspace=$(basename "$(pwd)")
  {
    echo "# Current Priorities — ${workspace}"
    echo ""
    render_today_section "$today_focus" "$today_stamp"
    echo ""
    echo "---"
    echo ""
    # For week, preserve the stamp but recompute the range only if no stamp exists.
    # If we have a stamp, we don't know the original range, so just recompute it.
    # (Range drift across week boundary is acceptable; the stamp is the source of truth.)
    if [ -n "$week_stamp" ]; then
      render_week_section "$week_focus" "$week_stamp"
    else
      render_week_section "$week_focus"
    fi
  } > "$PRIORITIES"
}

# ── Gate predicate (THE shared code path: sentinel + PreToolUse guards) ───────
# Returns 0 (gate ACTIVE → block product work) if today's OR this week's focus
# is stale. Returns 1 (gate CLEAR) if both stamps match the current period.
# "Stale" includes "never set" (empty stamp) — a fresh workspace is gated by
# default; the first-run on-ramp (handled in the guard) prevents minute-one
# lockout. This is the ONE function the sentinel and every guard call, so the
# loop stays coherent. (Drift never enters here — drift is surfaced, not gated.)
# True (0) iff a week-number stamp matches the current ISO week, tolerant of
# zero-padding ("Week 5" from a hand-edit/legacy file == "05" from date +%V).
# Empty or non-numeric stamp → not current (gate active). This kills the
# weeks-01-09 stuck-gate class.
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

# Emit "  <ID>  <title>  [state]" indented lines for a section's focus IDs
# (today|week), or a single "  (none set)" line. Used by the sentinel dashboard
# render so the user sees the actual tasks, not bare IDs. Store items (CAP)
# render with their store title + lever.
render_focus_lines() {
  local section="$1" ids id t
  ids=$(read_focus "$section")
  if [ -z "$ids" ]; then
    echo "  (none set)"
    return 0
  fi
  for id in $ids; do
    [ -z "$id" ] && continue
    t=$(focus_title "$id")
    if [ -n "$t" ]; then echo "  ${id}  ${t}  [$(focus_state "$id")]"; else echo "  ${id}  [$(focus_state "$id")]"; fi
  done
}

# ── v2.5 Real C: orientation renders ─────────────────────────────────────────
# "  ID  title  [state]" lines for an ID list, or "  (none)".
_orient_lines() {
  local ids="$1" id t
  [ -z "$ids" ] && { echo "  (none)"; return 0; }
  for id in $ids; do
    [ -z "$id" ] && continue
    t=$(focus_title "$id")
    printf '  %s  %s  [%s]\n' "$id" "${t:-?}" "$(focus_state "$id")"
  done
}

# The /today orientation block: where you are vs yesterday's carry-forward and
# the week's anchors, plus the store pull. Ends with a SUGGESTED_FOCUS line the
# skill reads. No board print — the board is a state check, not the planning pen.
render_today_orient() {
  local today stamp wk wk_stamp wk_state carry prev dropped id sugg n_later
  today=$(iso_today); stamp=$(read_today_stamp)
  wk=$(week_num_current); wk_stamp=$(read_week_stamp)
  if week_stamp_current "$wk_stamp"; then wk_state="current"; else wk_state="STALE — run /4loops:week first"; fi
  prev=$(read_focus today); carry=$(compute_carry_forward today)
  echo "Orientation · Today ${today} · Week ${wk} (${wk_state})"
  if [ -z "$stamp" ]; then echo "Today stamp: none (first run)"
  elif [ "$stamp" = "$today" ]; then echo "Today stamp: ${stamp} (fresh — re-orienting mid-day)"
  else echo "Today stamp: ${stamp} (stale)"; fi
  echo ""
  echo "Last Today${stamp:+ (${stamp})} — carry-forward (still alive):"
  _orient_lines "$carry"
  dropped=""
  for id in $prev; do case " $carry " in *" $id "*) ;; *) dropped="${dropped:+$dropped }$id" ;; esac; done
  if [ -n "$dropped" ]; then
    echo "  dropped (done / retired / expired):"
    _orient_lines "$dropped" | sed 's/^/  /'
  fi
  echo ""
  echo "Store pull:"
  echo "  urgent:"; _orient_lines "$(_merge_ids "" $(store_ids_by_lever urgent))" | sed 's/^/  /'
  echo "  today:";  _orient_lines "$(_merge_ids "" $(store_ids_by_lever today))"  | sed 's/^/  /'
  n_later=$(store_ids_by_lever later | wc -l | tr -d ' ')
  echo "  later: ${n_later} parked (pull with /4loops:prioritize, or name them when you set today)"
  echo ""
  sugg=$(suggest_today)
  echo "Week ${wk} anchors — how today meets the week:"
  local wk_ids; wk_ids=$(read_focus week)
  if [ -z "$wk_ids" ]; then echo "  (none set)"; else
    for id in $wk_ids; do
      local mark="" t
      case " $sugg " in *" $id "*) mark="  ← in suggested today" ;; esac
      t=$(focus_title "$id")
      printf '  %s  %s  [%s]%s\n' "$id" "${t:-?}" "$(focus_state "$id")" "$mark"
    done
  fi
  echo ""
  echo "SUGGESTED_FOCUS: ${sugg:-—}"
}

# The /week orientation block: last week's anchors (alive vs finished), the
# committed board work, and the store pull. Ends with SUGGESTED_FOCUS.
render_week_orient() {
  local wk wk_stamp wk_state prev carry dropped id sugg n_later
  wk=$(week_num_current); wk_stamp=$(read_week_stamp)
  if week_stamp_current "$wk_stamp"; then wk_state="fresh — re-orienting mid-week"; else wk_state="${wk_stamp:+last stamp Week ${wk_stamp} — }new week"; fi
  prev=$(read_focus week); carry=$(compute_carry_forward week)
  echo "Orientation · Week ${wk} ($(iso_week_range)) · ${wk_state}"
  echo ""
  echo "Last Week${wk_stamp:+ (Week ${wk_stamp})} anchors — still alive:"
  _orient_lines "$carry"
  dropped=""
  for id in $prev; do case " $carry " in *" $id "*) ;; *) dropped="${dropped:+$dropped }$id" ;; esac; done
  if [ -n "$dropped" ]; then
    echo "  finished / retired / expired (honest endings):"
    _orient_lines "$dropped" | sed 's/^/  /'
  fi
  echo ""
  echo "Committed board work (in-progress · testing):"
  _orient_lines "$(_merge_ids "" $(board_ids_in in-progress testing))"
  echo ""
  echo "Store pull:"
  echo "  urgent:"; _orient_lines "$(_merge_ids "" $(store_ids_by_lever urgent))" | sed 's/^/  /'
  echo "  today:";  _orient_lines "$(_merge_ids "" $(store_ids_by_lever today))"  | sed 's/^/  /'
  echo "  due this week (later):"; _orient_lines "$(_merge_ids "" $(store_ids_due_by "$(week_end_date)"))" | sed 's/^/  /'
  n_later=$(store_ids_by_lever later | wc -l | tr -d ' ')
  echo "  later: ${n_later} parked"
  echo ""
  sugg=$(suggest_week)
  echo "SUGGESTED_FOCUS: ${sugg:-—}"
}

# "What did we do yesterday?" — derived from transitions, not an archive:
# the last Today commit before today (priorities.log, falling back to the
# current file's stale stamp), board transitions on that date, and store
# transitions on that date.
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
  _orient_lines "$ids"
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
