#!/usr/bin/env bash
# vt-arrange.sh [--dry-run] — batch-draft stories from TSV on stdin (W6 helper).
#
# Each stdin line: PROJECT<TAB>TITLE<TAB>TYPE<TAB>WHY   (TYPE + WHY optional).
# Used by /4loops:arrange AFTER the user confirms the proposed stories — it never
# decides WHAT to create or HOW to prioritize; it just executes a user-confirmed
# batch atomically (every item lands in Backlog, the operator sets focus after).
# --dry-run prints the planned drafts without creating anything (the proposal).
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

created=0
while IFS=$'\t' read -r proj title type why || [ -n "${proj:-}" ]; do
  [ -z "${proj:-}" ] && continue
  title="${title:-}"; type="${type:-dev}"; why="${why:-}"
  [ -z "$title" ] && continue
  case "$type" in dev|modeling) ;; *) type=dev ;; esac
  if [ "$DRY" = 1 ]; then
    printf -- '- [%s] %s  (type: %s)%s\n' "$proj" "$title" "$type" "${why:+ — why: $why}"
    continue
  fi
  args=("$proj" "$title")
  [ -n "$why" ] && args+=("$why")
  args+=(--type "$type")
  "$SCRIPT_DIR/vt-draft.sh" "${args[@]}" >/dev/null
  created=$((created + 1))
done

if [ "$DRY" = 0 ]; then
  echo "arranged: drafted ${created} story(ies) into Backlog — set focus with /4loops:today or /4loops:priority."
fi
