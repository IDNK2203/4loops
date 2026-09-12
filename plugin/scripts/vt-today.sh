#!/usr/bin/env bash
# vt-today.sh — mid-day pull-from-week (v2.5 Packet 006). NOT required to clear the
# gate: the today beat lives inside /week (vt-week.sh … --today / vt-week.sh today).
# This is the standalone escape for re-pointing today's 2–3 from the week mid-day.
#
#   vt-today.sh --orient          → the priorities file + the week to pull from + TODAY_SUGGESTED
#   vt-today.sh --print           → the priorities file
#   vt-today.sh --default         → TODAY_SUGGESTED IDs only
#   vt-today.sh --current         → IDs on today now
#   vt-today.sh --yesterday       → what happened last Today (focus + transitions that day)
#   vt-today.sh [--project P] <ID|"free text"> ...
#                                 → set today's 2–3 from the week. A pick not on the week is
#                                   promoted onto it (cap 5); free text lands in the store
#                                   (lever=today) and on both. Refuses on a stale week.
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=./vt-priorities-lib.sh
source "$SCRIPT_DIR/vt-priorities-lib.sh"

PROJECT=""
if [ "${1:-}" = "--project" ]; then PROJECT="${2:-}"; shift 2; fi

case "${1:-}" in
  --orient)    render_today_orient ;;
  --print)     print_priorities ;;
  --default)   printf '%s\n' "$(suggest_today)" ;;
  --current)   read_focus today; echo ;;
  --yesterday) render_yesterday ;;
  ""|-h|--help)
    cat <<'USAGE' >&2
Usage:
  vt-today.sh --orient                  The file + the week to pull from + TODAY_SUGGESTED
  vt-today.sh --print                   The priorities file
  vt-today.sh --default                 TODAY_SUGGESTED IDs only
  vt-today.sh --current                 IDs on today now
  vt-today.sh --yesterday               Last Today's focus + that day's transitions
  vt-today.sh [--project P] <items>...  Set today's 2–3 from the week (mid-day pull)
USAGE
    exit 1
    ;;
  *)
    # Unknown --flags never become free-text items (see vt-week.sh, Packet 009).
    case "$1" in
      --*) echo "4loops: vt-today.sh has no ${1} mode (read-only modes: --orient --print --default --current --yesterday)." >&2; exit 2 ;;
    esac
    # WEEK FIRST (hard): on a new week the one-shot /week sets the week AND today.
    # Bypass for internal/repair use: VT_ALLOW_TODAY_FIRST=1.
    if [ "${VT_ALLOW_TODAY_FIRST:-0}" != "1" ] && ! week_stamp_current "$(read_week_stamp)"; then
      echo "4loops: it's a new week — run /4loops:week (one-shot orientation: look back, set the week from the store, pick today's 2–3). /today is only the mid-day pull." >&2
      exit 3
    fi
    precheck_today_tokens set "$@" || exit 4
    today_ids=$(resolve_focus_tokens today "$PROJECT" "$@")
    check_today_size "$today_ids" || exit 4
    week_ids=$(week_with_today "$today_ids") || exit 4
    if [ "$week_ids" != "$(read_focus week)" ]; then write_week_list_keep_stamp "$week_ids" "promote-from-today"; fi
    write_focus_section today "$today_ids" "today"
    sync_store_levers_today "$today_ids"
    # shellcheck source=./vt-guard-lib.sh
    source "$SCRIPT_DIR/vt-guard-lib.sh"
    vt_arm_rail
    vt_gate_active || vt_mark_session_cleared "${CLAUDE_CODE_SESSION_ID:-}"
    echo "Today set: ${today_ids:-—}"
    ;;
esac
