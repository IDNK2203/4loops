#!/usr/bin/env bash
# vt-store-expire.sh — drive the store expiry state machine.
#
#   vt-store-expire.sh                  # activate captured + expire actives past TTL
#   vt-store-expire.sh --activate-only  # captured → active only
#   vt-store-expire.sh --expire-only    # active → expired (TTL)
#   vt-store-expire.sh --clear          # expired → cleared
#   vt-store-expire.sh --force-expire <id>   # active → expired ignoring TTL (tests)
#   vt-store-expire.sh --activate <id>       # single-item captured → active
#   vt-store-expire.sh --clear-id <id>       # single-item expired → cleared
#
# States: captured → active → expired → cleared
# TTL: VT_STORE_TTL_DAYS or config store_ttl_days (default 14).
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=./vt-store-lib.sh
source "$SCRIPT_DIR/vt-store-lib.sh"

VT_DIR="${VT_DIR:-./.4loops}"
vt_store_ensure
d=$(vt_store_dir)
ttl=$(vt_store_ttl_days)

MODE=tick
FORCE_ID=""
SINGLE_ID=""

while [ $# -gt 0 ]; do
  case "$1" in
    --activate-only) MODE=activate-only; shift ;;
    --expire-only)   MODE=expire-only; shift ;;
    --clear)         MODE=clear; shift ;;
    --force-expire)  MODE=force-expire; FORCE_ID="${2:?}"; shift 2 ;;
    --activate)      MODE=activate-one; SINGLE_ID="${2:?}"; shift 2 ;;
    --clear-id)      MODE=clear-one; SINGLE_ID="${2:?}"; shift 2 ;;
    -h|--help)
      sed -n '2,16p' "$0" | sed 's/^# //;s/^#//'
      exit 0
      ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

activated=0; expired=0; cleared=0

activate_all() {
  local f id
  shopt -s nullglob
  for f in "$d"/items/*; do
    [ "$(vt_store_get "$f" state)" = "captured" ] || continue
    id=$(vt_store_get "$f" id)
    vt_store_transition "$id" active "auto-activate"
    activated=$((activated + 1))
  done
}

expire_ttl() {
  local f id cap age
  shopt -s nullglob
  for f in "$d"/items/*; do
    [ "$(vt_store_get "$f" state)" = "active" ] || continue
    id=$(vt_store_get "$f" id)
    cap=$(vt_store_get "$f" captured_at)
    age=$(vt_store_age_days "$cap") || continue
    if [ "$age" -ge "$ttl" ]; then
      vt_store_transition "$id" expired "ttl=${ttl}d age=${age}d"
      expired=$((expired + 1))
    fi
  done
}

clear_expired() {
  local f id
  shopt -s nullglob
  for f in "$d"/items/*; do
    [ "$(vt_store_get "$f" state)" = "expired" ] || continue
    id=$(vt_store_get "$f" id)
    vt_store_transition "$id" cleared "clear-expired"
    cleared=$((cleared + 1))
  done
}

case "$MODE" in
  tick)
    activate_all
    expire_ttl
    echo "store-expire: activated=$activated expired=$expired (ttl=${ttl}d)"
    ;;
  activate-only)
    activate_all
    echo "store-expire: activated=$activated"
    ;;
  expire-only)
    expire_ttl
    echo "store-expire: expired=$expired (ttl=${ttl}d)"
    ;;
  clear)
    clear_expired
    echo "store-expire: cleared=$cleared"
    ;;
  force-expire)
    # Allow captured→active first if needed, then force expire
    st=$(vt_store_get "$(vt_store_item_path "$FORCE_ID")" state)
    if [ "$st" = "captured" ]; then
      vt_store_transition "$FORCE_ID" active "pre-force-expire"
    fi
    vt_store_transition "$FORCE_ID" expired "force-expire"
    echo "store-expire: force-expired $FORCE_ID"
    ;;
  activate-one)
    vt_store_transition "$SINGLE_ID" active "manual-activate"
    ;;
  clear-one)
    vt_store_transition "$SINGLE_ID" cleared "manual-clear"
    ;;
esac
