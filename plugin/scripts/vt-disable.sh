#!/usr/bin/env bash
# vt-disable.sh — the workspace opt-out switch for 4loops enforcement (v2.5 Packet 010).
#
#   vt-disable.sh --status | status    report ENABLED / DISABLED   (read-only)
#   vt-disable.sh --on     | on       write .4loops/disabled → every hook fails open
#   vt-disable.sh --off    | off      remove it              → enforcement returns
#
# What the flag switches off, wholesale: the orientation gate (vt-gate.sh /
# vt-bash-gate.sh staleness check), the rail-capability check, the rail-owned
# record protection, and the UserPromptSubmit nudge. Full opt-out is the point —
# a half-off rail that still refused a board hand-edit would be worse than either
# honest state.
#
# What it does NOT touch: board.md, current-priorities.md, store/, tasks/,
# archive/, transitions.log, config. Nothing is deleted, so `--off` resumes the
# same board you left.
#
# BASH-GATE TIERS: `--status` is declared read-only (vt_rail_readonly_modes) and
# is never blocked. `on`/`off` are tier `optout` and need the `disable` capability
# — i.e. the USER typed /4loops:disable. That, plus .4loops/disabled being a
# rail-owned record the agent cannot write by hand, is what stops an agent from
# switching off its own gate. Opting out is the user's call alone.
#
# NOTE the asymmetry: once the flag is on, the gates fail open, so `--off` runs
# without a capability. Turning the rail back ON is never something to block.
set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
VT_DIR="${VT_DIR:-./.4loops}"
# shellcheck source=./vt-priorities-lib.sh
source "$SCRIPT_DIR/vt-priorities-lib.sh" 2>/dev/null || true
# shellcheck source=./vt-guard-lib.sh
source "$SCRIPT_DIR/vt-guard-lib.sh" 2>/dev/null || true

FLAG="$VT_DIR/disabled"

usage() { printf 'usage: vt-disable.sh --status | --on | --off   (bare status|on|off also work)\n' >&2; }

print_status() {
  if [ -f "$FLAG" ]; then
    printf '4loops: DISABLED for this workspace\n'
    printf 'flag:   %s\n' "$FLAG"
    printf 'since:  %s\n' "$(head -1 "$FLAG" 2>/dev/null || printf 'unknown')"
    printf 'off:    orientation gate · rail-capability check · rail-record protection · prompt nudge\n'
    printf 're-enable: rm %s   (or vt-disable.sh --off)\n' "$FLAG"
  else
    printf '4loops: ENABLED for this workspace (no %s)\n' "$FLAG"
    printf 'opt out with: /4loops:disable   (writes %s; deletes no data)\n' "$FLAG"
  fi
}

turn_on() {
  [ -d "$VT_DIR" ] || { printf 'vt-disable: %s does not exist — not a 4loops workspace, nothing to disable\n' "$VT_DIR" >&2; exit 2; }
  if [ -f "$FLAG" ]; then
    printf '4loops: already DISABLED (%s exists)\n' "$FLAG"
    printf 'since:  %s\n' "$(head -1 "$FLAG" 2>/dev/null || printf 'unknown')"
    return 0
  fi
  printf 'disabled %s — 4loops enforcement opted out for this workspace\n' "$(date "+%Y-%m-%d %H:%M")" > "$FLAG" 2>/dev/null \
    || { printf 'vt-disable: could not write %s\n' "$FLAG" >&2; exit 2; }
  printf '4loops: DISABLED — wrote %s\n' "$FLAG"
  printf 'Off now: orientation gate · rail-capability check · rail-record protection · prompt nudge.\n'
  printf 'Kept:    board.md · current-priorities.md · store/ · tasks/ · archive/ · config (nothing deleted).\n'
  printf 're-enable: rm %s   (or vt-disable.sh --off)\n' "$FLAG"
}

turn_off() {
  if [ -f "$FLAG" ]; then
    rm -f "$FLAG" 2>/dev/null || { printf 'vt-disable: could not remove %s\n' "$FLAG" >&2; exit 2; }
    printf '4loops: ENABLED — removed %s\n' "$FLAG"
  else
    printf '4loops: already ENABLED (no %s)\n' "$FLAG"
  fi
  printf 'Enforcement is back. The orientation gate returns as soon as priorities are stale — run /4loops:week.\n'
}

case "${1:---status}" in
  --status) print_status ;;
  status)   print_status ;;
  --on)     turn_on ;;
  on)       turn_on ;;
  --off)    turn_off ;;
  off)      turn_off ;;
  -h|--help|help) usage; exit 0 ;;
  *) printf 'vt-disable: has no %s mode (use --status | --on | --off)\n' "$1" >&2; usage; exit 2 ;;
esac
