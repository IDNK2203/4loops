#!/usr/bin/env bash
# vt-priorities-print.sh — print current-priorities.md (surface-only; never mutates).
# The read-only half of the orientation rails: /4loops:priorities shows the same
# today + week checkboxes an operator sees in `vt-week.sh --orient`, without
# running the ritual, setting anything, or clearing the orientation gate.
# v2.5 Packet 012 (Views)
set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=./vt-priorities-lib.sh
source "$SCRIPT_DIR/vt-priorities-lib.sh"

print_priorities
