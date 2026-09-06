#!/usr/bin/env bash
# vt-store-capture.sh [--dry-run] [--lever LEVER] — batch-capture into detached store.
#
# Each stdin line: PROJECT<TAB>TITLE<TAB>TYPE<TAB>WHY<TAB>DUE_OR_LEVER<TAB>LEVER
#   TYPE/WHY/DUE/LEVER optional. LEVER = urgent|today|later (default later).
#
# Field 5 ambiguity (bash collapses empty tab fields):
#   - YYYY-MM-DD → deadline; optional field 6 = lever
#   - urgent|today|later → lever with empty deadline
#   - other/empty → deadline blank; lever from --lever or later
#
# Batch default: --lever urgent|today|later (overridden per-line when line sets lever).
# Writes CAP-NNN with state=captured + lever=. Does NOT touch board.md.
#
# v2.5 Track A+C
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=./vt-store-lib.sh
source "$SCRIPT_DIR/vt-store-lib.sh"

VT_DIR="${VT_DIR:-./.4loops}"
"$SCRIPT_DIR/vt-init.sh" >/dev/null
vt_store_ensure

DRY=0
BATCH_LEVER=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    --lever)
      BATCH_LEVER="${2:?--lever needs urgent|today|later}"
      case "$BATCH_LEVER" in urgent|today|later) ;; *)
        echo "error: --lever must be urgent|today|later (got '$BATCH_LEVER')" >&2
        exit 2
      ;; esac
      shift 2
      ;;
    -h|--help)
      sed -n '2,18p' "$0" | sed 's/^# //;s/^#//'
      exit 0
      ;;
    *)
      echo "unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

created=0
while IFS=$'\t' read -r proj title type why f5 f6 || [ -n "${proj:-}" ]; do
  [ -z "${proj:-}" ] && continue
  title="${title:-}"; type="${type:-dev}"; why="${why:-}"; f5="${f5:-}"; f6="${f6:-}"
  [ -z "$title" ] && continue
  case "$type" in dev|modeling) ;; *) type=dev ;; esac

  due=""
  lever="$BATCH_LEVER"
  case "$f5" in
    urgent|today|later)
      lever="$f5"
      ;;
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
      due="$f5"
      case "$f6" in
        urgent|today|later) lever="$f6" ;;
        '') ;;
        *)
          echo "warn: ignoring invalid lever '$f6' (want urgent|today|later)." >&2
          ;;
      esac
      ;;
    '')
      case "$f6" in
        urgent|today|later) lever="$f6" ;;
        '') ;;
        *)
          echo "warn: ignoring invalid field6 '$f6'." >&2
          ;;
      esac
      ;;
    *)
      # treat as malformed due; drop with warn (legacy behavior)
      echo "warn: ignoring invalid deadline '$f5' (want YYYY-MM-DD or lever keyword)." >&2
      case "$f6" in
        urgent|today|later) lever="$f6" ;;
      esac
      ;;
  esac

  norm=$(vt_store_normalize_lever "$lever")
  if [ "$DRY" = 1 ]; then
    printf -- '- [%s] %s  (type: %s%s, lever: %s)%s  → store:captured\n' \
      "$proj" "$title" "$type" "${due:+, due $due}" "$norm" "${why:+ — why: $why}"
    continue
  fi
  STORE_PROJECT="$proj"
  STORE_TITLE="$title"
  STORE_TYPE="$type"
  STORE_WHY="$why"
  STORE_DEADLINE="$due"
  STORE_LEVER="$lever"
  id=$(vt_store_write_new)
  printf 'captured: %s [%s] %s  lever=%s\n' "$id" "$proj" "$title" "$norm"
  created=$((created + 1))
done

if [ "$DRY" = 0 ]; then
  echo "store: captured ${created} item(s) into $(vt_store_dir)/items (off-board). Prioritize levers later — not board Backlog."
fi
