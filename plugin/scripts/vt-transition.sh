#!/usr/bin/env bash
# vt-transition.sh <id> <new-state> [--backdate YYYY-MM-DD] [--by <id>]
#
# Moves story <id> to <new-state>.
#   Grid states  (backlog|planning|in-progress|testing|done) — move the cell
#                within the kanban grid; refresh counts.
#   Terminal     (abandoned|superseded) — pull the story OFF the active grid
#                into archive/<month>/abandoned.md immediately (W2), so dead work
#                stops cluttering the board without waiting for the weekly rollover.
# --backdate stamps the transition log + archive record with a past date (closes
#            the no-backdate gap — e.g. recording work that happened days ago).
# --by <id>  records the superseding story on a `superseded` transition.
set -euo pipefail

ID=""; NEW_STATE=""; BACKDATE=""; BY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --backdate) BACKDATE="${2:-}"; shift 2 ;;
    --by)       BY="${2:-}"; shift 2 ;;
    *) if [ -z "$ID" ]; then ID="$1"; elif [ -z "$NEW_STATE" ]; then NEW_STATE="$1"; fi; shift ;;
  esac
done
[ -n "$ID" ] && [ -n "$NEW_STATE" ] || {
  echo "usage: vt-transition <id> <new-state> [--backdate YYYY-MM-DD] [--by <id>]" >&2; exit 1; }

case "$NEW_STATE" in
  backlog|planning|in-progress|testing|done|abandoned|superseded) ;;
  *) echo "Invalid state: $NEW_STATE (valid: backlog|planning|in-progress|testing|done|abandoned|superseded)" >&2; exit 1 ;;
esac

VT_DIR="${VT_DIR:-./.4loops}"
BOARD="$VT_DIR/board.md"
[ -f "$BOARD" ] || { echo "No board yet — run /4loops:configure first to set up your board." >&2; exit 1; }

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=./vt-priorities-lib.sh
source "$SCRIPT_DIR/vt-priorities-lib.sh"
# shellcheck source=./vt-drift-lib.sh
source "$SCRIPT_DIR/vt-drift-lib.sh"

# Timestamp for the log / archive record: backdated noon-UTC, or now. An invalid
# backdate is dropped (warned) and we fall back to now.
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
if [ -n "$BACKDATE" ]; then
  BTS=$(vt_backdate_ts "$BACKDATE")
  if [ -n "$BTS" ]; then TS="$BTS"; else BACKDATE=""; fi
fi

OLD_STATE=$(story_state "$ID")
[ -z "$OLD_STATE" ] && { echo "Story ${ID} not found in board" >&2; exit 1; }

# ── Terminal states: archive + remove from the active grid ────────────────────
if [ "$NEW_STATE" = "abandoned" ] || [ "$NEW_STATE" = "superseded" ]; then
  if [ "$OLD_STATE" = "done" ]; then
    echo "${ID} is already Done — leave it for the weekly rollover, not ${NEW_STATE}." >&2; exit 1
  fi
  content=$(board_rows | awk -F'\t' -v id="$ID" '$1==id{print $3; exit}')
  [ -z "$content" ] && content="**$ID**"
  recdate="${BACKDATE:-$(iso_today)}"
  month=$(printf '%s' "$recdate" | cut -c1-7)
  afile="$VT_DIR/archive/$month/abandoned.md"
  mkdir -p "$(dirname "$afile")"
  [ -f "$afile" ] || printf '# Archive — abandoned\n\n' > "$afile"
  note="${NEW_STATE} ${recdate}"
  [ "$NEW_STATE" = "superseded" ] && [ -n "$BY" ] && note="${note} (superseded-by: ${BY})"
  printf -- '- %s · %s\n' "$content" "$note" >> "$afile"
  _remove_board_rows "$ID"
  refresh_counts
  logline="${OLD_STATE}→${NEW_STATE}"
  [ "$NEW_STATE" = "superseded" ] && [ -n "$BY" ] && logline="${logline} by:${BY}"
  printf "%s\t%s\t%s\n" "$TS" "$ID" "$logline" >> "$VT_DIR/transitions.log"
  refresh_priorities_activity
  echo "${ID}: ${OLD_STATE} → ${NEW_STATE} (archived → archive/${month}/abandoned.md)"
  exit 0
fi

# ── Grid states: move the cell within the kanban ──────────────────────────────
case "$NEW_STATE" in
  backlog) NEW_COL=1 ;; planning) NEW_COL=2 ;; in-progress) NEW_COL=3 ;; testing) NEW_COL=4 ;; done) NEW_COL=5 ;;
esac
case "$OLD_STATE" in
  backlog) OLD_COL=1 ;; planning) OLD_COL=2 ;; in-progress) OLD_COL=3 ;; testing) OLD_COL=4 ;; done) OLD_COL=5 ;;
esac

if [ "$OLD_COL" = "$NEW_COL" ]; then
  echo "${ID} already in ${NEW_STATE}" >&2; exit 0
fi

# Rebuild the board as a DENSE grid, moving ID's cell to NEW_COL. Co-located
# stories on ID's row are preserved (dense storage = many stories per row), so we
# can't just replace the row — we re-grid the whole body.
awk -v id="$ID" -v newcol="$NEW_COL" '
  BEGIN { FS = "|" }
  /^\| Backlog \| Planning \| In Progress \| Testing \| Done \|$/ { print; hdr = 1; next }
  hdr && /^\| --/ { print; inbody = 1; next }
  inbody && /^\|/ {
    for (i = 2; i <= 6; i++) {
      c = $i; gsub(/^ +| +$/, "", c)
      if (c == "") continue
      col = (index(c, "**" id "**") > 0) ? newcol : (i - 1)
      cells[col, ++n[col]] = c
    }
    next
  }
  !inbody { print }
  END {
    rows = 0
    for (col = 1; col <= 5; col++) if (n[col] > rows) rows = n[col]
    for (i = 1; i <= rows; i++) {
      line = "|"
      for (col = 1; col <= 5; col++) {
        c = (i <= n[col]) ? cells[col, i] : ""
        line = line " " c " |"
      }
      print line
    }
  }
' "$BOARD" > "${BOARD}.tmp" && mv "${BOARD}.tmp" "$BOARD"

"$SCRIPT_DIR/vt-refresh-counts.sh"

printf "%s\t%s\t%s→%s\n" "$TS" "$ID" "$OLD_STATE" "$NEW_STATE" >> "$VT_DIR/transitions.log"

# Refresh activity slices in current-priorities.md so it doesn't lie between
# /4loops:today runs. No-op if the file doesn't exist yet; preserves stamps + focus.
refresh_priorities_activity

# W1 done-rule: a MODELING story's DONE is "model coherent + traceable", witnessed
# by a decision log — not just "shipped". Surface the reminder (never block: fail-open).
if [ "$NEW_STATE" = "done" ] && [ "$(story_type "$ID")" = "modeling" ]; then
  echo "note: ${ID} is a MODELING story — DONE = a coherent + traceable decision log, not just 'shipped'." >&2
fi

echo "${ID}: ${OLD_STATE} → ${NEW_STATE}"
