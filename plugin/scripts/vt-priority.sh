#!/usr/bin/env bash
# vt-priority.sh — mid-flight priority edits (v2.5 Real C: direct add to Today / Week).
# Re-point priority BETWEEN the daily/weekly rituals without rerunning the whole
# walk. Items may be board IDs (P0-12), store IDs (CAP-003), or FREE TEXT — free
# text lands in the detached store on the spot (today → lever=today, week →
# lever=later) and goes straight into the priorities doc. No capture step, no
# board write.
#
#   vt-priority.sh [--project P] add  <item...>   append to today's focus (dedup), freshen stamp
#   vt-priority.sh [--project P] set  <item...>   replace today's focus, freshen stamp
#   vt-priority.sh drop <ID...>                   remove from today's focus (CAP → lever later)
#   vt-priority.sh [--project P] week add|set <item...>   same, for the Week anchors
#   vt-priority.sh week drop <ID...>
#   vt-priority.sh since                          board + store items that landed since the
#                                                 last Today stamp and aren't in focus
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

# Freshen the section, arm the rail, and clear this session if the gate is fully
# clear — the same closing move the ritual makes, so a mid-flight re-point also
# lifts the gate. Today commits keep store levers coherent with the focus.
_commit() {
  local which="$1" ids="$2" reason="$3"
  write_focus_section "$which" "$ids" "$reason"
  [ "$which" = today ] && sync_store_levers_today "$ids"
  # shellcheck source=./vt-guard-lib.sh
  source "$SCRIPT_DIR/vt-guard-lib.sh"
  vt_arm_rail
  vt_gate_active || vt_mark_session_cleared "${CLAUDE_CODE_SESSION_ID:-}"
}

label() { if [ "$section" = today ]; then echo "Today focus"; else echo "Week anchors"; fi; }

case "$sub" in
  add)
    [ $# -gt 0 ] || { echo "usage: vt-priority.sh [week] add <ID|\"text\">..." >&2; exit 1; }
    new=$(resolve_focus_tokens "$section" "$PROJECT" "$@")
    merged=$(_merge_ids "$(read_focus "$section")" $new)
    _commit "$section" "$merged" "add"
    echo "$(label): ${merged:-—}"
    ;;
  set)
    new=$(resolve_focus_tokens "$section" "$PROJECT" "$@")
    _commit "$section" "$new" "set"
    echo "$(label): ${new:-—}"
    ;;
  drop)
    [ $# -gt 0 ] || { echo "usage: vt-priority.sh [week] drop <ID>..." >&2; exit 1; }
    keep=""
    for id in $(read_focus "$section"); do
      case " $* " in *" $id "*) ;; *) keep="${keep:+$keep }$id" ;; esac
    done
    _commit "$section" "$keep" "drop"
    echo "$(label): ${keep:-—}"
    ;;
  since)
    stamp=$(read_today_stamp); [ -z "$stamp" ] && stamp=$(iso_today)
    focus=$(read_focus today)
    out=$(stories_since "$stamp" "$focus")
    # Store items captured on/after the stamp that aren't in focus.
    sd=$(vt_store_dir)
    if [ -d "$sd/items" ]; then
      for f in "$sd"/items/CAP-*; do
        [ -f "$f" ] || continue
        id=$(basename "$f")
        case " $focus " in *" $id "*) continue ;; esac
        cap=$(vt_store_get "$f" captured_at); cap=${cap:0:10}
        [ -n "$cap" ] || continue
        [[ "$cap" > "$stamp" || "$cap" == "$stamp" ]] || continue
        out="${out:+$out
}${id}  $(vt_store_get "$f" title)  [store·$(vt_store_get_lever "$f")]"
      done
    fi
    if [ -z "$out" ]; then
      echo "(nothing new since ${stamp} — focus is current)"
    else
      echo "Added/moved since ${stamp} (not in focus):"
      printf '%s\n' "$out" | sed 's/^/  /'
    fi
    ;;
  *)
    echo "usage: vt-priority.sh [--project P] [week] add|set <ID|\"text\">... | [week] drop <ID>... | since" >&2; exit 1
    ;;
esac
