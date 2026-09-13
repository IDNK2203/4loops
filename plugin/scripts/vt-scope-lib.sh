#!/usr/bin/env bash
# vt-scope-lib.sh — ephemeral scope-doc helpers (v2.5 Track B · Scope).
#
# Scope docs live at $VT_DIR/tasks/<PROJECT-KEY>/<CAP-ID>.md
# Capacity judgment only: deadline · impact · resource. No modeling.
# Source this file; do not invoke it directly.
#
# UNSURFACED (v2.5 Packet 009b): Track B is dead and the `/scope` skill was
# removed, so nothing in the product routes here. The rail still works and
# still carries its bash-gate tier; it is a bare power-user hatch, reachable
# only from a session that already holds a capability from another
# /4loops:* command. Scope docs under .4loops/tasks/ still never expire —
# delete them by hand.
#
# Promote reads an *active* store item and writes a scope doc. Does NOT
# touch board.md. Store item stays active; scoped_at + scope_doc are set.

# shellcheck source=./vt-store-lib.sh
SCRIPT_DIR_SCOPE="${SCRIPT_DIR_SCOPE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# Prefer caller-sourced store lib; otherwise load sibling.
if ! declare -F vt_store_dir >/dev/null 2>&1; then
  # shellcheck source=./vt-store-lib.sh
  source "$SCRIPT_DIR_SCOPE/vt-store-lib.sh"
fi

vt_tasks_dir() {
  printf '%s' "${VT_DIR:-./.4loops}/tasks"
}

vt_scope_ensure() {
  mkdir -p "$(vt_tasks_dir)"
  local d
  d=$(vt_tasks_dir)
  [ -f "$d/transitions.log" ] || : > "$d/transitions.log"
}

vt_scope_doc_path() {
  # $1=project key  $2=CAP-ID
  local proj="$1" id="$2"
  printf '%s/%s/%s.md' "$(vt_tasks_dir)" "$proj" "$id"
}

vt_scope_find() {
  # $1=CAP-ID → path if exists under any project, else empty
  local id="$1" d f
  d=$(vt_tasks_dir)
  [ -d "$d" ] || return 1
  shopt -s nullglob
  for f in "$d"/*/"$id".md; do
    printf '%s' "$f"
    return 0
  done
  return 1
}

vt_scope_get() {
  # $1=path $2=key — read key=value from header (before first blank or # heading)
  local path="$1" key="$2"
  [ -f "$path" ] || return 1
  awk -F= -v k="$key" '
    NR==1 && $0 ~ /^---$/ { fm=1; next }
    fm && $0 ~ /^---$/ { exit }
    fm {
      if (index($0, ":")) {
        split($0, a, /:[[:space:]]*/)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", a[1])
        if (a[1] == k) { sub(/^[^:]*:[[:space:]]*/, ""); print; exit }
      }
      next
    }
    $0 ~ /^#/ { exit }
    $0 == "" { if (seen) exit; next }
    index($0, "=") == 0 { next }
    $1 == k { sub(/^[^=]*=/, ""); print; exit }
    { seen=1 }
  ' "$path"
}

vt_scope_log_transition() {
  # $1=id $2=from $3=to $4=reason
  vt_scope_ensure
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  printf '%s | %s | %s → %s | %s\n' "$ts" "$1" "$2" "$3" "$4" \
    >> "$(vt_tasks_dir)/transitions.log"
}

vt_scope_sanitize() {
  # strip tabs/newlines/pipes from a field
  local s="$1"
  s="${s//|/│}"
  s="${s//$'\t'/ }"
  s="${s//$'\n'/ }"
  printf '%s' "$s"
}

vt_scope_write_doc() {
  # Env: SCOPE_ID SCOPE_PROJECT SCOPE_TITLE SCOPE_DEADLINE SCOPE_IMPACT SCOPE_RESOURCE
  # Optional: SCOPE_WHY SCOPE_TYPE
  # Writes markdown with YAML frontmatter — capacity fields only.
  vt_scope_ensure
  local proj id path why type
  id="$SCOPE_ID"
  proj="$SCOPE_PROJECT"
  path=$(vt_scope_doc_path "$proj" "$id")
  mkdir -p "$(dirname "$path")"
  why="${SCOPE_WHY:-}"
  type="${SCOPE_TYPE:-dev}"
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  cat > "$path" <<DOC
---
id: $id
project: $proj
title: $SCOPE_TITLE
type: $type
source_store_id: $id
deadline: $SCOPE_DEADLINE
impact: $SCOPE_IMPACT
resource: $SCOPE_RESOURCE
why: $why
promoted_at: $ts
state: scoped
---

# $SCOPE_TITLE

Capacity judgment only (deadline · impact · resource). Not a design or build plan.

| Field | Value |
| --- | --- |
| **deadline** | $SCOPE_DEADLINE |
| **impact** | $SCOPE_IMPACT |
| **resource** | $SCOPE_RESOURCE |

$(if [ -n "$why" ]; then printf '## Why\n\n%s\n' "$why"; fi)

---
*Handoff artifact for build rails. Expires on Done (Track D). Source store item: \`$id\`.*
DOC
  printf '%s\n' "$path"
}
