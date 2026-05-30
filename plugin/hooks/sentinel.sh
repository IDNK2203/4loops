#!/usr/bin/env bash
# sentinel.sh — Vibe Table SessionStart hook (premium dashboard render).
#
# Builds ONE dashboard string and emits it as both channels:
#   - hookSpecificOutput.additionalContext → Claude's context (board state + directives)
#   - systemMessage (with a leading newline so the block sits on its own lines,
#     NOT jammed into the "SessionStart startup" status prefix) → the user sees it
#
# The dashboard shows board state at a glance: counts, today's tasks (ID + title),
# this week's tasks, and surfaced drift. The full kanban stays a /vt:board call.
#
# Side effects: auto weekly rollover (armed-gated, idempotent), session-scoped
# gate clearing (carry across midnight), and marker pruning.
#
# Falls back to plain stdout if jq is unavailable (context-only).
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=../scripts/vt-priorities-lib.sh
source "$SCRIPT_DIR/../scripts/vt-priorities-lib.sh"
# shellcheck source=../scripts/vt-guard-lib.sh
source "$SCRIPT_DIR/../scripts/vt-guard-lib.sh"
# shellcheck source=../scripts/vt-drift-lib.sh
source "$SCRIPT_DIR/../scripts/vt-drift-lib.sh"

# If this workspace doesn't use Vibe Table, exit silently — don't pollute context.
[ ! -d "$VT_DIR" ] && exit 0

# Read the SessionStart payload; session_id drives gate session-clearing.
HOOK_INPUT=$(cat 2>/dev/null || printf '{}')
SID=$(vt_json_field "$HOOK_INPUT" '.session_id')
WORKSPACE=$(basename "$(pwd)")

TODAY_STAMP=$(read_today_stamp); ISO_TODAY=$(iso_today)
WEEK_STAMP=$(read_week_stamp);   ISO_WEEK=$(iso_week_num)

TODAY_STALE=false
if [ -z "$TODAY_STAMP" ] || [ "$TODAY_STAMP" != "$ISO_TODAY" ]; then TODAY_STALE=true; fi
WEEK_STALE=false
if ! week_stamp_current "$WEEK_STAMP"; then WEEK_STALE=true; fi

# Auto weekly rollover (once per ISO week, self-guarded), gated on the rail being
# armed so a fresh install / on-ramp doesn't empty its Done column unprompted.
if vt_rail_armed; then
  weekly_rollover >/dev/null 2>&1 || true
fi

# Counts read AFTER any rollover so they reflect the current board.
COUNTS_LINE=""
[ -f "$BOARD" ] && COUNTS_LINE=$(awk '/^\*\*Counts:\*\*/ { sub(/^\*\*Counts:\*\* /, ""); print; exit }' "$BOARD" || true)

# Drift is SURFACED, never blocks (BRIEF §7).
DRIFT_LINE=$(render_drift || true)

# Board-shape sanity: kanban header + story rows present but board_rows parses
# none ⇒ a broken separator (hand-edit / markdown formatter). Warn, don't die.
WARN_LINE=""
if [ -f "$BOARD" ] \
   && grep -q '^| Backlog | Planning | In Progress | Testing | Done |$' "$BOARD" 2>/dev/null \
   && grep -qE '^\|.*\*\*[A-Za-z0-9]+-[0-9]+\*\*' "$BOARD" 2>/dev/null \
   && [ -z "$(board_rows)" ]; then
  WARN_LINE="[WARN] board.md looks malformed — rows present but unparseable. Check the | --- | separator row."
fi

# --- Build ONE premium dashboard string ----------------------------------------
nl=$'\n'
D="── Vibe Table · ${WORKSPACE} ──${nl}"
[ -n "$COUNTS_LINE" ] && D="${D}${COUNTS_LINE}${nl}"
[ -n "$WARN_LINE" ] && D="${D}${WARN_LINE}${nl}"
D="${D}${nl}"

if [ "$TODAY_STALE" = true ]; then
  if [ -z "$TODAY_STAMP" ]; then
    D="${D}[STALE] No Today focus — run /vt:today${nl}"
  else
    D="${D}[STALE] Today focus is ${TODAY_STAMP} (today ${ISO_TODAY}) — run /vt:today${nl}"
  fi
else
  D="${D}Today (${ISO_TODAY})${nl}$(render_focus_lines today || true)${nl}"
fi
D="${D}${nl}"

if [ "$WEEK_STALE" = true ]; then
  if [ -z "$WEEK_STAMP" ]; then
    D="${D}[STALE] No Week focus — run /vt:week${nl}"
  else
    D="${D}[STALE] Week focus is Week ${WEEK_STAMP} (now Week ${ISO_WEEK}) — run /vt:week, then /vt:today${nl}"
  fi
else
  D="${D}Week ${ISO_WEEK}${nl}$(render_focus_lines week || true)${nl}"
fi

[ -n "${DRIFT_LINE:-}" ] && D="${D}${nl}${DRIFT_LINE}${nl}"
if ! vt_rail_armed; then
  D="${D}${nl}[on-ramp] rail goes hard after your first /vt:today${nl}"
fi

# --- Session-scoped gate clearing + marker cleanup ------------------------------
# A session that starts on an already-reconciled day carries its clearance forward
# (never re-blocked across midnight).
if [ "$TODAY_STALE" = false ] && [ "$WEEK_STALE" = false ]; then
  vt_mark_session_cleared "$SID"
fi
vt_prune_cleared
find "$VT_DIR" -maxdepth 1 -name '.prompt-nudged-*' ! -name ".prompt-nudged-$(iso_today)" -delete 2>/dev/null || true

# --- Emit -----------------------------------------------------------------------
# systemMessage leads with a newline so the dashboard starts on its own line,
# separated from the SessionStart status prefix.
if command -v jq >/dev/null 2>&1; then
  jq -n --arg ctx "$D" --arg msg "${nl}${D}" \
    '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}, systemMessage: $msg}'
else
  printf '%s\n' "$D"
fi
