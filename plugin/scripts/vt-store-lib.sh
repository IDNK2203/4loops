#!/usr/bin/env bash
# vt-store-lib.sh — detached backlog store helpers (v2.5 Track A · Capture).
#
# Store lives at $VT_DIR/store/ (off-board). Items are CAP-NNN files with a
# key=value header. State machine: captured → active → expired → cleared.
# Priority lever: urgent | today | later (default later) — v2.5 Track C.
# Source this file; do not invoke it directly.
#
# TTL: VT_STORE_TTL_DAYS (default 14), or `store_ttl_days: N` in .4loops/config.

vt_store_dir() {
  printf '%s' "${VT_DIR:-./.4loops}/store"
}

vt_store_ensure() {
  local d
  d=$(vt_store_dir)
  mkdir -p "$d/items" "$d/cleared"
  [ -f "$d/transitions.log" ] || : > "$d/transitions.log"
  [ -f "$d/.counter" ] || echo "0" > "$d/.counter"
}

vt_store_ttl_days() {
  local n="${VT_STORE_TTL_DAYS:-}" cfg="${VT_DIR:-./.4loops}/config"
  if [ -z "$n" ] && [ -f "$cfg" ]; then
    n=$(awk -F: '/^[[:space:]]*store_ttl_days[[:space:]]*:/ {
      gsub(/[[:space:]]/, "", $2); print $2; exit
    }' "$cfg" 2>/dev/null || true)
  fi
  case "$n" in ''|*[!0-9]*) n=14 ;; esac
  printf '%s' "$n"
}

vt_store_next_id() {
  vt_store_ensure
  local d c n
  d=$(vt_store_dir)
  c=$(cat "$d/.counter")
  n=$((c + 1))
  echo "$n" > "$d/.counter"
  printf 'CAP-%03d\n' "$n"
}

vt_store_item_path() {
  # $1 = CAP-NNN (or path). Active/captured/expired live under items/; cleared under cleared/.
  local id="$1" d
  d=$(vt_store_dir)
  case "$id" in
    */*) printf '%s' "$id" ;;
    *)
      if [ -f "$d/items/$id" ]; then printf '%s' "$d/items/$id"
      elif [ -f "$d/cleared/$id" ]; then printf '%s' "$d/cleared/$id"
      else printf '%s' "$d/items/$id"
      fi
      ;;
  esac
}

vt_store_get() {
  # $1=path $2=key → value
  local path="$1" key="$2"
  [ -f "$path" ] || return 1
  awk -F= -v k="$key" '
    $0 ~ /^#/ { next }
    $0 == "" { next }
    index($0, "=") == 0 { next }
    $1 == k { sub(/^[^=]*=/, ""); print; exit }
  ' "$path"
}

vt_store_set_field() {
  # $1=path $2=key $3=value — rewrite key in place (create file header if missing)
  local path="$1" key="$2" val="$3" tmp
  tmp="${path}.tmp.$$"
  if [ ! -f "$path" ]; then
    printf '%s=%s\n' "$key" "$val" > "$path"
    return 0
  fi
  awk -F= -v k="$key" -v v="$val" '
    BEGIN { done=0 }
    index($0, "=") && $1 == k {
      print k "=" v
      done=1
      next
    }
    { print }
    END { if (!done) print k "=" v }
  ' "$path" > "$tmp" && mv "$tmp" "$path"
}

vt_store_normalize_lever() {
  # $1=raw → prints urgent|today|later; empty/unknown → later (default)
  local raw="${1:-}"
  case "$raw" in
    urgent|today|later) printf '%s' "$raw" ;;
    ''|*) printf 'later' ;;
  esac
}

vt_store_get_lever() {
  # $1=path → lever value; missing field treated as later
  local path="$1" v
  v=$(vt_store_get "$path" lever 2>/dev/null || true)
  vt_store_normalize_lever "$v"
}

vt_store_set_lever() {
  # $1=id $2=lever $3=reason — change priority lever; no board writes
  local id="$1" to="$2" reason="${3:-lever}" path from
  case "$to" in
    urgent|today|later) ;;
    *) echo "error: lever must be urgent|today|later (got '$to')" >&2; return 2 ;;
  esac
  path=$(vt_store_item_path "$id")
  [ -f "$path" ] || { echo "error: store item not found: $id" >&2; return 1; }
  from=$(vt_store_get_lever "$path")
  if [ "$from" = "$to" ]; then
    printf '%s: lever already %s\n' "$id" "$to"
    return 0
  fi
  vt_store_set_field "$path" lever "$to"
  vt_store_log_transition "$id" "lever:$from" "lever:$to" "$reason"
  printf '%s: lever %s → %s\n' "$id" "$from" "$to"
}

vt_store_write_new() {
  # args via env-ish: writes a new captured item. stdin unused.
  # Required: STORE_PROJECT STORE_TITLE; optional STORE_TYPE STORE_WHY STORE_DEADLINE STORE_LEVER
  vt_store_ensure
  local id path ts type why due lever
  id=$(vt_store_next_id)
  path="$(vt_store_dir)/items/$id"
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  type="${STORE_TYPE:-dev}"
  why="${STORE_WHY:-}"
  due="${STORE_DEADLINE:-}"
  lever=$(vt_store_normalize_lever "${STORE_LEVER:-}")
  case "$type" in dev|modeling) ;; *) type=dev ;; esac
  case "$due" in
    ''|[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
    *) echo "warn: ignoring invalid deadline '$due' (want YYYY-MM-DD)." >&2; due="" ;;
  esac
  case "${STORE_LEVER:-}" in
    ''|urgent|today|later) ;;
    *) echo "warn: ignoring invalid lever '${STORE_LEVER}' (want urgent|today|later); defaulting later." >&2 ;;
  esac
  # Sanitize pipes (board-legacy habit) and newlines/tabs in fields
  STORE_PROJECT="${STORE_PROJECT//|/│}"
  STORE_TITLE="${STORE_TITLE//|/│}"
  why="${why//|/│}"
  STORE_PROJECT="${STORE_PROJECT//$'\t'/ }"
  STORE_TITLE="${STORE_TITLE//$'\t'/ }"
  why="${why//$'\t'/ }"
  STORE_PROJECT="${STORE_PROJECT//$'\n'/ }"
  STORE_TITLE="${STORE_TITLE//$'\n'/ }"
  why="${why//$'\n'/ }"

  cat > "$path" <<ITEM
id=$id
project=$STORE_PROJECT
title=$STORE_TITLE
type=$type
why=$why
deadline=$due
lever=$lever
state=captured
captured_at=$ts
activated_at=
expired_at=
cleared_at=
ITEM
  vt_store_log_transition "$id" "-" "captured" "capture lever=$lever"
  printf '%s\n' "$id"
}

vt_store_log_transition() {
  # $1=id $2=from $3=to $4=reason
  vt_store_ensure
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  printf '%s | %s | %s → %s | %s\n' "$ts" "$1" "$2" "$3" "$4" \
    >> "$(vt_store_dir)/transitions.log"
}

vt_store_epoch_utc() {
  # $1=ISO8601 Z → epoch seconds (macOS + GNU)
  local iso="$1"
  if date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$iso" "+%s" 2>/dev/null; then
    return 0
  fi
  date -u -d "$iso" "+%s" 2>/dev/null || date -u -d "${iso%Z}" "+%s"
}

vt_store_age_days() {
  # $1=captured_at ISO → integer age in days
  local cap_ts now age
  cap_ts=$(vt_store_epoch_utc "$1") || return 1
  now=$(date -u +%s)
  age=$(( (now - cap_ts) / 86400 ))
  printf '%s' "$age"
}

vt_store_transition() {
  # $1=id $2=to_state $3=reason — enforces legal edges
  local id="$1" to="$2" reason="${3:-manual}" path from ts
  path=$(vt_store_item_path "$id")
  [ -f "$path" ] || { echo "error: store item not found: $id" >&2; return 1; }
  from=$(vt_store_get "$path" state)
  case "${from}:${to}" in
    captured:active|active:expired|expired:cleared) ;;
    *)
      echo "error: illegal transition ${from} -> ${to} for $id" >&2
      return 1
      ;;
  esac
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  vt_store_set_field "$path" state "$to"
  case "$to" in
    active)  vt_store_set_field "$path" activated_at "$ts" ;;
    expired) vt_store_set_field "$path" expired_at "$ts" ;;
    cleared)
      vt_store_set_field "$path" cleared_at "$ts"
      # Move into cleared/ so list of live items stays small
      mkdir -p "$(vt_store_dir)/cleared"
      mv "$path" "$(vt_store_dir)/cleared/$id"
      path="$(vt_store_dir)/cleared/$id"
      ;;
  esac
  vt_store_log_transition "$id" "$from" "$to" "$reason"
  printf '%s: %s → %s\n' "$id" "$from" "$to"
}
