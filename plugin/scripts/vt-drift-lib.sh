#!/usr/bin/env bash
# vt-drift-lib.sh — drift detection (surface-only) + weekly rollover/archive.
# Sourced AFTER vt-priorities-lib.sh (uses BOARD/TRANSITIONS/VT_DIR + iso_* +
# story_title). NOT directly invocable.
#
# Per BRIEF §7: drift NEVER blocks. The sentinel RENDERS these signals; the
# daily/weekly reconciliation ritual RESOLVES them. The only state mutation here
# is the weekly rollover (Done → closed, abandoned → abandoned), which auto-fires
# once per ISO week (idempotent marker) and is also reachable via /4loops:close --weekly.

DRIFT_CAP="${VT_DRIFT_CAP:-25}"
DRIFT_STALE_DAYS="${VT_DRIFT_STALE_DAYS:-14}"
DRIFT_ABANDON_DAYS="${VT_DRIFT_ABANDON_DAYS:-21}"
DRIFT_DUE_SOON_DAYS="${VT_DRIFT_DUE_SOON_DAYS:-3}"

# Emit one line per story row: "<ID>\t<state>\t<cell-content>".
board_rows() {
  [ -f "$BOARD" ] || return 0
  awk -F'|' '
    /^\| Backlog \| Planning \| In Progress \| Testing \| Done \|$/ { in_k=1; next }
    in_k && /^\| --/ { in_b=1; next }
    in_b && /^\|/ {
      for (i=2;i<=6;i++){ c=$i; gsub(/^ +| +$/,"",c);
        if (c!=""){
          split("backlog planning in-progress testing done", st, " ")
          id=""
          if (match(c, /\*\*[A-Za-z0-9]+-[0-9]+\*\*/)) id=substr(c, RSTART+2, RLENGTH-4)
          print id "\t" st[i-1] "\t" c
          # no break: dense rows hold a story per column, emit them all
        }
      }
    }
  ' "$BOARD"
}

# Whole days since a YYYY-MM-DD date (BSD + GNU). Large number if unknown.
days_since() {
  local d="$1" then now
  [ -z "$d" ] && { echo 99999; return; }
  then=$(date -j -f "%Y-%m-%d" "$d" +%s 2>/dev/null || date -d "$d" +%s 2>/dev/null || true)
  [ -z "$then" ] && { echo 99999; return; }
  now=$(date +%s)
  echo $(( (now - then) / 86400 ))
}

# Date (YYYY-MM-DD) of the most recent transition for a story, or empty.
last_transition_date() {
  local id="$1"
  [ -f "$TRANSITIONS" ] || return 0
  awk -F'\t' -v id="$id" '$2==id { d=substr($1,1,10) } END { if (d) print d }' "$TRANSITIONS"
}

# States at/over the cap. One "state N (cap C)" line each, or empty.
check_caps() {
  local cap="${1:-$DRIFT_CAP}"
  board_rows | awk -F'\t' -v cap="$cap" '
    { n[$2]++ }
    END {
      split("backlog planning in-progress testing done", o, " ")
      for (i=1;i<=5;i++){ s=o[i]; if (n[s]+0 >= cap) printf "%s %d (cap %d)\n", s, n[s], cap }
    }'
}

# Active stories (in-progress/testing) untouched >= N days. "<ID> <state> <age>d".
# A story with NO transition-log entry has no measurable age → NOT stale (skip),
# rather than treating unknown age as infinite.
find_stale() {
  local days="${1:-$DRIFT_STALE_DAYS}" id st d age
  board_rows | awk -F'\t' '$2=="in-progress"||$2=="testing"{print $1"\t"$2}' \
  | while IFS=$'\t' read -r id st; do
      [ -z "$id" ] && continue
      d=$(last_transition_date "$id"); [ -z "$d" ] && continue
      age=$(days_since "$d")
      [ "$age" -ge "$days" ] && printf '%s %s %dd\n' "$id" "$st" "$age"
    done
}

# Non-done, non-backlog stories untouched >= N days. IDs only (for the rollup).
# Two safeguards against perceived data loss in weekly_rollover:
#   - NEVER abandon a story the user is actively focused on (today or week).
#   - A story with NO transition-log entry is NOT abandoned (unknown age ≠ stale),
#     so hand-added / migrated rows aren't swept on the first rollover.
find_abandoned() {
  local days="${1:-$DRIFT_ABANDON_DAYS}" id d age focus
  focus=" $(read_focus today) $(read_focus week) "
  board_rows | awk -F'\t' '$2=="planning"||$2=="in-progress"||$2=="testing"{print $1}' \
  | while read -r id; do
      [ -z "$id" ] && continue
      case "$focus" in *" $id "*) continue ;; esac
      d=$(last_transition_date "$id"); [ -z "$d" ] && continue
      age=$(days_since "$d")
      [ "$age" -ge "$days" ] && echo "$id"
    done
}

# Active (non-done) stories whose deadline is in the past. "<id> <due> <Nd over>".
# Off-plan signal — a story you said you'd finish by a date that has slipped.
# Integer date compare (YYYYMMDD) avoids non-portable string `<` in test.
find_overdue() {
  local today_n id st due
  today_n=$(iso_today); today_n=${today_n//-/}
  board_rows | awk -F'\t' '$2!="done"{print $1"\t"$2}' \
  | while IFS=$'\t' read -r id st; do
      [ -z "$id" ] && continue
      due=$(story_deadline "$id"); [ -z "$due" ] && continue
      [ "${due//-/}" -lt "$today_n" ] && printf '%s %s %dd over\n' "$id" "$due" "$(days_since "$due")"
    done
}

# Active stories due within the next N days (today..today+N). "<id> <due>".
# Drifting-soon signal — surface in reconciliation before the date slips.
find_due_soon() {
  local days="${1:-$DRIFT_DUE_SOON_DAYS}" today_n horizon horizon_n id due st d
  today_n=$(iso_today); today_n=${today_n//-/}
  horizon=$(date -v+"${days}"d +%Y-%m-%d 2>/dev/null || date -d "today +${days} days" +%Y-%m-%d)
  horizon_n=${horizon//-/}
  board_rows | awk -F'\t' '$2!="done"{print $1}' \
  | while read -r id; do
      [ -z "$id" ] && continue
      due=$(story_deadline "$id"); [ -z "$due" ] && continue
      d=${due//-/}
      [ "$d" -ge "$today_n" ] && [ "$d" -le "$horizon_n" ] && printf '%s %s\n' "$id" "$due"
    done
}

# Compact one-line drift summary for the sentinel dashboard (or empty).
render_drift() {
  local caps stale ab over soon n out=""
  caps=$(check_caps)
  over=$(find_overdue)
  soon=$(find_due_soon)
  stale=$(find_stale)
  ab=$(find_abandoned)
  [ -n "$over" ]  && out="${out}overdue[$(printf '%s' "$over" | paste -sd ', ' -)]; "
  [ -n "$soon" ]  && out="${out}due-soon[$(printf '%s' "$soon" | paste -sd ', ' -)]; "
  [ -n "$caps" ]  && out="${out}cap[$(printf '%s' "$caps" | paste -sd ', ' -)]; "
  [ -n "$stale" ] && out="${out}stale[$(printf '%s' "$stale" | paste -sd ', ' -)]; "
  if [ -n "$ab" ]; then n=$(printf '%s\n' "$ab" | grep -c .); out="${out}${n} abandoned candidate(s); "; fi
  [ -n "$out" ] && printf '[DRIFT] %s' "${out%; }"
}

# Verbose drift report with titles (for /4loops:close + the reconciliation ritual).
drift_report() {
  local any=0 line id age t
  echo "Drift report ($(iso_today)) — surface-only, resolve during /4loops:today · /4loops:week:"
  while IFS= read -r line; do [ -z "$line" ] && continue; any=1; echo "  cap:    $line"; done < <(check_caps)
  while IFS= read -r line; do
    [ -z "$line" ] && continue; any=1
    id=${line%% *}; t=$(story_title "$id")
    echo "  overdue:  $line${t:+  — $t}"
  done < <(find_overdue)
  while IFS= read -r line; do
    [ -z "$line" ] && continue; any=1
    id=${line%% *}; t=$(story_title "$id")
    echo "  due-soon: $line${t:+  — $t}"
  done < <(find_due_soon)
  while IFS= read -r line; do
    [ -z "$line" ] && continue; any=1
    id=${line%% *}; t=$(story_title "$id")
    echo "  stale:  $line${t:+  — $t}"
  done < <(find_stale)
  while IFS= read -r id; do
    [ -z "$id" ] && continue; any=1
    age=$(days_since "$(last_transition_date "$id")"); t=$(story_title "$id")
    echo "  abandon-candidate: $id ${age}d${t:+  — $t}"
  done < <(find_abandoned)
  [ "$any" = 0 ] && echo "  (clean — no caps hit, nothing stale or abandoned)"
}

# Recompute the **Counts:** header from the board (BSD/GNU sed).
refresh_counts() {
  [ -f "$BOARD" ] || return 0
  local counts
  counts=$(board_rows | awk -F'\t' '
    { n[$2]++ }
    END {
      printf "Backlog %d · Planning %d · In Progress %d · Testing %d · Done %d",
        n["backlog"]+0, n["planning"]+0, n["in-progress"]+0, n["testing"]+0, n["done"]+0
    }')
  sed -i.bak "s|^\*\*Counts:\*\*.*|**Counts:** ${counts}|" "$BOARD" 2>/dev/null && rm -f "${BOARD}.bak"
}

# Append given story IDs (newline/space list) to an archive file with kind+date.
_archive_ids() {
  local ids="$1" file="$2" kind="$3" today id content
  [ -z "${ids//[[:space:]]/}" ] && return 0
  mkdir -p "$(dirname "$file")" 2>/dev/null || true   # create the month dir only once there IS content
  today=$(iso_today)
  [ -f "$file" ] || printf '# Archive — %s\n\n' "$kind" > "$file"
  while IFS= read -r id; do
    [ -z "$id" ] && continue
    content=$(board_rows | awk -F'\t' -v id="$id" '$1==id{print $3; exit}')
    [ -z "$content" ] && content="**$id**"
    printf -- '- %s · %s %s\n' "$content" "$kind" "$today" >> "$file"
  done <<EOF
$ids
EOF
}

# Remove the given story IDs from the board and re-grid densely. Dense storage
# packs many stories per row, so we drop the matching CELLS (not whole rows,
# which would take co-located stories with them) and rebuild the grid.
# IDs may arrive newline- or space-separated; flatten to spaces.
_remove_board_rows() {
  local ids tmp
  ids=$(printf '%s' "$1" | tr '\n' ' ')
  [ -z "${ids// /}" ] && return 0
  tmp="${BOARD}.tmp"
  awk -v exclude=" $ids " '
    function excluded(c,   id) {
      if (match(c, /\*\*[A-Za-z0-9]+-[0-9]+\*\*/)) {
        id = substr(c, RSTART+2, RLENGTH-4)
        return index(exclude, " " id " ") > 0
      }
      return 0
    }
    BEGIN { FS="|" }
    /^\| Backlog \| Planning \| In Progress \| Testing \| Done \|$/ { print; hdr=1; next }
    hdr && /^\| --/ { print; inbody=1; next }
    inbody && /^\|/ {
      for (i=2;i<=6;i++){ c=$i; gsub(/^ +| +$/,"",c);
        if (c!="" && !excluded(c)) cells[i-1, ++n[i-1]]=c }
      next
    }
    !inbody { print }
    END {
      rows=0; for (col=1;col<=5;col++) if (n[col]>rows) rows=n[col]
      for (i=1;i<=rows;i++){ line="|";
        for (col=1;col<=5;col++){ c=(i<=n[col])?cells[col,i]:""; line=line " " c " |" }
        print line }
    }
  ' "$BOARD" > "$tmp" && mv "$tmp" "$BOARD"
}

# Weekly rollover: Done → closed.md, abandoned → abandoned.md. Idempotent per
# ISO week via a marker. Safe to call any number of times. Prints a summary line.
weekly_rollover() {
  [ -f "$BOARD" ] || return 0
  local marker="$VT_DIR/.weekly-rolled-$(week_marker_id)"
  [ -f "$marker" ] && return 0
  local month adir done_ids ab_ids dn an
  month=$(iso_today | cut -c1-7)
  adir="$VT_DIR/archive/$month"   # created lazily by _archive_ids only when there's content
  done_ids=$(board_rows | awk -F'\t' '$2=="done"{print $1}')
  ab_ids=$(find_abandoned)
  _archive_ids "$done_ids" "$adir/closed.md"    "closed"
  _archive_ids "$ab_ids"   "$adir/abandoned.md" "abandoned"
  _remove_board_rows "$(printf '%s\n%s' "$done_ids" "$ab_ids")"
  refresh_counts
  : > "$marker" 2>/dev/null || true
  dn=$(printf '%s\n' "$done_ids" | grep -c .)
  an=$(printf '%s\n' "$ab_ids"   | grep -c .)
  printf 'Weekly rollover (%s): %s closed, %s abandoned → archive/%s/\n' \
    "$(week_marker_id)" "$dn" "$an" "$month"
}
