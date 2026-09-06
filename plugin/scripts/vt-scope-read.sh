#!/usr/bin/env bash
# vt-scope-read.sh <CAP-ID|path> — print a scope doc (read-only).
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
