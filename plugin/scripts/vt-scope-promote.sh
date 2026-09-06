#!/usr/bin/env bash
# vt-scope-promote.sh — promote an active store CAP → ephemeral scope doc.
#
#   vt-scope-promote.sh <CAP-ID> --deadline YYYY-MM-DD --impact TEXT --resource TEXT
#   vt-scope-promote.sh <CAP-ID> --deadline … --impact … --resource … --force
#
# Writes $VT_DIR/tasks/<PROJECT>/<CAP-ID>.md with capacity fields only.
# Does NOT touch board.md. Requires store item state=active.
# Marks store item scoped_at + scope_doc (state stays active).
#
# v2.5 Track B · Scope
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=./vt-store-lib.sh
source "$SCRIPT_DIR/vt-store-lib.sh"
# shellcheck source=./vt-scope-lib.sh
SCRIPT_DIR_SCOPE="$SCRIPT_DIR"
source "$SCRIPT_DIR/vt-scope-lib.sh"

VT_DIR="${VT_DIR:-./.4loops}"
"$SCRIPT_DIR/vt-init.sh" >/dev/null
vt_store_ensure
vt_scope_ensure

usage() {
  sed -n '2,14p' "$0" | sed 's/^# //;s/^#//'
  exit 2
}

ID=""
DEADLINE=""
IMPACT=""
RESOURCE=""
FORCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --deadline) DEADLINE="${2:?}"; shift 2 ;;
    --impact)   IMPACT="${2:?}"; shift 2 ;;
    --resource) RESOURCE="${2:?}"; shift 2 ;;
    --force)    FORCE=1; shift ;;
    -h|--help)  usage ;;
    -*)
      echo "unknown arg: $1" >&2
      usage
      ;;
    *)
      if [ -z "$ID" ]; then ID="$1"; shift
      else echo "unexpected arg: $1" >&2; usage
      fi
      ;;
  esac
done

[ -n "$ID" ] || { echo "error: CAP-ID required" >&2; usage; }
[ -n "$DEADLINE" ] && [ -n "$IMPACT" ] && [ -n "$RESOURCE" ] || {
  echo "error: --deadline, --impact, and --resource are all required (capacity judgment)" >&2
  exit 2
}

case "$DEADLINE" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
  *) echo "error: --deadline must be YYYY-MM-DD (got '$DEADLINE')" >&2; exit 2 ;;
esac

# Refuse modeling-looking payloads in capacity fields
for label_val in "impact:$IMPACT" "resource:$RESOURCE"; do
  label="${label_val%%:*}"
  val="${label_val#*:}"
  case "$val" in
    *[Mm]odel*|*[Ii]mplementation\ plan*|*[Aa]rchitecture*|*[Dd]esign\ doc*)
      echo "error: $label looks like modeling — scope docs are capacity judgment only (deadline·impact·resource)" >&2
      exit 2
      ;;
  esac
done

path=$(vt_store_item_path "$ID")
[ -f "$path" ] || { echo "error: store item not found: $ID" >&2; exit 1; }

st=$(vt_store_get "$path" state)
if [ "$st" != "active" ]; then
  echo "error: refuse promote — $ID state=$st (need active). Activate first: vt-store-expire.sh --activate $ID" >&2
  exit 1
fi

proj=$(vt_store_get "$path" project)
title=$(vt_store_get "$path" title)
type=$(vt_store_get "$path" type)
why=$(vt_store_get "$path" why)
# Prefer store deadline if promote omitted? No — flags are required; but if
# store has deadline and user passed same, fine. Optionally fill from store
# when user wants — already required on CLI.

existing=""
existing=$(vt_scope_find "$ID" 2>/dev/null || true)
if [ -n "$existing" ] && [ "$FORCE" != 1 ]; then
  echo "error: scope doc already exists: $existing (pass --force to overwrite)" >&2
  exit 1
fi

# Also refuse if store already has scoped_at without --force
scoped_at=$(vt_store_get "$path" scoped_at 2>/dev/null || true)
if [ -n "${scoped_at:-}" ] && [ "$FORCE" != 1 ]; then
  echo "error: $ID already promoted (scoped_at=$scoped_at). Pass --force to re-promote." >&2
  exit 1
fi

IMPACT=$(vt_scope_sanitize "$IMPACT")
RESOURCE=$(vt_scope_sanitize "$RESOURCE")
title=$(vt_scope_sanitize "$title")
why=$(vt_scope_sanitize "$why")

SCOPE_ID="$ID"
SCOPE_PROJECT="$proj"
SCOPE_TITLE="$title"
SCOPE_DEADLINE="$DEADLINE"
SCOPE_IMPACT="$IMPACT"
SCOPE_RESOURCE="$RESOURCE"
SCOPE_WHY="$why"
SCOPE_TYPE="${type:-dev}"

doc_path=$(vt_scope_write_doc)
ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Annotate store item (state remains active — Scope does not advance expiry SM)
vt_store_set_field "$path" scoped_at "$ts"
vt_store_set_field "$path" scope_doc "$doc_path"

from="active"
to="scoped-doc"
[ -n "$existing" ] && from="scoped-doc"
vt_scope_log_transition "$ID" "$from" "$to" "promote"

# Relative display path
rel="${doc_path#"$VT_DIR"/}"
printf 'promoted: %s → %s\n' "$ID" "$rel"
printf 'capacity: deadline=%s | impact=%s | resource=%s\n' "$DEADLINE" "$IMPACT" "$RESOURCE"
printf 'board: unchanged (Scope writes tasks/ only)\n'
