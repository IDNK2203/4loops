#!/usr/bin/env bash
# vt-key.sh rename <old-key> <new-key> [--dry-run]
# vt-key.sh list
#
# Key lifecycle (v2.5 Track D · P0-049). A project key is the prefix on every story
# ID it owns (WEB → WEB-001), so renaming one is a workspace-wide rewrite, not a
# board edit: the Projects table row, every board cell, the ID counter, the store
# items, the priorities file, and every log + archive record move together.
#
# Abandoning a key is `vt-transition.sh <id> abandoned` per story — that trail
# already exists and is unchanged.
#
# Refuses if <new-key> is already in use (IDs would collide). --dry-run prints
# exactly what would be rewritten and touches nothing.
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=./vt-priorities-lib.sh
source "$SCRIPT_DIR/vt-priorities-lib.sh"
# shellcheck source=./vt-board-lib.sh
source "$SCRIPT_DIR/vt-board-lib.sh"

CMD="${1:-}"; shift || true

# Every project key seen in the Projects table.
_keys() {
  [ -f "$BOARD" ] || return 0
  awk -F'|' '
    /^## Projects$/ { inp = 1; next }
    inp && /^\| -+/ { body = 1; next }
    body && /^\|/ { k = $2; gsub(/^ +| +$/, "", k); if (k != "") print k; next }
    body && /^$/ { exit }
  ' "$BOARD"
}

case "$CMD" in
  list)
    _keys
    exit 0
    ;;
  rename) ;;
  *) echo "usage: vt-key.sh rename <old-key> <new-key> [--dry-run] | vt-key.sh list" >&2; exit 1 ;;
esac

OLD=""; NEW=""; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    *) if [ -z "$OLD" ]; then OLD="$1"; elif [ -z "$NEW" ]; then NEW="$1"; fi; shift ;;
  esac
done
[ -n "$OLD" ] && [ -n "$NEW" ] || { echo "usage: vt-key.sh rename <old-key> <new-key> [--dry-run]" >&2; exit 1; }
[ "$OLD" != "$NEW" ] || { echo "vt-key: old and new key are the same." >&2; exit 0; }
case "$NEW" in
  *[!A-Za-z0-9]*|'') echo "vt-key: a key must be alphanumeric (got '$NEW')." >&2; exit 1 ;;
esac
[ -f "$BOARD" ] || { echo "No board yet — run /4loops:configure first." >&2; exit 1; }

KEYS=$(_keys)
case $'\n'"$KEYS"$'\n' in
  *$'\n'"$OLD"$'\n'*) ;;
  *) echo "vt-key: no project '$OLD' in the Projects table. Known keys: $(printf '%s' "$KEYS" | paste -sd ' ' -)" >&2; exit 1 ;;
esac
case $'\n'"$KEYS"$'\n' in
  *$'\n'"$NEW"$'\n'*) echo "vt-key: '$NEW' is already a project — IDs would collide. Rename it first, or merge the stories." >&2; exit 1 ;;
esac
[ -f "$VT_DIR/.ids/${NEW}.counter" ] && { echo "vt-key: an ID counter for '$NEW' already exists — IDs would collide." >&2; exit 1; }

# Files that can carry the key or its IDs. Archive + logs are rewritten too, so
# the trail stays followable after the rename (append-only still holds — nothing
# is deleted, the rows are re-labelled).
FILES=("$BOARD")
for f in "$VT_DIR/current-priorities.md" "$VT_DIR/transitions.log" "$VT_DIR/priorities.log"; do
  [ -f "$f" ] && FILES+=("$f")
done
while IFS= read -r f; do [ -n "$f" ] && FILES+=("$f"); done < <(
  find "$VT_DIR/archive" "$VT_DIR/store" "$VT_DIR/tasks" -type f 2>/dev/null | sort)

N=$(grep -c -- "\*\*${OLD}-" "$BOARD" 2>/dev/null || true)
if [ "$DRY" = 1 ]; then
  echo "vt-key rename (dry-run): ${OLD} → ${NEW}"
  echo "  board rows carrying ${OLD}-NNN: ${N}"
  echo "  files that would be rewritten:"
  for f in "${FILES[@]}"; do
    c=$(grep -c -E "(\[${OLD}\]|(^|[^A-Za-z0-9])${OLD}-[0-9]|^project=${OLD}$)" "$f" 2>/dev/null || true)
    [ "${c:-0}" -gt 0 ] && printf '    %s (%s line(s))\n' "${f#"$VT_DIR"/}" "$c"
  done
  [ -f "$VT_DIR/.ids/${OLD}.counter" ] && echo "    .ids/${OLD}.counter → .ids/${NEW}.counter"
  exit 0
fi

for f in "${FILES[@]}"; do
  # `[OLD]` project tag, `OLD-NNN` IDs, and the store's `project: OLD` field.
  # The ID rewrite guards its left edge with (^|[^A-Za-z0-9]) rather than \b —
  # BSD sed has no \b, and an unguarded match would also hit e.g. SUBWEB-001.
  sed -i.bak -E "s/\[${OLD}\]/[${NEW}]/g; s/(^|[^A-Za-z0-9])${OLD}-([0-9])/\1${NEW}-\2/g; s/^project=${OLD}\$/project=${NEW}/" "$f"
  rm -f "${f}.bak"
done
# The Projects-table key cell itself (first column) — not covered by the tag rewrite.
sed -i.bak -E "s/^\| ${OLD} \|/| ${NEW} |/" "$BOARD"; rm -f "${BOARD}.bak"
[ -f "$VT_DIR/.ids/${OLD}.counter" ] && mv "$VT_DIR/.ids/${OLD}.counter" "$VT_DIR/.ids/${NEW}.counter"

"$SCRIPT_DIR/vt-refresh-counts.sh"
printf '%s\t%s\t%s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$NEW" "key-renamed from:${OLD}" \
  >> "$VT_DIR/transitions.log"

echo "key: ${OLD} → ${NEW} (${N} board row(s) re-labelled; ID counter carried over)"
echo "  the trail moved with it — archive + logs now read ${NEW}-NNN."
