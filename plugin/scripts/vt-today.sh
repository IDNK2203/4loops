#!/usr/bin/env bash
# vt-today.sh — today's focus operations.
# Modes:
#   vt-today.sh --default        → print space-separated carry-forward default focus IDs
#   vt-today.sh --current        → print currently-set Today focus IDs (regardless of stamp)
#   vt-today.sh <ID1> <ID2> ...  → write new Today section with these IDs (preserves Week section)
#   vt-today.sh                  → no-op; print usage
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=./vt-priorities-lib.sh
source "$SCRIPT_DIR/vt-priorities-lib.sh"

case "${1:-}" in
  --default)
    compute_carry_forward today
    ;;
  --current)
    read_focus today
    ;;
  "")
    cat <<'USAGE' >&2
Usage:
  vt-today.sh --default        Carry-forward default focus IDs (for SKILL.md to suggest)
  vt-today.sh --current        Currently-set Today focus IDs
  vt-today.sh <ID1> <ID2> ...  Write new Today section with these IDs
USAGE
    exit 1
    ;;
  *)
    new_today_focus="$*"
    # WEEK-BEFORE-TODAY (hard): on a fresh ISO week, /week must run first — the week
    # stamp carries the ritual order. Refuse to set today's focus until the week is
    # current. configure's bootstrap sets the week stamp before calling this, so it
    # passes; vt-priority.sh writes Today directly and is unaffected. Bypass for
    # internal/repair use: VT_ALLOW_TODAY_FIRST=1.
    if [ "${VT_ALLOW_TODAY_FIRST:-0}" != "1" ] && ! week_stamp_current "$(read_week_stamp)"; then
      echo "4loops: it's a new week — run /4loops:week first, then /4loops:today (the week's context flows into the day)." >&2
      exit 3
    fi
    # Freshen ONLY Today's stamp; the week gate is left exactly as it was.
    write_focus_section today "$new_today_focus"
    # Arm the rail (first run) and — only if the gate is now fully clear (today
    # AND week fresh) — record THIS session as cleared so continuous work
    # carries across midnight without re-blocking.
    # shellcheck source=./vt-guard-lib.sh
    source "$SCRIPT_DIR/vt-guard-lib.sh"
    vt_arm_rail
    vt_gate_active || vt_mark_session_cleared "${CLAUDE_CODE_SESSION_ID:-}"
    echo "Today set: ${new_today_focus}"
    ;;
esac
