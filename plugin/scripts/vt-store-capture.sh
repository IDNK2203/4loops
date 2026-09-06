#!/usr/bin/env bash
# vt-store-capture.sh [--dry-run] — batch-capture into the detached backlog store.
#
# Each stdin line: PROJECT<TAB>TITLE<TAB>TYPE<TAB>WHY<TAB>DUE  (TYPE/WHY/DUE optional).
# Writes to .4loops/store/items/CAP-NNN with state=captured. Does NOT touch board.md.
# --dry-run prints the planned captures without writing.
#
# v2.5 Track A: this is the capture path. Board Backlog is no longer the write
# target for /capture (vt-arrange/vt-draft remain for intentional board drafts).
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=./vt-store-lib.sh
source "$SCRIPT_DIR/vt-store-lib.sh"

VT_DIR="${VT_DIR:-./.4loops}"
"$SCRIPT_DIR/vt-init.sh" >/dev/null
vt_store_ensure

DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

created=0
while IFS=$'\t' read -r proj title type why due || [ -n "${proj:-}" ]; do
  [ -z "${proj:-}" ] && continue
  title="${title:-}"; type="${type:-dev}"; why="${why:-}"; due="${due:-}"
  [ -z "$title" ] && continue
  case "$type" in dev|modeling) ;; *) type=dev ;; esac
  if [ "$DRY" = 1 ]; then
    printf -- '- [%s] %s  (type: %s%s)%s  → store:captured\n' \
      "$proj" "$title" "$type" "${due:+, due $due}" "${why:+ — why: $why}"
    continue
  fi
  STORE_PROJECT="$proj"
  STORE_TITLE="$title"
  STORE_TYPE="$type"
  STORE_WHY="$why"
  STORE_DEADLINE="$due"
  id=$(vt_store_write_new)
  printf 'captured: %s [%s] %s\n' "$id" "$proj" "$title"
  created=$((created + 1))
done

if [ "$DRY" = 0 ]; then
  echo "store: captured ${created} item(s) into $(vt_store_dir)/items (off-board). Promote via Scope/Prioritize later — not board Backlog."
fi
