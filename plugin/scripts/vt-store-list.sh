#!/usr/bin/env bash
# vt-store-list.sh [filter] — list detached store items (read-only).
#
# Filters:
#   live|all-live|''     all non-cleared (default)
#   captured|active|expired|cleared|all
#   urgent|today|later   by priority lever (live items only)
#   --lever <lever>      same as lever name filter
#
# v2.5 Track A+C
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=./vt-store-lib.sh
source "$SCRIPT_DIR/vt-store-lib.sh"

VT_DIR="${VT_DIR:-./.4loops}"
FILTER="${1:-live}"
if [ "$FILTER" = "--lever" ]; then
  FILTER="${2:?usage: vt-store-list.sh --lever urgent|today|later}"
fi
vt_store_ensure
d=$(vt_store_dir)

list_one() {
  local path="$1" id st proj title type due cap age lev
  id=$(vt_store_get "$path" id)
  st=$(vt_store_get "$path" state)
  proj=$(vt_store_get "$path" project)
  title=$(vt_store_get "$path" title)
  type=$(vt_store_get "$path" type)
  due=$(vt_store_get "$path" deadline)
  lev=$(vt_store_get_lever "$path")
  cap=$(vt_store_get "$path" captured_at)
  age=$(vt_store_age_days "$cap" 2>/dev/null || echo "?")
  printf '%-8s %-10s %-6s %-4s  age=%sd  %s%s\n' \
    "$id" "$st" "$lev" "$proj" "$age" "$title" "${due:+ (due $due)}"
}

shopt -s nullglob
case "$FILTER" in
  live|all-live|'')
    for f in "$d"/items/*; do list_one "$f"; done
    ;;
  captured|active|expired)
    for f in "$d"/items/*; do
      [ "$(vt_store_get "$f" state)" = "$FILTER" ] && list_one "$f"
    done
    ;;
  urgent|today|later)
    for f in "$d"/items/*; do
      [ "$(vt_store_get_lever "$f")" = "$FILTER" ] && list_one "$f"
    done
    ;;
  cleared)
    for f in "$d"/cleared/*; do list_one "$f"; done
    ;;
  all)
    for f in "$d"/items/* "$d"/cleared/*; do list_one "$f"; done
    ;;
  *)
    echo "usage: vt-store-list.sh [live|captured|active|expired|cleared|all|urgent|today|later|--lever LEVER]" >&2
    exit 2
    ;;
esac
