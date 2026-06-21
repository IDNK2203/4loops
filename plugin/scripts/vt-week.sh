#!/usr/bin/env bash
# vt-week.sh — this week's focus operations. Same shape as vt-today.sh.
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=./vt-priorities-lib.sh
source "$SCRIPT_DIR/vt-priorities-lib.sh"

case "${1:-}" in
  --default)
    compute_carry_forward week
    ;;
  --current)
    read_focus week
    ;;
  "")
    cat <<'USAGE' >&2
Usage:
  vt-week.sh --default        Carry-forward default focus IDs
  vt-week.sh --current        Currently-set Week focus IDs
  vt-week.sh <ID1> <ID2> ...  Write new Week section with these IDs
USAGE
    exit 1
    ;;
  *)
    new_week_focus="$*"
    # Freshen ONLY the Week stamp; the day gate stays active until /4loops:today runs.
    write_focus_section week "$new_week_focus"
    # Arm the rail; record this session as cleared only if the gate is now fully
    # clear (on a new ISO week, today is usually still stale → not yet cleared).
    # shellcheck source=./vt-guard-lib.sh
    source "$SCRIPT_DIR/vt-guard-lib.sh"
    vt_arm_rail
    vt_gate_active || vt_mark_session_cleared "${CLAUDE_CODE_SESSION_ID:-}"
    echo "Week set: ${new_week_focus}"
    ;;
esac
