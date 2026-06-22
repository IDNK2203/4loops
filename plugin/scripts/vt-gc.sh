#!/usr/bin/env bash
# vt-gc.sh — garbage-collect replicating marker files to "latest only" (W5).
# Prunes dead idempotency markers (.weekly-rolled-* / .prompt-nudged-* / stale
# .cleared/*) that otherwise accumulate one-per-period forever. Runs automatically
# from the SessionStart sentinel; also invocable by hand. Fail-open.
set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
VT_DIR="${VT_DIR:-./.4loops}"
# shellcheck source=./vt-priorities-lib.sh
source "$SCRIPT_DIR/vt-priorities-lib.sh" 2>/dev/null || exit 0
# shellcheck source=./vt-guard-lib.sh
source "$SCRIPT_DIR/vt-guard-lib.sh" 2>/dev/null || exit 0

[ -d "$VT_DIR" ] || exit 0
vt_gc_markers
echo "gc: pruned stale markers in ${VT_DIR}"
