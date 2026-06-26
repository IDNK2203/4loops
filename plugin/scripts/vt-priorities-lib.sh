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

# Compute carry-forward default for either today or week.
# Default = IDs from previous focus whose current state is in {planning, in-progress, testing}.
# If no previous focus (or no priorities file), default = all stories currently in in-progress.
compute_carry_forward() {
  local section="$1"
  local prev_ids
  prev_ids=$(read_focus "$section")
  if [ -z "$prev_ids" ]; then
    # No previous focus: surface what's currently in-progress as a starting point.
    awk -F'|' '
      /^\| Backlog \| Planning \| In Progress \| Testing \| Done \|$/ { in_kanban = 1; next }
      in_kanban && /^\| --/ { in_body = 1; next }
      in_body && /^\|/ {
        cell = $4   # In Progress column
        gsub(/^ +| +$/, "", cell)
        if (cell != "" && match(cell, /\*\*[A-Z0-9]+-[0-9]+\*\*/)) {
          print substr(cell, RSTART+2, RLENGTH-4)
        }
      }
    ' "$BOARD" 2>/dev/null | tr '\n' ' ' | sed 's/ *$//'
    return
  fi
  # Filter previous focus: keep IDs currently in planning/in-progress/testing
  local result=""
  for id in $prev_ids; do
    local s
    s=$(story_state "$id")
    case "$s" in
      planning|in-progress|testing) result="${result}${id} " ;;
    esac
  done
  echo "$result" | sed 's/ *$//'
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
# stays active until /4loops:today also runs). Args: which=today|week, new_focus.
write_focus_section() {
  local which="$1" new_focus="$2" workspace
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

# Emit "  <ID>  <title>" indented lines for a section's focus IDs (today|week),
# or a single "  (none set)" line. Used by the sentinel dashboard render so the
# user sees the actual tasks, not bare IDs.
render_focus_lines() {
  local section="$1" ids id t
  ids=$(read_focus "$section")
  if [ -z "$ids" ]; then
    echo "  (none set)"
    return 0
  fi
  for id in $ids; do
    [ -z "$id" ] && continue
    t=$(story_title "$id")
    if [ -n "$t" ]; then echo "  ${id}  ${t}"; else echo "  ${id}"; fi
  done
}
