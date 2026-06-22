#!/usr/bin/env bash
# vt-drift.sh — print the current drift report (surface-only; never mutates).
# Used by /4loops:today, /4loops:week, and standalone inspection (+ vt-close.sh weekly rollover).
set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=./vt-priorities-lib.sh
source "$SCRIPT_DIR/vt-priorities-lib.sh"
# shellcheck source=./vt-drift-lib.sh
source "$SCRIPT_DIR/vt-drift-lib.sh"

drift_report
