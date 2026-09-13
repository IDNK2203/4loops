#!/usr/bin/env bash
# vt-priority.sh — mid-flight priority edits (v2.5 Packet 006: checkbox priorities).
# Re-point today / the week BETWEEN orientations without re-running /week. Items
# may be board IDs (P0-12), store IDs (CAP-003), or FREE TEXT — free text lands in
# the store on the spot (today → lever=today, week → lever=later). No board write.
#
# Rules (LOCKED): week ≤ 5 open · today 2–3, only from the week · a today add is
# promoted onto the week (no orphan today items).
#
#   vt-priority.sh [--project P] add  <item...>   add to today (promotes onto the week), freshen stamp
#   vt-priority.sh [--project P] set  <item...>   replace today (same rule), freshen stamp
#   vt-priority.sh drop <ID...>                   take off today (CAP → lever later)
#   vt-priority.sh done <ID...>                   check the box [x] (today + week); CAP → store done
#   vt-priority.sh [--project P] week add|set <item...>   the week's list, under the cap
#   vt-priority.sh week drop <ID...>
#   vt-priority.sh since                          board + store items that landed since the
#                                                 last Today stamp and aren't on today
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=./vt-priorities-lib.sh
source "$SCRIPT_DIR/vt-priorities-lib.sh"

PROJECT=""
if [ "${1:-}" = "--project" ]; then PROJECT="${2:-}"; shift 2; fi

section=today
if [ "${1:-}" = "week" ]; then section=week; shift; fi
sub="${1:-}"
[ $# -gt 0 ] && shift

# Arm the rail and clear this session if the gate is fully clear — the same
# closing move the ritual makes, so a mid-flight re-point also lifts the gate.
_finish() {
  # shellcheck source=./vt-guard-lib.sh
  source "$SCRIPT_DIR/vt-guard-lib.sh"
  vt_arm_rail
  vt_gate_active || vt_mark_session_cleared "${CLAUDE_CODE_SESSION_ID:-}"
}

# Commit a today list: size rule, promote onto the week (cap), write, levers.
_commit_today() {
  local ids="$1" reason="$2" week_ids
  check_today_size "$ids" || exit 4
  week_ids=$(week_with_today "$ids") || exit 4
  if [ "$week_ids" != "$(read_focus week)" ]; then write_week_list_keep_stamp "$week_ids" "promote-from-today"; fi
  write_focus_section today "$ids" "$reason"
  sync_store_levers_today "$ids"
  _finish
}

# Commit a week list under the cap. Today untouched.
_commit_week() {
  local ids="$1" reason="$2"
  check_week_cap "$ids" || exit 4
  write_focus_section week "$ids" "$reason"
  _finish
}

label() { if [ "$section" = today ]; then echo "Today"; else echo "Week"; fi; }

case "$sub" in
  add)
    [ $# -gt 0 ] || { echo "usage: vt-priority.sh [week] add <ID|\"text\">..." >&2; exit 1; }
    if [ "$section" = today ]; then precheck_today_tokens add "$@" || exit 4; else precheck_week_tokens add "$@" || exit 4; fi
    new=$(resolve_focus_tokens "$section" "$PROJECT" "$@")
    merged=$(_merge_ids "$(read_focus "$section")" $new)
    if [ "$section" = today ]; then _commit_today "$merged" "add"; else _commit_week "$merged" "add"; fi
    echo "$(label): ${merged:-—}"
    ;;
  set)
    if [ "$section" = today ]; then precheck_today_tokens set "$@" || exit 4; else precheck_week_tokens set "$@" || exit 4; fi
    new=$(resolve_focus_tokens "$section" "$PROJECT" "$@")
    if [ "$section" = today ]; then _commit_today "$new" "set"; else _commit_week "$new" "set"; fi
    echo "$(label): ${new:-—}"
    ;;
  drop)
    [ $# -gt 0 ] || { echo "usage: vt-priority.sh [week] drop <ID>..." >&2; exit 1; }
    keep=$(_without_ids "$(read_focus "$section")" "$@")
    if [ "$section" = today ]; then
      write_focus_section today "$keep" "drop"; sync_store_levers_today "$keep"; _finish
    else
      # Dropping from the week also drops from today (today ⊆ week).
      tkeep=$(_without_ids "$(read_focus today)" "$@")
      write_focus_section week "$keep" "drop"
      if [ "$tkeep" != "$(read_focus today)" ]; then
        _write_priorities_file "$tkeep" "$(read_today_stamp)" "$keep" "$(read_week_stamp)"
        log_priorities today "$tkeep" "drop-with-week"; sync_store_levers_today "$tkeep"
      fi
      _finish
    fi
    echo "$(label): ${keep:-—}"
    ;;
  done)
    [ $# -gt 0 ] || { echo "usage: vt-priority.sh done <ID>..." >&2; exit 1; }
    ids=""; for id in "$@"; do
      case " $(read_focus today) $(read_focus week) " in
        *" $id "*) ids=$(_merge_ids "$ids" "$id") ;;
        *) echo "warn: $id is not on today or the week — nothing to check." >&2 ;;
      esac
    done
    [ -n "$ids" ] || exit 1
    mark_done "$ids"
    echo "Done: ${ids}"
    print_priorities
    ;;
  since)
    stamp=$(read_today_stamp); [ -z "$stamp" ] && stamp=$(iso_today)
    focus=$(read_focus today)
    out=$(stories_since "$stamp" "$focus")
    sd=$(vt_store_dir)
    if [ -d "$sd/items" ]; then
      for f in "$sd"/items/CAP-*; do
        [ -f "$f" ] || continue
        id=$(basename "$f")
        case " $focus " in *" $id "*) continue ;; esac
        case "$(vt_store_get "$f" state)" in captured|active) ;; *) continue ;; esac
        cap=$(vt_store_get "$f" captured_at); cap=${cap:0:10}
        [ -n "$cap" ] || continue
        [[ "$cap" > "$stamp" || "$cap" == "$stamp" ]] || continue
        out="${out:+$out
}${id}  $(vt_store_get "$f" title)  [store·$(vt_store_get_lever "$f")]"
      done
    fi
    if [ -z "$out" ]; then
      echo "(nothing new since ${stamp} — today is current)"
    else
      echo "Added/moved since ${stamp} (not on today):"
      printf '%s\n' "$out" | sed 's/^/  /'
    fi
    ;;
  *)
    echo "usage: vt-priority.sh [--project P] [week] add|set <ID|\"text\">... | [week] drop <ID>... | done <ID>... | since" >&2; exit 1
    ;;
esac
