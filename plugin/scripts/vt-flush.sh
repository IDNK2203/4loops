#!/usr/bin/env bash
# vt-flush.sh [--dwell N | --all] [--dry-run]
# vt-flush.sh --restore <id> [--to <state>]
#
# Done → archive flush (v2.5 Track D · Manage).
#
# Done is a SHORT-LIVED orientation column — "what I just finished", not a history
# dump. After a dwell (default 7 days, i.e. the week rolloff) a Done story leaves
# the grid for archive/<month>/closed.md. The archive is append-only, exactly like
# the abandon trail, and `--restore` puts a row back on the board — so a flush is
# never a one-way door.
#
# Dwell comes from, in order: --dwell N, $VT_DONE_DWELL_DAYS, `done-dwell: N` in
# .4loops/config, else 7. `--dwell 0` / `--all` flush every Done row now.
# Age is measured from the story's last transition (when it went Done); a story
# with no transition log entry has no measurable age and is NOT flushed.
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=./vt-priorities-lib.sh
source "$SCRIPT_DIR/vt-priorities-lib.sh"
# shellcheck source=./vt-drift-lib.sh
source "$SCRIPT_DIR/vt-drift-lib.sh"

DWELL=""; DRY=0; RESTORE=""; TO="done"
while [ $# -gt 0 ]; do
  case "$1" in
    --dwell)   DWELL="${2:-}"; shift 2 ;;
    --all)     DWELL=0; shift ;;
    --dry-run) DRY=1; shift ;;
    --restore) RESTORE="${2:-}"; shift 2 ;;
    --to)      TO="${2:-done}"; shift 2 ;;
    *) echo "usage: vt-flush.sh [--dwell N | --all] [--dry-run] | --restore <id> [--to <state>]" >&2; exit 1 ;;
  esac
done

[ -f "$BOARD" ] || { echo "No board yet — nothing to flush." >&2; exit 0; }

# ── Restore: pull a row back out of the archive onto the grid ─────────────────
if [ -n "$RESTORE" ]; then
  case "$TO" in planning|in-progress|testing|done) ;;
    *) echo "--to must be planning|in-progress|testing|done" >&2; exit 1 ;; esac
  if [ -n "$(story_state "$RESTORE")" ]; then
    echo "${RESTORE} is already on the board (${TO} restore is a no-op)." >&2; exit 0
  fi
  # Last matching archive record wins (closed · abandoned · removed · merged · migrated);
  # strip the trailing " · <kind> <date>" note to recover the cell as it was.
  cell=$(grep -rhF -- "**${RESTORE}**" "$VT_DIR/archive" 2>/dev/null \
         | grep '^- ' | tail -1 | sed -E 's/^- //; s/ · [a-z→-]+ [0-9]{4}-[0-9]{2}-[0-9]{2}.*$//')
  [ -z "$cell" ] && { echo "No archive record for ${RESTORE} under ${VT_DIR}/archive." >&2; exit 1; }
  case "$TO" in planning) pad="| ${cell} |  |  |  |" ;; in-progress) pad="|  | ${cell} |  |  |" ;;
                testing)  pad="|  |  | ${cell} |  |" ;; done) pad="|  |  |  | ${cell} |" ;; esac
  # A pre-migration board still carries the Backlog pen in front — pad by one cell.
  if grep -qxF '| Backlog | Planning | In Progress | Testing | Done |' "$BOARD"; then pad="|  ${pad}"; fi
  printf '%s\n' "$pad" >> "$BOARD"
  "$SCRIPT_DIR/vt-repack.sh"
  "$SCRIPT_DIR/vt-refresh-counts.sh"
  printf '%s\t%s\t%s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$RESTORE" "archived→${TO} (restore)" \
    >> "$VT_DIR/transitions.log"
  refresh_priorities_activity
  echo "${RESTORE}: restored from archive → ${TO} (the archive record stays; it is append-only)."
  exit 0
fi

# ── Dwell resolution ──────────────────────────────────────────────────────────
if [ -z "$DWELL" ]; then
  DWELL="${VT_DONE_DWELL_DAYS:-}"
  [ -z "$DWELL" ] && [ -f "$VT_DIR/config" ] \
    && DWELL=$(awk -F': *' '/^done-dwell:/ { print $2; exit }' "$VT_DIR/config")
  [ -z "$DWELL" ] && DWELL=7
fi
case "$DWELL" in ''|*[!0-9]*) echo "--dwell wants a whole number of days (got '$DWELL')" >&2; exit 1 ;; esac

ripe=""; held=0
while read -r id; do
  [ -z "$id" ] && continue
  if [ "$DWELL" -eq 0 ]; then ripe="${ripe}${id}"$'\n'; continue; fi
  d=$(last_transition_date "$id")
  [ -z "$d" ] && { held=$((held + 1)); continue; }   # unknown age ≠ stale
  if [ "$(days_since "$d")" -ge "$DWELL" ]; then ripe="${ripe}${id}"$'\n'; else held=$((held + 1)); fi
done < <(board_rows | awk -F'\t' '$2=="done"{print $1}')

n=$(printf '%s' "$ripe" | grep -c . || true)
if [ "$n" -eq 0 ]; then
  echo "flush: nothing ripe in Done (dwell ${DWELL}d; ${held} still dwelling)."
  exit 0
fi

if [ "$DRY" = 1 ]; then
  echo "flush (dry-run, dwell ${DWELL}d): ${n} Done story(ies) would archive:"
  while IFS= read -r id; do [ -z "$id" ] && continue; printf -- '  - %s  %s\n' "$id" "$(story_title "$id")"; done <<< "$ripe"
  exit 0
fi

month=$(iso_today | cut -c1-7)
_archive_ids "$ripe" "$VT_DIR/archive/$month/closed.md" "closed"
_remove_board_rows "$ripe"
refresh_counts
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
while IFS= read -r id; do
  [ -z "$id" ] && continue
  printf '%s\t%s\t%s\n' "$TS" "$id" "done→archived (flush)" >> "$VT_DIR/transitions.log"
done <<< "$ripe"
refresh_priorities_activity

printf 'flush: %d Done story(ies) → archive/%s/closed.md (dwell %sd; %d still dwelling).\n' \
  "$n" "$month" "$DWELL" "$held"
echo "  reversible: vt-flush.sh --restore <id> puts a row back (the archive record stays — append-only)."
