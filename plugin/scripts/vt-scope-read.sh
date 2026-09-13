#!/usr/bin/env bash
# vt-scope-read.sh <CAP-ID|path> — print a scope doc (read-only).
#
# UNSURFACED (v2.5 Packet 009b): Track B is dead and the `/scope` skill was
# removed, so nothing in the product routes here. The rail still works and
# still carries its bash-gate tier; it is a bare power-user hatch, reachable
# only from a session that already holds a capability from another
# /4loops:* command. Scope docs under .4loops/tasks/ still never expire —
# delete them by hand.
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=./vt-store-lib.sh
source "$SCRIPT_DIR/vt-store-lib.sh"
SCRIPT_DIR_SCOPE="$SCRIPT_DIR"
# shellcheck source=./vt-scope-lib.sh
source "$SCRIPT_DIR/vt-scope-lib.sh"

VT_DIR="${VT_DIR:-./.4loops}"
TARGET="${1:?usage: vt-scope-read.sh <CAP-ID|path>}"

if [ -f "$TARGET" ]; then
  path="$TARGET"
else
  path=$(vt_scope_find "$TARGET" || true)
  [ -n "${path:-}" ] || { echo "error: scope doc not found: $TARGET" >&2; exit 1; }
fi

cat "$path"
