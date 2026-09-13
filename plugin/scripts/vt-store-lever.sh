#!/usr/bin/env bash
# vt-store-lever.sh — change priority lever on store CAP items (no board writes).
#
#   vt-store-lever.sh <CAP-ID> <urgent|today|later>
#   vt-store-lever.sh set <CAP-ID> <urgent|today|later>
#   vt-store-lever.sh today <CAP-ID> [<CAP-ID>…]   # pull later/urgent → today
#   vt-store-lever.sh --today <CAP-ID> […]         # same
#
# Thin prioritize rails (v2.5 Track C). Does NOT touch board.md.
# Week stays ritual/`/week` — not a fourth lever.
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=./vt-store-lib.sh
source "$SCRIPT_DIR/vt-store-lib.sh"

VT_DIR="${VT_DIR:-./.4loops}"
"$SCRIPT_DIR/vt-init.sh" >/dev/null
vt_store_ensure

usage() {
  sed -n '2,12p' "$0" | sed 's/^# //;s/^#//'
  exit 2
}

[ $# -ge 1 ] || usage

MODE=""
IDS=()
LEVER=""

case "$1" in
  -h|--help) usage ;;
  set)
    shift
    [ $# -ge 2 ] || usage
    IDS=("$1"); LEVER="$2"; MODE=set
    ;;
  today|--today)
    shift
    [ $# -ge 1 ] || usage
    MODE=today
    IDS=("$@")
    LEVER=today
    ;;
  urgent|today|later)
    # accidental: lever first — need id
    echo "error: CAP-ID required before lever (got '$1')" >&2
    usage
    ;;
  -*)
    echo "unknown arg: $1" >&2
    usage
    ;;
  *)
    # <CAP-ID> <lever>
    [ $# -ge 2 ] || usage
    IDS=("$1"); LEVER="$2"; MODE=set
    ;;
esac

case "$LEVER" in
  urgent|today|later) ;;
  *) echo "error: lever must be urgent|today|later (got '$LEVER')" >&2; exit 2 ;;
esac

reason="prioritize"
[ "$MODE" = "today" ] && reason="pull-to-today"

ok=0
for id in "${IDS[@]}"; do
  vt_store_set_lever "$id" "$LEVER" "$reason" || exit $?
  ok=$((ok + 1))
done

echo "store: updated lever on ${ok} item(s) (board untouched)."
