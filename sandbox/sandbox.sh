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
MARKETPLACE="vibe-table"   # must match .claude-plugin/marketplace.json "name"

# ── Defaults (set by parse_new_args) ────────────────────────────────────────────
# Default to --light: it keeps your real auth (no --bare → keychain/OAuth intact),
# and since sandboxes live OUTSIDE your project tree, other workspace hooks don't load.
# --isolated (--bare) is hermetic but SKIPS OAuth/keychain → needs ANTHROPIC_API_KEY.
MODE=light
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
  sandbox.sh expire <name>       backdate Today's focus → flips the gate ACTIVE
                                 (demo the B1 rail block on a live, reconciled board)
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

find_sandbox() {  # <name> → echo root, or return 1. Require the .sandbox-meta marker
                  # (not bare dir existence) so a stale config-only dir left by an aborted
                  # real-install can't shadow the real sandbox at the other location.
  [ -f "$PERSIST_BASE/$1/.sandbox-meta" ]        && { printf '%s' "$PERSIST_BASE/$1"; return 0; }
  [ -f "$TMP_BASE/vt-sandbox-$1/.sandbox-meta" ] && { printf '%s' "$TMP_BASE/vt-sandbox-$1"; return 0; }
  return 1
}

# ── Builders ──────────────────────────────────────────────────────────────────
scaffold_mock() {  # <workspace> — realistic mock tree. Gated-ness comes from the PATH
  local ws="$1"    # (matches vt_gated_globs defaults), NOT the content. Keep files NEUTRAL:
                   # meta-text like "this is gated" makes the model self-refuse by reading it
                   # instead of attempting the edit and letting the rail decide. Which paths
                   # are gated is documented in README / the launch walk, never in the files.
  mkdir -p "$ws/projects/acme-demo/content" \
           "$ws/projects/acme-demo/repo-scaffolding" \
           "$ws/projects/acme-demo/gists" \
           "$ws/projects/acme-demo/src" \
           "$ws/study"
  printf '# Launch post — draft\n\nAcme is live. What we shipped and why it matters.\n\n- intro hook\n- 3 feature highlights\n- CTA\n' \
    > "$ws/projects/acme-demo/content/post.md"
  printf '# acme-demo\n\nScaffolding for the acme demo project.\n' \
    > "$ws/projects/acme-demo/repo-scaffolding/README.md"
  printf '// acme-demo embeddable snippet\nexport function greet(name) {\n  return `Hello, ${name}!`;\n}\n' \
    > "$ws/projects/acme-demo/gists/snippet.js"
  printf '// acme-demo app entrypoint\nconsole.log("acme app starting");\n' \
    > "$ws/projects/acme-demo/src/app.js"
  printf '# Study notes\n\nScratch space for research and to-dos.\n' \
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
      echo
      echo "  ⚠  --bare SKIPS OAuth + keychain (CC docs) → a Max/Pro subscription shows"
      echo "     'Not logged in'. Authenticate with ANTHROPIC_API_KEY (or an apiKeyHelper in"
      echo "     the settings file). For an authenticated run with no setup, use --light."
      [ -z "${ANTHROPIC_API_KEY:-}" ] && echo "     (ANTHROPIC_API_KEY is not set in this shell.)"
      ;;
    isolated/real)
      echo "  export HOME=\"$root/config\""
      echo "  claude plugin marketplace add \"$REPO\""
      echo "  claude plugin install vt@$MARKETPLACE"
      echo "  cd \"$ws\" && HOME=\"$root/config\" claude"
      echo
      echo "  ⚠  \$HOME override may not resolve the macOS login keychain → if it shows"
      echo "     'Not logged in', run /login inside the session (one-time, into this config)."
      ;;
  esac
  echo
  if [ "$EMPTY" = true ]; then
    echo "Walk (virgin): confirm vt is SILENT (no .vibe-table yet) → /vt:configure"
    echo "       (detect → confirm projects/week-start/gated → bootstrap spawns this week's focus)."
  else
    echo "Walk:  sentinel renders (B3)"
    echo "       · ATTEMPT an Edit to projects/acme-demo/content/post.md (don't pre-judge it)"
    echo "         → the Edit tool returns the PreToolUse hook denial = B1, the thesis"
    echo "       · edit study/notes.md → allowed (exempt)"
    echo "       · /vt:week THEN /vt:today (fresh board = new ISO week, both needed) → retry"
    echo "         the gated edit, same session → now allowed = B2"
    echo "       · the reconciliation shows the multiSelect groups, labels → IDs = B5"
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

cmd_expire() {  # backdate Today's stamp so a reconciled board reads stale → gate active
  local name="${1:-}" root vt pri y
  [ -z "$name" ] && die "usage: sandbox expire <name>"
  root="$(find_sandbox "$name")" || die "no sandbox '$name'"
  vt="$root/workspace/.vibe-table"
  pri="$vt/current-priorities.md"
  [ -f "$pri" ] || die "no current-priorities.md in '$name' — run /vt:configure (or /vt:today) first"
  y=$(date -v-1d +%F 2>/dev/null || date -d 'yesterday' +%F)
  # Backdate ONLY Today (leave Week current) so a single /vt:today lifts the gate
  # again — the clean B1 (blocked) → B2 (allowed-same-session) demo.
  sed -i.bak -E "s/## Today \([0-9-]+\)/## Today ($y)/" "$pri" && rm -f "$pri.bak"
  : > "$vt/.armed"   # the gate only enforces once armed
  echo "✓ expired '$name' — Today backdated to $y; the rail is now ACTIVE for any NEW session."
  echo "  Demo: start a FRESH session (the /configure session stays cleared by design) →"
  echo "  attempt an Edit to a gated path → BLOCKED (B1); run /vt:today → retry → ALLOWED (B2)."
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
  expire)            shift; cmd_expire "${1:-}" ;;
  list)              cmd_list ;;
  rm)                shift; cmd_rm "${1:-}" ;;
  ""|-h|--help|help) usage ;;
  *)                 die "unknown subcommand: $1 (try: new|refresh|list|rm)" ;;
esac
