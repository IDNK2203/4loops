#!/usr/bin/env bash
# sandbox.sh — disposable clean-room workspaces to dogfood vibe-table as a fresh user.
#
# Two modes (config fidelity × persistence) and two install paths — see sandbox/README.md.
#   --light     ephemeral /tmp + real config (--plugin-dir). Fast inner loop.
#   --isolated  persistent ~/Ship/vt-sandbox + hermetic. The true fresh-user env. (default)
#     · settings injection (default): claude --bare --settings … (no cache/version machinery)
#     · --real-install: genuine marketplace add + install via $HOME override (tests install-UX + B4)
#
# Each sandbox carries a mock project tree whose gated paths match vt's real default
# globs, so the rail (B1) has real targets. Seeding drives the REAL vt CLI.
set -euo pipefail

# ── Paths ─────────────────────────────────────────────────────────────────────
SANDBOX_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO="$( cd "$SANDBOX_DIR/.." && pwd )"
PLUGIN_DIR="$REPO/plugin"
PLUGIN_SCRIPTS="$PLUGIN_DIR/scripts"
TMP_BASE="/tmp"
PERSIST_BASE="$HOME/Ship/vt-sandbox"
MARKETPLACE="bls-vibe-table"   # must match .claude-plugin/marketplace.json "name"

# ── Defaults (set by parse_new_args) ────────────────────────────────────────────
MODE=isolated
INSTALL=inject     # inject | real | "" (light)
EMPTY=false
NAME=""

die() { printf 'sandbox: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
sandbox.sh — clean-room workspaces for dogfooding vibe-table

USAGE
  sandbox.sh new [--light|--isolated] [--real-install] [--empty|--seeded] [name]
  sandbox.sh refresh <name>      reset the board to seed (keeps the workspace)
  sandbox.sh list                show all sandboxes
  sandbox.sh rm <name>           delete a sandbox

MODES
  --isolated   (default) persistent ~/Ship/vt-sandbox/<name>, hermetic. True fresh-user env.
  --light      ephemeral /tmp/vt-sandbox-<name>, real config (--plugin-dir). Fast iteration.

INSTALL (isolated only)
  (default)        settings injection — claude --bare --settings. Tests runtime B1/B2/B3/B5.
  --real-install   real marketplace add+install via $HOME override. Tests install-UX + B4.

SEED
  --seeded     (default) stories across states + pre-armed rail + stale focus (B1 demoable now)
  --empty      virgin workspace (no board) — walk /vt:draft → /vt:today from scratch
EOF
}

# ── Sandbox location + discovery ─────────────────────────────────────────────────
sandbox_root() {  # <mode> <name>
  case "$1" in
    light)    printf '%s/vt-sandbox-%s' "$TMP_BASE" "$2" ;;
    isolated) printf '%s/%s' "$PERSIST_BASE" "$2" ;;
  esac
}

find_sandbox() {  # <name> → echo root, or return 1
  [ -d "$PERSIST_BASE/$1" ]        && { printf '%s' "$PERSIST_BASE/$1"; return 0; }
  [ -d "$TMP_BASE/vt-sandbox-$1" ] && { printf '%s' "$TMP_BASE/vt-sandbox-$1"; return 0; }
  return 1
}

# ── Builders ──────────────────────────────────────────────────────────────────
scaffold_mock() {  # <workspace> — mock tree; gated paths match vt_gated_globs defaults
  local ws="$1"
  mkdir -p "$ws/projects/acme-demo/content" \
           "$ws/projects/acme-demo/repo-scaffolding" \
           "$ws/projects/acme-demo/gists" \
           "$ws/projects/acme-demo/src" \
           "$ws/study"
  printf '# Launch post (GATED)\nEditing this while focus is stale must be DENIED by the rail (B1).\n' \
    > "$ws/projects/acme-demo/content/post.md"
  printf '# acme-demo (GATED) — repo scaffolding\n' \
    > "$ws/projects/acme-demo/repo-scaffolding/README.md"
  printf '// GATED — embeddable snippet\nconsole.log("vibe");\n' \
    > "$ws/projects/acme-demo/gists/snippet.js"
  printf '// NOT gated — editing this is always allowed\n' \
    > "$ws/projects/acme-demo/src/app.js"
  printf '# Study notes — exempt research surface, writable even gate-up\n' \
    > "$ws/study/notes.md"
}

seed_board() {  # <vt_dir> — drive the REAL vt CLI so seeding exercises it too
  local vtdir="$1"
  VT_DIR="$vtdir" bash "$PLUGIN_SCRIPTS/vt-draft.sh" DEMO "Wire up the landing page" "build" "projects/acme-demo/content/" >/dev/null
  VT_DIR="$vtdir" bash "$PLUGIN_SCRIPTS/vt-draft.sh" DEMO "Draft launch thread"      "share" >/dev/null
  VT_DIR="$vtdir" bash "$PLUGIN_SCRIPTS/vt-draft.sh" DEMO "Set up CI"                "build" >/dev/null
  VT_DIR="$vtdir" bash "$PLUGIN_SCRIPTS/vt-draft.sh" DEMO "Write API docs"           "build" >/dev/null
  VT_DIR="$vtdir" bash "$PLUGIN_SCRIPTS/vt-draft.sh" DEMO "Ship v0.1"                "build" >/dev/null
  VT_DIR="$vtdir" bash "$PLUGIN_SCRIPTS/vt-transition.sh" DEMO-002 planning    >/dev/null
  VT_DIR="$vtdir" bash "$PLUGIN_SCRIPTS/vt-transition.sh" DEMO-003 in-progress >/dev/null
  VT_DIR="$vtdir" bash "$PLUGIN_SCRIPTS/vt-transition.sh" DEMO-004 testing     >/dev/null
  VT_DIR="$vtdir" bash "$PLUGIN_SCRIPTS/vt-transition.sh" DEMO-005 done        >/dev/null
  : > "$vtdir/.armed"   # pre-arm: armed + stale focus = gate active, so B1 is demoable immediately
}

write_settings() {  # <config-dir> — injection settings (directory-source marketplace)
  local cfg="$1"
  mkdir -p "$cfg"
  cat > "$cfg/sandbox-settings.json" <<EOF
{
  "extraKnownMarketplaces": {
    "$MARKETPLACE": { "source": { "source": "directory", "path": "$REPO" } }
  },
  "enabledPlugins": { "vt@$MARKETPLACE": true }
}
EOF
}

write_meta() {  # <root>
  cat > "$1/.sandbox-meta" <<EOF
MODE=$MODE
INSTALL=$INSTALL
EMPTY=$EMPTY
REPO=$REPO
CREATED=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
}

print_launch() {  # <root> <workspace>
  local root="$1" ws="$2"
  echo
  echo "✓ sandbox '$NAME' ready  (${MODE}${INSTALL:+/$INSTALL}$([ "$EMPTY" = true ] && echo ', empty'))"
  echo "  root: $root"
  echo
  echo "Launch:"
  case "$MODE/$INSTALL" in
    light/*)
      echo "  cd \"$ws\" && claude --plugin-dir \"$PLUGIN_DIR\""
      ;;
    isolated/inject)
      echo "  cd \"$ws\" && claude --bare --settings \"$root/config/sandbox-settings.json\" --strict-mcp-config"
      ;;
    isolated/real)
      echo "  export HOME=\"$root/config\""
      echo "  claude plugin marketplace add \"$REPO\""
      echo "  claude plugin install vt@$MARKETPLACE"
      echo "  cd \"$ws\" && HOME=\"$root/config\" claude"
      ;;
  esac
  echo
  if [ "$EMPTY" = true ]; then
    echo "Walk (virgin): confirm vt is SILENT (no .vibe-table yet) → /vt:draft a story → /vt:today."
  else
    echo "Walk:  sentinel renders (B3)"
    echo "       · edit projects/acme-demo/content/post.md → DENIED (B1)"
    echo "       · edit study/notes.md → allowed"
    echo "       · /vt:today → then a same-session gated edit is allowed (B2)"
    echo "       · /vt:today shows the 3-group multiSelect (B5)"
    [ "$INSTALL" = real ] && echo "       · bump version → /plugin update → /reload-plugins → new hooks run (B4)"
  fi
}

# ── Commands ──────────────────────────────────────────────────────────────────
parse_new_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --light)        MODE=light ;;
      --isolated)     MODE=isolated ;;
      --real-install) INSTALL=real ;;
      --inject)       INSTALL=inject ;;
      --empty)        EMPTY=true ;;
      --seeded)       EMPTY=false ;;
      -*)             die "unknown flag: $1" ;;
      *)              [ -z "$NAME" ] && NAME="$1" || die "unexpected arg: $1" ;;
    esac
    shift
  done
  [ -z "$NAME" ] && NAME="demo"
  case "$NAME" in *[!A-Za-z0-9._-]*) die "name must be [A-Za-z0-9._-]: $NAME" ;; esac
  if [ "$MODE" = light ]; then
    [ "$INSTALL" = real ] && echo "sandbox: --real-install ignored in --light (uses --plugin-dir)" >&2
    INSTALL=""
  fi
}

cmd_new() {
  local root ws
  root="$(sandbox_root "$MODE" "$NAME")"
  [ -e "$root" ] && die "sandbox '$NAME' already exists at $root (use 'refresh' or 'rm')"
  ws="$root/workspace"
  mkdir -p "$ws"
  scaffold_mock "$ws"
  [ "$EMPTY" = false ] && seed_board "$ws/.vibe-table"
  write_meta "$root"
  case "$MODE/$INSTALL" in
    isolated/inject) write_settings "$root/config" ;;
    isolated/real)   mkdir -p "$root/config" ;;
  esac
  print_launch "$root" "$ws"
}

cmd_refresh() {
  local name="${1:-}" root ws
  [ -z "$name" ] && die "usage: sandbox refresh <name>"
  root="$(find_sandbox "$name")" || die "no sandbox '$name'"
  # shellcheck disable=SC1091
  . "$root/.sandbox-meta"   # restores MODE/INSTALL/EMPTY/REPO
  ws="$root/workspace"
  rm -rf "$ws/.vibe-table"
  [ "${EMPTY:-false}" = false ] && seed_board "$ws/.vibe-table"
  echo "✓ refreshed '$name' — board reset to seed ($root)"
}

cmd_list() {
  local found=0 d
  for d in "$PERSIST_BASE"/*/ "$TMP_BASE"/vt-sandbox-*/; do
    [ -f "${d}.sandbox-meta" ] || continue
    found=1
    ( # shellcheck disable=SC1091
      . "${d}.sandbox-meta"
      nm="$(basename "$d")"; [ "$MODE" = light ] && nm="${nm#vt-sandbox-}"
      printf '  %-16s %-9s %-7s %s\n' "$nm" "$MODE" "${INSTALL:--}" "$d" )
  done
  [ "$found" = 0 ] && echo "  (no sandboxes)"
}

cmd_rm() {
  local name="${1:-}" root
  [ -z "$name" ] && die "usage: sandbox rm <name>"
  root="$(find_sandbox "$name")" || die "no sandbox '$name'"
  case "$root" in
    "$PERSIST_BASE"/?*|"$TMP_BASE"/vt-sandbox-?*) ;;
    *) die "refusing to rm outside sandbox bases: $root" ;;
  esac
  rm -rf "$root"
  echo "✓ removed '$name' ($root)"
}

# ── Dispatch ──────────────────────────────────────────────────────────────────
case "${1:-}" in
  new)               shift; parse_new_args "$@"; cmd_new ;;
  refresh)           shift; cmd_refresh "${1:-}" ;;
  list)              cmd_list ;;
  rm)                shift; cmd_rm "${1:-}" ;;
  ""|-h|--help|help) usage ;;
  *)                 die "unknown subcommand: $1 (try: new|refresh|list|rm)" ;;
esac
