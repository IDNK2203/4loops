#!/usr/bin/env bash
# vt-today.sh — today's focus operations (v2.5 Real C: priorities are the main surface).
# Modes:
#   vt-today.sh --orient          → orientation block: yesterday carry-forward, store pull
#                                   (urgent/today levers), week anchors, SUGGESTED_FOCUS
#   vt-today.sh --default         → print space-separated suggested focus IDs only
#   vt-today.sh --current         → print currently-set Today focus IDs (regardless of stamp)
#   vt-today.sh --yesterday       → what happened last Today (focus + transitions that day)
#   vt-today.sh [--project P] <ID|"free text"> ...
#                                 → write the Today section with these items (preserves Week).
#                                   IDs may be board (P0-12) or store (CAP-003); free text lands
#                                   in the store on the spot (lever=today) — no capture step.
#   vt-today.sh                   → no-op; print usage
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=./vt-priorities-lib.sh
source "$SCRIPT_DIR/vt-priorities-lib.sh"

PROJECT=""
if [ "${1:-}" = "--project" ]; then PROJECT="${2:-}"; shift 2; fi

case "${1:-}" in
  --orient)
    render_today_orient
    ;;
  --default)
    printf '%s\n' "$(suggest_today)"
    ;;
  --current)
    read_focus today
    ;;
  --yesterday)
    render_yesterday
    ;;
  "")
    cat <<'USAGE' >&2
Usage:
  vt-today.sh --orient                  Orientation: carry-forward · store pull · week anchors · SUGGESTED_FOCUS
  vt-today.sh --default                 Suggested focus IDs only
  vt-today.sh --current                 Currently-set Today focus IDs
  vt-today.sh --yesterday               Last Today's focus + that day's transitions
  vt-today.sh [--project P] <ID|"text"> ...
                                        Write the Today section (board IDs, CAP IDs, or free text → store)
USAGE
    exit 1
    ;;
  *)
    # WEEK-BEFORE-TODAY (hard): on a fresh ISO week, /week must run first — the week
    # stamp carries the ritual order. Refuse to set today's focus until the week is
    # current. configure's bootstrap sets the week stamp before calling this, so it
    # passes; vt-priority.sh writes Today directly and is unaffected. Bypass for
    # internal/repair use: VT_ALLOW_TODAY_FIRST=1.
    if [ "${VT_ALLOW_TODAY_FIRST:-0}" != "1" ] && ! week_stamp_current "$(read_week_stamp)"; then
      echo "4loops: it's a new week — run /4loops:week first, then /4loops:today (the week's anchors flow into the day)." >&2
      exit 3
    fi
    new_today_focus=$(resolve_focus_tokens today "$PROJECT" "$@")
    # Freshen ONLY Today's stamp; the week gate is left exactly as it was.
    write_focus_section today "$new_today_focus" "today"
    # Store levers follow the committed day (CAP in focus → today; dropped → later).
    # board.md is never touched here.
    sync_store_levers_today "$new_today_focus"
    # Arm the rail (first run) and — only if the gate is now fully clear (today
    # AND week fresh) — record THIS session as cleared so continuous work
    # carries across midnight without re-blocking.
    # shellcheck source=./vt-guard-lib.sh
    source "$SCRIPT_DIR/vt-guard-lib.sh"
    vt_arm_rail
    vt_gate_active || vt_mark_session_cleared "${CLAUDE_CODE_SESSION_ID:-}"
    echo "Today set: ${new_today_focus:-—}"
    ;;
esac
