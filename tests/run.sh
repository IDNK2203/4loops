#!/usr/bin/env bash
# Vibe Table mechanical regression suite. Repo-relative; run from anywhere:
#   bash tests/run.sh
# Covers the headline behaviors + regressions for the bugs found in the
# 2026-05-29 battle-test fan-out. The LIVE behaviors (does CC honor a plugin
# PreToolUse deny, AskUserQuestion render, version-cache, SessionStart cwd) are
# NOT here — they're the live walkthrough in DOGFOOD-PLAN.md.
set -uo pipefail

PLUGIN="$(cd "$(dirname "$0")/../plugin" && pwd)"
S="$PLUGIN/scripts"; H="$PLUGIN/hooks"
P=0; F=0
ok(){ P=$((P+1)); printf '  PASS  %s\n' "$1"; }
no(){ F=$((F+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; return 0; }
ck(){ if eval "$2"; then ok "$1"; else no "$1" "${3:-}"; fi; }

TODAY=$(date +%F); WK=$(date +%V)
D10=$(date -v-10d +%F 2>/dev/null || date -d '10 days ago' +%F)
D30=$(date -v-30d +%F 2>/dev/null || date -d '30 days ago' +%F)

mkboard(){ # $1=VT_DIR ; writes a minimal valid board + dirs
  mkdir -p "$1/.cleared" "$1/archive"
  cat > "$1/board.md" <<EOF
# Vibe Table

**Counts:** Backlog 0 · Planning 0 · In Progress 0 · Testing 0 · Done 0

## Projects

| Key | Project | Repo |
| --- | ------- | ---- |
| P0 | dev-os | — |

---

| Backlog | Planning | In Progress | Testing | Done |
| ------- | -------- | ----------- | ------- | ---- |
EOF
}

echo "════ 1. Gate guard (PreToolUse) ════"
W=$(mktemp -d); VT="$W/.vibe-table"; mkboard "$VT"; : > "$VT/.armed"; : > "$VT/transitions.log"
mkdir -p "$W/projects/p0/content" "$W/projects/p0/study" "$W/src"; printf '# x\n' > "$W/README.md"
pj(){ printf '{"session_id":"%s","cwd":"%s","tool_input":{"file_path":"%s"}}' "$1" "$W" "$2"; }
gate(){ printf '%s' "$1" | bash "$H/vt-gate.sh" 2>&1; }   # echoes deny JSON or nothing
isdeny(){ printf '%s' "$1" | grep -q '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"'; }
# stale (no priorities file)
ck "block: stale + gated"        'O=$(gate "$(pj S1 "$W/projects/p0/content/a.md")"); isdeny "$O"'
ck "allow: exempt study/"        'O=$(gate "$(pj S1 "$W/projects/p0/study/n.md")"); ! isdeny "$O"'
ck "allow: exempt root *.md"     'O=$(gate "$(pj S1 "$W/README.md")"); ! isdeny "$O"'
ck "allow: exempt .vibe-table/"  'O=$(gate "$(pj S1 "$W/.vibe-table/board.md")"); ! isdeny "$O"'
ck "allow: non-gated src/"       'O=$(gate "$(pj S1 "$W/src/x.js")"); ! isdeny "$O"'
: > "$VT/.cleared/S2"
ck "allow: cleared session"      'O=$(gate "$(pj S2 "$W/projects/p0/content/a.md")"); ! isdeny "$O"'
ck "allow: env override + log"   'O=$(VT_ALLOW_STALE_GATE=1 gate "$(pj S3 "$W/projects/p0/content/a.md")"); ! isdeny "$O" && grep -q VT_ALLOW_STALE_GATE "$VT/override.log"'
rm -f "$VT/.armed"
ck "allow: on-ramp (unarmed)"    'O=$(gate "$(pj S4 "$W/projects/p0/content/a.md")"); ! isdeny "$O"'

echo "════ 2. Regression: bugs from the 2026-05-29 fan-out ════"
W2=$(mktemp -d); VT="$W2/.vibe-table"; mkboard "$VT"
export VT_DIR="$VT"; BOARD="$VT/board.md"; TRANSITIONS="$VT/transitions.log"; PRIORITIES="$VT/current-priorities.md"
# shellcheck source=/dev/null
source "$S/vt-priorities-lib.sh"; source "$S/vt-drift-lib.sh"
# board with three in-progress stories: P0-100 (focused, stale), P0-101 (stale),
# P0-102 (no transition-log entry)
cat > "$BOARD" <<EOF
# Vibe Table

**Counts:** Backlog 0 · Planning 0 · In Progress 3 · Testing 0 · Done 0

## Projects

| Key | Project | Repo |
| --- | ------- | ---- |
| P0 | dev-os | — |

---

| Backlog | Planning | In Progress | Testing | Done |
| ------- | -------- | ----------- | ------- | ---- |
|  |  | [P0] **P0-100** focused stale |  |  |
|  |  | [P0] **P0-101** logged stale |  |  |
|  |  | [P0] **P0-102** no-log story |  |  |
EOF
# P0-100 + P0-101 have transitions 30d ago; P0-102 has NO log entry
printf '%sT10:00:00Z\tP0-100\tplanning→in-progress\n%sT10:00:00Z\tP0-101\tplanning→in-progress\n' "$D30" "$D30" > "$TRANSITIONS"
# focus = P0-100 (today)
printf '# Current Priorities — w\n\n## Today (%s)\nFocus: P0-100\n\n## Week %s (r)\nFocus: P0-100\n' "$TODAY" "$WK" > "$PRIORITIES"
AB=$(find_abandoned 21)
ck "find_abandoned: spares FOCUSED story"     '! printf "%s" "$AB" | grep -q P0-100'
ck "find_abandoned: flags non-focus stale"    'printf "%s" "$AB" | grep -q P0-101'
ck "find_abandoned: skips NO-LOG story"        '! printf "%s" "$AB" | grep -q P0-102'
ST=$(find_stale 14)
ck "find_stale: skips NO-LOG story"            '! printf "%s" "$ST" | grep -q P0-102'
ck "find_stale: flags logged stale"            'printf "%s" "$ST" | grep -q P0-101'
# week-stamp padding (simulate ISO week 05 via override)
iso_week_num(){ echo "05"; }
ck "week_stamp_current: 5 == 05 (padding)"     'week_stamp_current "5"'
ck "week_stamp_current: 05 == 05"              'week_stamp_current "05"'
ck "week_stamp_current: 6 != 05"               '! week_stamp_current "6"'
ck "week_stamp_current: empty → not current"   '! week_stamp_current ""'
source "$S/vt-priorities-lib.sh"   # restore the real iso_week_num (override above was a stub)
# weekly_rollover must NOT archive the focused or no-log story
weekly_rollover >/dev/null 2>&1
M=$(date +%Y-%m)
ck "rollover: focused P0-100 stays on board"   'grep -q P0-100 "$BOARD"'
ck "rollover: no-log P0-102 stays on board"    'grep -q P0-102 "$BOARD"'
ck "rollover: stale P0-101 archived"           'grep -q P0-101 "$VT/archive/$M/abandoned.md" 2>/dev/null && ! grep -q P0-101 "$BOARD"'
# each ritual freshens ONLY its own stamp (week-alone must NOT clear the day gate)
rm -f "$PRIORITIES"
write_focus_section week "P0-100"
ck "ritual: /week leaves Today STALE"          '[ -z "$(read_today_stamp)" ]'
ck "ritual: /week sets Week current"           'week_stamp_current "$(read_week_stamp)"'
write_focus_section today "P0-100"
ck "ritual: /today PRESERVES Week stamp"        'week_stamp_current "$(read_week_stamp)"'
ck "ritual: /today sets Today current"          '[ "$(read_today_stamp)" = "$(iso_today)" ]'
unset VT_DIR

echo "════ 3. Sentinel render + malformed-board warn ════"
W3=$(mktemp -d); VT="$W3/.vibe-table"; mkboard "$VT"; : > "$VT/.armed"; : > "$VT/transitions.log"
cat >> "$VT/board.md" <<EOF
|  |  | [P0] **P0-007** Hard gate foundation |  |  |
EOF
printf '%sT10:00:00Z\tP0-007\tplanning→in-progress\n' "$D10" >> "$VT/transitions.log"
printf '# Current Priorities — w\n\n## Today (%s)\nFocus: P0-007\n\n## Week %s (r)\nFocus: P0-007\n' "$TODAY" "$WK" > "$VT/current-priorities.md"
SOUT=$(cd "$W3" && printf '{"session_id":"SR","source":"startup"}' | bash "$H/sentinel.sh" 2>/dev/null)
ck "sentinel: valid JSON"            'printf "%s" "$SOUT" | jq -e . >/dev/null 2>&1'
C=$(printf '%s' "$SOUT" | jq -r '.hookSpecificOutput.additionalContext')
ck "sentinel: renders task w/ title" 'printf "%s" "$C" | grep -q "P0-007  Hard gate foundation"'
ck "sentinel: · header"              'printf "%s" "$C" | grep -q "Vibe Table · "'
# break the separator → malformed warn
sed -i.bak 's/^| ------- | -------- | ----------- | ------- | ---- |$/| - | - | - | - | - |/' "$VT/board.md" && rm -f "$VT/board.md.bak"
SOUT2=$(cd "$W3" && printf '{"session_id":"SR2","source":"startup"}' | bash "$H/sentinel.sh" 2>/dev/null)
C2=$(printf '%s' "$SOUT2" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
ck "sentinel: malformed-board WARN"  'printf "%s" "$C2" | grep -q "\[WARN\] board.md looks malformed"'

echo "════ 4. Dense board storage (P0-016) ════"
W4=$(mktemp -d); export VT_DIR="$W4/.vibe-table"
for t in a b c d e; do bash "$S/vt-draft.sh" T "$t" >/dev/null; done
bash "$S/vt-transition.sh" T-002 in-progress >/dev/null
bash "$S/vt-transition.sh" T-003 testing >/dev/null
bash "$S/vt-transition.sh" T-004 in-progress >/dev/null
# 5 stories: backlog {T-001,T-005}, in-progress {T-002,T-004}, testing {T-003}.
# Dense grid → 2 body rows (max column height). A staircase would be 5.
NR=$(awk '/^\| Backlog \| Planning/{b=1;getline;next} b&&/^\|/{c++} END{print c+0}' "$VT_DIR/board.md")
NSTORIES=$(grep -oE 'T-00[1-5]' "$VT_DIR/board.md" | wc -l | tr -d ' ')
ck "dense: body rows = max col height (2)"       '[ '"$NR"' -eq 2 ]'
ck "dense: all 5 stories retained (no loss)"      '[ '"$NSTORIES"' -eq 5 ]'
source "$S/vt-priorities-lib.sh"
ck "dense: story_state resolves co-located cell"  '[ "$(story_state T-004)" = "in-progress" ]'
bash "$S/vt-transition.sh" T-002 done >/dev/null
ck "dense: co-located T-004 survives T-002 move"  'grep -q T-004 "$VT_DIR/board.md"'
unset VT_DIR

echo "════ 5. Carry-over slice + week-start (P0-015) ════"
W5=$(mktemp -d); export VT_DIR="$W5/.vibe-table"; mkboard "$VT_DIR"; : > "$VT_DIR/transitions.log"
BOARD="$VT_DIR/board.md"; TRANSITIONS="$VT_DIR/transitions.log"; PRIORITIES="$VT_DIR/current-priorities.md"
# shellcheck source=/dev/null
source "$S/vt-priorities-lib.sh"
cat >> "$BOARD" <<EOF
|  |  | [P0] **P0-200** durative wip |  | [P0] **P0-202** shipped today |
|  |  |  | [P0] **P0-201** in testing |  |
EOF
# P0-200 started 30d ago (NOT touched this window); P0-202 transitioned to done TODAY
printf '%sT10:00:00Z\tP0-200\tplanning→in-progress\n%sT09:00:00Z\tP0-202\ttesting→done\n' "$D30" "$TODAY" > "$TRANSITIONS"
IP=$(activity_lines today in-progress "P0-200")
ck "carry-over: focused in-progress shows w/o today-touch" 'printf "%s" "$IP" | grep -q "P0-200"'
ck "carry-over: empty focus → none"                        '[ "$(activity_lines today in-progress "")" = "- (none)" ]'
ck "carry-over: focus not-in-progress → none"              '[ "$(activity_lines today in-progress "P0-201")" = "- (none)" ]'
CP=$(activity_lines today completed)
ck "completed: today journal shows P0-202"                 'printf "%s" "$CP" | grep -q "P0-202"'
ck "completed: stale non-done excluded"                    '! printf "%s" "$CP" | grep -q "P0-200"'
# week-start: default mon mirrors ISO exactly (no regression)
ck "week-start: default = mon"                  '[ "$(vt_week_start)" = "mon" ]'
ck "week-start: mon num == iso_week_num"        '[ "$(week_num_current)" = "$(iso_week_num)" ]'
ck "week-start: mon marker == legacy form"      '[ "$(week_marker_id)" = "$(iso_year)-W$(iso_week_num)" ]'
dow(){ date -j -f "%Y-%m-%d" "$1" +%u 2>/dev/null || date -d "$1" +%u; }
ck "week-start: mon start_date is a Monday"     '[ "$(dow "$(week_start_date)")" = "1" ]'
# week-start: sun read from config flips the boundary
printf 'week-start: sun\n' > "$VT_DIR/config"
ck "week-start: reads sun from config"          '[ "$(vt_week_start)" = "sun" ]'
ck "week-start: sun num == %U"                  '[ "$(week_num_current)" = "$(date +%U)" ]'
ck "week-start: sun start_date is a Sunday"     '[ "$(dow "$(week_start_date)")" = "7" ]'
rm -f "$VT_DIR/config"
unset VT_DIR

echo
echo "════ RESULT: $P passed, $F failed ════"
[ "$F" -eq 0 ]