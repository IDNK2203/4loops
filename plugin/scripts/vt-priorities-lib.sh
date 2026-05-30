#!/usr/bin/env bash
# vt-priorities-lib.sh — sourced library used by vt-today.sh and vt-week.sh.
# Not directly invocable; do not chmod +x.
#
# Centralizes: date helpers, current-priorities.md read/write, story-state +
# title lookups from board.md, carry-forward defaults, activity-slice derivation.

VT_DIR="${VT_DIR:-./.vibe-table}"
BOARD="$VT_DIR/board.md"
PRIORITIES="$VT_DIR/current-priorities.md"
TRANSITIONS="$VT_DIR/transitions.log"

# Date helpers (BSD/macOS-compatible)
iso_today()      { date +"%Y-%m-%d"; }
iso_week_num()   { date +"%V"; }
iso_year()       { date +"%G"; }

# Returns "YYYY-MM-DD → MM-DD" for the current ISO week (Mon → Sun).
iso_week_range() {
  local today dow mon sun
  today=$(date +"%Y-%m-%d")
  dow=$(date +"%u")     # 1=Mon ... 7=Sun
  mon=$(date -v-$((dow-1))d +"%Y-%m-%d" 2>/dev/null || date -d "$today -$((dow-1)) days" +"%Y-%m-%d")
  sun=$(date -v-$((dow-1))d -v+6d +"%Y-%m-%d" 2>/dev/null || date -d "$today -$((dow-1)) days +6 days" +"%Y-%m-%d")
  local sun_short
  sun_short=${sun#????-}     # strip the year, keep MM-DD
  echo "${mon} → ${sun_short}"
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
        if (cell != "") {
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
          # Strip trailing " — why: ..." or " — context: ..."
          sub(/ — (why|context):.*/, "", cell)
          gsub(/^ +| +$/, "", cell)
          print cell
          exit
        }
      }
    }
  ' "$BOARD"
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
# Args: today|week, slice=completed|in-progress
# Outputs markdown bullet lines (one per match), or "- (none)" if empty.
activity_lines() {
  local window="$1"
  local slice="$2"
  local date_filter=""
  case "$window" in
    today)
      date_filter=$(iso_today)
      ;;
    week)
      # All dates from Monday of current ISO week through today.
      local dow mon
      dow=$(date +"%u")
      mon=$(date -v-$((dow-1))d +"%Y-%m-%d" 2>/dev/null || date -d "today -$((dow-1)) days" +"%Y-%m-%d")
      date_filter="$mon"
      ;;
    *) echo "activity_lines: bad window $window" >&2; return 1 ;;
  esac

  [ ! -f "$TRANSITIONS" ] && { echo "- (none)"; return; }

  local ids=""
  case "$slice" in
    completed)
      # IDs that transitioned INTO done within window.
      ids=$(awk -v start="$date_filter" -F'\t' '
        {
          # $1 is ISO timestamp like 2026-05-28T14:32:00Z; take date prefix
          d = substr($1, 1, 10)
          if (d >= start && $3 ~ /→done$/) print $2
        }
      ' "$TRANSITIONS" | awk '!seen[$0]++')
      ;;
    in-progress)
      # IDs touched within window that are currently in in-progress.
      local touched
      touched=$(awk -v start="$date_filter" -F'\t' '
        { d = substr($1, 1, 10); if (d >= start) print $2 }
      ' "$TRANSITIONS" | awk '!seen[$0]++')
      for id in $touched; do
        local s
        s=$(story_state "$id")
        [ "$s" = "in-progress" ] && ids="${ids}${id}"$'\n'
      done
      ;;
    *) echo "activity_lines: bad slice $slice" >&2; return 1 ;;
  esac

  if [ -z "$ids" ]; then
    echo "- (none)"
    return
  fi
  for id in $ids; do
    [ -z "$id" ] && continue
    local title
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
  echo "In progress today (touched today):"
  activity_lines today in-progress
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
  if [ "$#" -ge 2 ]; then week_num="$2"; else week_num="$(iso_week_num)"; fi
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
  activity_lines week in-progress
  echo ""
  echo "Completed this week:"
  activity_lines week completed
}

# Write the whole current-priorities.md file.
# Args: today_focus week_focus
# Uses current date/week stamps. Used by /vt:today and /vt:week when the user
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
# This is what makes each ritual own its own gate: /vt:today freshens only Today
# (the week gate is untouched) and /vt:week freshens only Week (the day gate
# stays active until /vt:today also runs). Args: which=today|week, new_focus.
write_focus_section() {
  local which="$1" new_focus="$2" workspace
  workspace=$(basename "$(pwd)")
  local today_focus today_stamp week_focus week_stamp
  today_focus=$(read_focus today); today_stamp=$(read_today_stamp)
  week_focus=$(read_focus week);   week_stamp=$(read_week_stamp)
  case "$which" in
    today) today_focus="$new_focus"; today_stamp=$(iso_today) ;;
    week)  week_focus="$new_focus";  week_stamp=$(iso_week_num) ;;
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
# state change so the file doesn't lie between /vt:today invocations.
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
  iw=$(iso_week_num)
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
