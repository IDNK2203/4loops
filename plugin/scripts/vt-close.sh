#!/usr/bin/env bash
# vt-close.sh — end-of-day / end-of-week close.
#   vt-close.sh --weekly   Force the weekly rollover (Done → closed, abandoned → abandoned).
#                          Idempotent; normally auto-fires at the first session of a new ISO week.
#   vt-close.sh            Daily close: print the drift report as a retro prompt. No mutation.
set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=./vt-priorities-lib.sh
source "$SCRIPT_DIR/vt-priorities-lib.sh"
# shellcheck source=./vt-drift-lib.sh
source "$SCRIPT_DIR/vt-drift-lib.sh"

case "${1:-}" in
  --weekly)
    out=$(weekly_rollover)
    if [ -n "$out" ]; then echo "$out"; else echo "Weekly rollover already ran this ISO week (no-op)."; fi
    ;;
  *)
    echo "Daily close — nothing archived (the weekly rollover handles that)."
    drift_report
    ;;
esac
