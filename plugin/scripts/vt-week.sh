#!/usr/bin/env bash
# vt-week.sh — the ONE-SHOT orientation (v2.5 Packet 006). Week + today in one flow.
#
#   vt-week.sh --orient              → print the priorities file · look-back (last week on a
#                                      new week, since-yesterday otherwise) · week pick list
#                                      from the store (cap-aware) · today pick · machine lines
#                                      (MODE / WEEK_ACTIVE / WEEK_CAP_LEFT / WEEK_SUGGESTED /
#                                      TODAY_SUGGESTED). Read-only, never gated.
#   vt-week.sh --print               → the priorities file (checkboxes). Read-only.
#   vt-week.sh --default             → WEEK_SUGGESTED IDs only
#   vt-week.sh --current             → IDs on the week now (open + done)
#   vt-week.sh [--project P] [set] <ID|"text"> ... [--today <ID|"text"> ...]
#                                    → set the week (≤ 5 open; free text → store, lever=later)
#                                      and, with --today, today's 2–3 from it — one write, both
#                                      stamps fresh, gate clears.
#   vt-week.sh [--project P] add <ID|"text"> ... [--today ...]
#                                    → add to the week under the cap (2 on → at most 3 new)
#   vt-week.sh [--project P] today <ID|"text"> ...
#                                    → the today beat alone: 2–3 from the week (a pick not on
#                                      the week is promoted onto it). Gate clears.
# Board is a state check — board.md is never written here.
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=./vt-priorities-lib.sh
source "$SCRIPT_DIR/vt-priorities-lib.sh"

usage() {
  cat <<'USAGE' >&2
Usage:
  vt-week.sh --orient                       One-shot orientation print (file · look-back · week pick · today pick)
  vt-week.sh --print                        The priorities file
  vt-week.sh --default                      WEEK_SUGGESTED IDs only
  vt-week.sh --current                      IDs on the week now
  vt-week.sh [--project P] [set] <items>... [--today <items>...]
                                            Set the week (≤5 open) and optionally today (2–3 from it)
  vt-week.sh [--project P] add <items>... [--today <items>...]
                                            Add to the week under the cap
  vt-week.sh [--project P] today <items>... Today's 2–3 from the week (promotes onto the week if needed)
Items: board IDs (P0-12), store IDs (CAP-003), or free text (→ store).
USAGE
  exit 1
}

PROJECT=""
if [ "${1:-}" = "--project" ]; then PROJECT="${2:-}"; shift 2; fi

# Close a gate-clearing commit: arm the rail; record this session cleared only
# if BOTH stamps are now fresh.
_finish() {
  # shellcheck source=./vt-guard-lib.sh
  source "$SCRIPT_DIR/vt-guard-lib.sh"
  vt_arm_rail
  vt_gate_active || vt_mark_session_cleared "${CLAUDE_CODE_SESSION_ID:-}"
}

# Split "<week items> [--today <today items>]" into WEEK_ARGS / TODAY_ARGS.
WEEK_ARGS=(); TODAY_ARGS=(); HAVE_TODAY=0
_split_args() {
  local in_today=0 a
  for a in "$@"; do
    if [ "$a" = "--today" ]; then in_today=1; HAVE_TODAY=1; continue; fi
    if [ "$in_today" = 1 ]; then TODAY_ARGS+=("$a"); else WEEK_ARGS+=("$a"); fi
  done
}

# Commit the today beat against a given week list. $1 = week ids, rest = today tokens.
# Writes week + today with fresh stamps (one-shot), syncs store levers, clears the gate.
_commit_week_and_today() {
  local week_ids="$1"; shift
  local today_ids n_new n_week
  # Pre-flight on raw tokens (no store writes on a refusal).
  _today_size_ok "$(_count_new_tokens "" "$@")" || exit 4
  n_new=$(_count_new_tokens "$week_ids" "$@"); n_week=0
  for id in $week_ids; do focus_done "$id" || n_week=$((n_week+1)); done
  _week_cap_ok $(( n_week + n_new )) "$n_week" "$n_new" || exit 4
  today_ids=$(resolve_focus_tokens today "$PROJECT" "$@")
  check_today_size "$today_ids" || exit 4
  week_ids=$(week_with_today "$today_ids" "$week_ids") || exit 4
  write_orientation "$week_ids" "$today_ids" "week"
  sync_store_levers_today "$today_ids"
  _finish
  echo "Week set: ${week_ids:-—}"
  echo "Today set: ${today_ids:-—}"
}

case "${1:-}" in
  --orient)  render_week_orient ;;
  --print)   print_priorities ;;
  --default) printf '%s\n' "$(suggest_week)" ;;
  --current) read_focus week; echo ;;
  ""|-h|--help) usage ;;
  today)
    shift
    [ $# -gt 0 ] || usage
    if [ "${VT_ALLOW_TODAY_FIRST:-0}" != "1" ] && ! week_stamp_current "$(read_week_stamp)"; then
      echo "4loops: it's a new week — set the week first (vt-week.sh set <items> --today <items>), then today comes from it." >&2
      exit 3
    fi
    _commit_week_and_today "$(read_focus week)" "$@"
    ;;
  set|add|*)
    # An unknown --flag must never fall through to the item parser: the catch-all
    # below treats a bare token as free text, so `vt-week.sh --yesterday` would
    # silently CREATE a store item named "--yesterday" and set the week — a write
    # from something that reads like a read (v2.5 Packet 009).
    case "${1:-}" in
      --*) echo "4loops: vt-week.sh has no ${1} mode (read-only modes: --orient --print --default --current; --yesterday lives on vt-today.sh)." >&2; exit 2 ;;
    esac
    mode=set
    case "${1:-}" in set) shift ;; add) mode=add; shift ;; esac
    [ $# -gt 0 ] || usage
    _split_args "$@"
    [ "${#WEEK_ARGS[@]}" -gt 0 ] || { echo "4loops: name the week's items before --today." >&2; usage; }
    precheck_week_tokens "$mode" "${WEEK_ARGS[@]}" || exit 4
    new_ids=$(resolve_focus_tokens week "$PROJECT" "${WEEK_ARGS[@]}")
    if [ "$mode" = add ]; then week_ids=$(_merge_ids "$(read_focus week)" $new_ids); else week_ids="$new_ids"; fi
    check_week_cap "$week_ids" || exit 4
    if [ "$HAVE_TODAY" = 1 ]; then
      [ "${#TODAY_ARGS[@]}" -gt 0 ] || { echo "4loops: --today needs 2–3 items from the week." >&2; exit 1; }
      _commit_week_and_today "$week_ids" "${TODAY_ARGS[@]}"
    else
      # Week only: fresh week stamp; today untouched (stale stays stale until the
      # today beat — that's part of the same /week flow, not a second ritual).
      write_focus_section week "$week_ids" "$mode"
      _finish
      echo "Week set: ${week_ids:-—}"
      vt_gate_active && echo "next: today's ${VT_TODAY_MIN}–${VT_TODAY_MAX} from the week — vt-week.sh today <items> (clears the gate)." >&2
      true
    fi
    ;;
esac
