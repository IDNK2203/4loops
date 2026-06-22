#!/usr/bin/env bash
# vt-priority.sh — midweek priority reconciliation (W3).
# Set or reset today's focus BETWEEN the daily/weekly rituals — when work lands
# mid-week you re-point priority without rerunning the whole walk. Freshens the
# Today stamp (so the gate lifts) exactly like /4loops:today, but targeted.
#
#   vt-priority.sh add <ID...>   append IDs to today's focus (dedup), freshen stamp
#   vt-priority.sh set <ID...>   replace today's focus with IDs, freshen stamp
#   vt-priority.sh since         list stories added/moved since the last Today stamp
#                                (and not already in focus) — what to reconsider
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=./vt-priorities-lib.sh
source "$SCRIPT_DIR/vt-priorities-lib.sh"

sub="${1:-}"
[ $# -gt 0 ] && shift

# Freshen Today, arm the rail, and clear this session if the gate is fully clear —
# the same closing move /4loops:today makes, so a midweek re-point also lifts the gate.
_commit_today() {
  write_focus_section today "$1"
  # shellcheck source=./vt-guard-lib.sh
  source "$SCRIPT_DIR/vt-guard-lib.sh"
  vt_arm_rail
  vt_gate_active || vt_mark_session_cleared "${CLAUDE_CODE_SESSION_ID:-}"
}

case "$sub" in
  add)
    merged=$(read_focus today)
    for id in "$@"; do
      [ -z "$id" ] && continue
      case " $merged " in *" $id "*) ;; *) merged="${merged:+$merged }$id" ;; esac
    done
    _commit_today "$merged"
    echo "Today focus: ${merged:-—}"
    ;;
  set)
    new="$*"
    _commit_today "$new"
    echo "Today focus: ${new:-—}"
    ;;
  since)
    stamp=$(read_today_stamp); [ -z "$stamp" ] && stamp=$(iso_today)
    out=$(stories_since "$stamp" "$(read_focus today)")
    if [ -z "$out" ]; then
      echo "(nothing new since ${stamp} — focus is current)"
    else
      echo "Added/moved since ${stamp} (not in focus):"
      printf '%s\n' "$out" | sed 's/^/  /'
    fi
    ;;
  *)
    echo "usage: vt-priority.sh add|set <ID...> | since" >&2; exit 1
    ;;
esac
