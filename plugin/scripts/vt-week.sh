#!/usr/bin/env bash
# vt-week.sh — this week's focus operations. Same shape as vt-today.sh (v2.5 Real C).
#   vt-week.sh --orient          → last week's anchors (alive / finished), committed board
#                                  work, store pull, SUGGESTED_FOCUS
#   vt-week.sh --default         → suggested anchor IDs only
#   vt-week.sh --current         → currently-set Week focus IDs
#   vt-week.sh [--project P] <ID|"free text"> ...
#                                → write the Week section (preserves Today). Free text lands
#                                  in the store (lever=later — week is not a lever).
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=./vt-priorities-lib.sh
source "$SCRIPT_DIR/vt-priorities-lib.sh"

PROJECT=""
if [ "${1:-}" = "--project" ]; then PROJECT="${2:-}"; shift 2; fi

case "${1:-}" in
  --orient)
    render_week_orient
    ;;
  --default)
    printf '%s\n' "$(suggest_week)"
    ;;
  --current)
    read_focus week
    ;;
  "")
    cat <<'USAGE' >&2
Usage:
  vt-week.sh --orient                  Orientation: last week alive/finished · board work · store pull · SUGGESTED_FOCUS
  vt-week.sh --default                 Suggested anchor IDs only
  vt-week.sh --current                 Currently-set Week focus IDs
  vt-week.sh [--project P] <ID|"text"> ...
                                       Write the Week section (board IDs, CAP IDs, or free text → store)
USAGE
    exit 1
    ;;
  *)
    new_week_focus=$(resolve_focus_tokens week "$PROJECT" "$@")
    # Freshen ONLY the Week stamp; the day gate stays active until /4loops:today runs.
    write_focus_section week "$new_week_focus" "week"
    # Arm the rail; record this session as cleared only if the gate is now fully
    # clear (on a new ISO week, today is usually still stale → not yet cleared).
    # shellcheck source=./vt-guard-lib.sh
    source "$SCRIPT_DIR/vt-guard-lib.sh"
    vt_arm_rail
    vt_gate_active || vt_mark_session_cleared "${CLAUDE_CODE_SESSION_ID:-}"
    echo "Week set: ${new_week_focus:-—}"
    ;;
esac
