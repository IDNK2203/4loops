#!/usr/bin/env bash
# vt-init.sh — initialize .4loops/ in workspace root (cwd).
# Idempotent: safe to call any number of times.
set -euo pipefail

VT_DIR="${VT_DIR:-./.4loops}"

mkdir -p "$VT_DIR/.ids" "$VT_DIR/archive" "$VT_DIR/.cleared" \
  "$VT_DIR/store/items" "$VT_DIR/store/cleared" \
  "$VT_DIR/tasks"
touch "$VT_DIR/store/transitions.log" 2>/dev/null || true
[ -f "$VT_DIR/store/.counter" ] || echo "0" > "$VT_DIR/store/.counter"
touch "$VT_DIR/tasks/transitions.log" 2>/dev/null || true
touch "$VT_DIR/transitions.log"

if [ ! -f "$VT_DIR/board.md" ]; then
  cat > "$VT_DIR/board.md" <<'EOF'
# 4loops

**Counts:** Planning 0 · In Progress 0 · Testing 0 · Done 0

## Projects

| Key | Project | Repo |
| --- | ------- | ---- |

---

| Planning | In Progress | Testing | Done |
| -------- | ----------- | ------- | ---- |
EOF
fi

echo "$VT_DIR"
