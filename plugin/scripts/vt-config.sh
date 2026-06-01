#!/usr/bin/env bash
# vt-config.sh — write .vibe-table/config keys + register projects in board.md.
# Centralizes every config mutation /configure performs.
#
# Subcommands:
#   vt-config.sh week-start <mon|sun>           Set the first day of the week.
#   vt-config.sh gated <glob> [<glob> ...]      REPLACE all gated: lines (the
#                                               built-in default no longer applies
#                                               once any gated: line exists).
#   vt-config.sh project <key> <name> [repo]    Upsert a Projects-table row.
#   vt-config.sh show                           Print the config file.
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
VT_DIR="${VT_DIR:-./.vibe-table}"
CONFIG="$VT_DIR/config"
BOARD="$VT_DIR/board.md"
"$SCRIPT_DIR/vt-init.sh" >/dev/null

# Upsert a single-value key: drop existing lines for that key, append the new one.
_set_key() {
  local key="$1" val="$2" tmp="${CONFIG}.tmp"
  touch "$CONFIG"
  grep -v "^${key}:" "$CONFIG" > "$tmp" 2>/dev/null || true
  printf '%s: %s\n' "$key" "$val" >> "$tmp"
  mv "$tmp" "$CONFIG"
}

cmd="${1:?usage: vt-config.sh <week-start|gated|project|show> ...}"; shift || true
case "$cmd" in
  week-start)
    ws="${1:?usage: vt-config.sh week-start <mon|sun>}"
    case "$ws" in
      mon|monday) ws=mon ;;
      sun|sunday) ws=sun ;;
      *) echo "week-start must be mon|sun" >&2; exit 1 ;;
    esac
    _set_key "week-start" "$ws"
    echo "week-start: $ws"
    ;;

  gated)
    [ "$#" -ge 1 ] || { echo "usage: vt-config.sh gated <glob> [<glob> ...]" >&2; exit 1; }
    tmp="${CONFIG}.tmp"
    touch "$CONFIG"
    grep -v "^gated:" "$CONFIG" > "$tmp" 2>/dev/null || true
    for g in "$@"; do printf 'gated: %s\n' "$g" >> "$tmp"; done
    mv "$tmp" "$CONFIG"
    printf 'gated:\n'; for g in "$@"; do printf '  %s\n' "$g"; done
    ;;

  project)
    key="${1:?usage: vt-config.sh project <key> <name> [repo]}"
    name="${2:?usage: vt-config.sh project <key> <name> [repo]}"
    repo="${3:-—}"
    key="${key//|/\\|}"; name="${name//|/\\|}"; repo="${repo//|/\\|}"
    # Upsert a row in the Projects table: replace the row whose key matches, else
    # insert just before the table's trailing blank line.
    awk -v key="$key" -v name="$name" -v repo="$repo" '
      BEGIN { done=0 }
      /^## Projects$/ { inp=1; print; next }
      inp && /^\| -+/ { inbody=1; print; next }
      inbody && /^\|/ {
        k=$0; sub(/^\| */,"",k); sub(/ *\|.*/,"",k)
        if (k==key) { printf "| %s | %s | %s |\n", key, name, repo; done=1; next }
        print; next
      }
      inbody && /^$/ {
        if (!done) { printf "| %s | %s | %s |\n", key, name, repo; done=1 }
        inbody=0; inp=0; print; next
      }
      { print }
    ' "$BOARD" > "${BOARD}.tmp" && mv "${BOARD}.tmp" "$BOARD"
    echo "project: $key ($name)"
    ;;

  show)
    [ -f "$CONFIG" ] && cat "$CONFIG" || echo "(no config)"
    ;;

  *) echo "unknown subcommand: $cmd" >&2; exit 1 ;;
esac
