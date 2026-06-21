#!/usr/bin/env bash
# vt-next-id.sh <project>
# Generates the next story ID for <project>, e.g. P0 -> P0-001.
# Per-project counter file at $VT_DIR/.ids/<project>.counter.
set -euo pipefail

PROJECT="${1:?usage: vt-next-id <project>}"
VT_DIR="${VT_DIR:-./.4loops}"
mkdir -p "$VT_DIR/.ids"
COUNTER_FILE="$VT_DIR/.ids/${PROJECT}.counter"

if [ ! -f "$COUNTER_FILE" ]; then
  echo "0" > "$COUNTER_FILE"
fi

CURRENT=$(cat "$COUNTER_FILE")
NEXT=$((CURRENT + 1))
echo "$NEXT" > "$COUNTER_FILE"
printf "%s-%03d\n" "$PROJECT" "$NEXT"
