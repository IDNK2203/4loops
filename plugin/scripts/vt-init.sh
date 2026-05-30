#!/usr/bin/env bash
# vt-init.sh — initialize .vibe-table/ in workspace root (cwd).
# Idempotent: safe to call any number of times.
set -euo pipefail

VT_DIR="${VT_DIR:-./.vibe-table}"

mkdir -p "$VT_DIR/.ids" "$VT_DIR/archive" "$VT_DIR/.cleared"
touch "$VT_DIR/transitions.log"

if [ ! -f "$VT_DIR/board.md" ]; then
  cat > "$VT_DIR/board.md" <<'EOF'
# Vibe Table

**Counts:** Backlog 0 · Planning 0 · In Progress 0 · Testing 0 · Done 0

## Projects

| Key | Project | Repo |
| --- | ------- | ---- |

---

| Backlog | Planning | In Progress | Testing | Done |
| ------- | -------- | ----------- | ------- | ---- |
EOF
fi

echo "$VT_DIR"
