#!/usr/bin/env bash
# 4loops mechanical regression suite. Repo-relative; run from anywhere:
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
# 4loops

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
W=$(mktemp -d); VT="$W/.4loops"; mkboard "$VT"; : > "$VT/.armed"; : > "$VT/transitions.log"
mkdir -p "$W/projects/p0/content" "$W/projects/p0/study" "$W/src"; printf '# x\n' > "$W/README.md"
pj(){ printf '{"session_id":"%s","cwd":"%s","tool_input":{"file_path":"%s"}}' "$1" "$W" "$2"; }
gate(){ printf '%s' "$1" | bash "$H/vt-gate.sh" 2>&1; }   # echoes deny JSON or nothing
isdeny(){ printf '%s' "$1" | grep -q '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"'; }
# stale (no priorities file)
ck "block: stale + gated"        'O=$(gate "$(pj S1 "$W/projects/p0/content/a.md")"); isdeny "$O"'
ck "allow: exempt study/"        'O=$(gate "$(pj S1 "$W/projects/p0/study/n.md")"); ! isdeny "$O"'
ck "allow: exempt root *.md"     'O=$(gate "$(pj S1 "$W/README.md")"); ! isdeny "$O"'
ck "allow: exempt .4loops/"  'O=$(gate "$(pj S1 "$W/.4loops/transitions.log")"); ! isdeny "$O"'
ck "allow: non-gated src/"       'O=$(gate "$(pj S1 "$W/src/x.js")"); ! isdeny "$O"'
: > "$VT/.cleared/S2"
ck "allow: cleared session"      'O=$(gate "$(pj S2 "$W/projects/p0/content/a.md")"); ! isdeny "$O"'
ck "allow: env override + log"   'O=$(VT_ALLOW_STALE_GATE=1 gate "$(pj S3 "$W/projects/p0/content/a.md")"); ! isdeny "$O" && grep -q VT_ALLOW_STALE_GATE "$VT/override.log"'
rm -f "$VT/.armed"
ck "allow: on-ramp (unarmed)"    'O=$(gate "$(pj S4 "$W/projects/p0/content/a.md")"); ! isdeny "$O"'

echo "════ 2. Regression: bugs from the 2026-05-29 fan-out ════"
W2=$(mktemp -d); VT="$W2/.4loops"; mkboard "$VT"
export VT_DIR="$VT"; BOARD="$VT/board.md"; TRANSITIONS="$VT/transitions.log"; PRIORITIES="$VT/current-priorities.md"
# shellcheck source=/dev/null
source "$S/vt-priorities-lib.sh"; source "$S/vt-drift-lib.sh"
# board with three in-progress stories: P0-100 (focused, stale), P0-101 (stale),
# P0-102 (no transition-log entry)
cat > "$BOARD" <<EOF
# 4loops

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
W3=$(mktemp -d); VT="$W3/.4loops"; mkboard "$VT"; : > "$VT/.armed"; : > "$VT/transitions.log"
cat >> "$VT/board.md" <<EOF
|  |  | [P0] **P0-007** Hard gate foundation |  |  |
EOF
printf '%sT10:00:00Z\tP0-007\tplanning→in-progress\n' "$D10" >> "$VT/transitions.log"
printf '# Current Priorities — w\n\n## Today (%s)\nFocus: P0-007\n\n## Week %s (r)\nFocus: P0-007\n' "$TODAY" "$WK" > "$VT/current-priorities.md"
SOUT=$(cd "$W3" && printf '{"session_id":"SR","source":"startup"}' | bash "$H/sentinel.sh" 2>/dev/null)
ck "sentinel: valid JSON"            'printf "%s" "$SOUT" | jq -e . >/dev/null 2>&1'
C=$(printf '%s' "$SOUT" | jq -r '.hookSpecificOutput.additionalContext')
ck "sentinel: renders task w/ title" 'printf "%s" "$C" | grep -q "P0-007  Hard gate foundation"'
ck "sentinel: · header"              'printf "%s" "$C" | grep -q "4loops · "'
# break the separator → malformed warn
sed -i.bak 's/^| ------- | -------- | ----------- | ------- | ---- |$/| - | - | - | - | - |/' "$VT/board.md" && rm -f "$VT/board.md.bak"
SOUT2=$(cd "$W3" && printf '{"session_id":"SR2","source":"startup"}' | bash "$H/sentinel.sh" 2>/dev/null)
C2=$(printf '%s' "$SOUT2" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
ck "sentinel: malformed-board WARN"  'printf "%s" "$C2" | grep -q "\[WARN\] board.md looks malformed"'

echo "════ 4. Dense board storage (P0-016) ════"
W4=$(mktemp -d); export VT_DIR="$W4/.4loops"
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
W5=$(mktemp -d); export VT_DIR="$W5/.4loops"; mkboard "$VT_DIR"; : > "$VT_DIR/transitions.log"
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

echo "════ 6. Configure + bootstrap (P0-015) ════"
W6=$(mktemp -d)
mkdir -p "$W6/proj-one/.git" "$W6/proj-one/content" "$W6/notes" "$W6/node_modules/dep/.git" "$W6/.git"
printf '{}' > "$W6/proj-one/package.json"
DET=$("$S/vt-detect.sh" "$W6")
ck "detect: finds top-level project"      'printf "%s" "$DET" | grep -qE "^PROJECT'$'\t''proj-one'$'\t''[A-Z0-9]{2,3}$"'
ck "detect: gated glob is whole-project"  'printf "%s" "$DET" | grep -q "^GATED'$'\t''proj-one/\*$"'
ck "detect: non-repo folder is an Area"   'printf "%s" "$DET" | grep -q "^AREA'$'\t''notes$"'
ck "detect: Area is not a Project"        '! printf "%s" "$DET" | grep -q "^PROJECT'$'\t''notes"'
ck "detect: prunes node_modules repo"     '! printf "%s" "$DET" | grep -q "'$'\t''dep'$'\t''"'
ck "detect: excludes the root repo"       '[ "$(printf "%s" "$DET" | grep -c "^PROJECT")" = "1" ]'
# mono/root mode: a repo AT the workspace root (no nested repos) is the project
W6r=$(mktemp -d); mkdir -p "$W6r/.git" "$W6r/src" "$W6r/docs"
DETR=$("$S/vt-detect.sh" "$W6r")
ck "detect(root): one project (the root repo)" '[ "$(printf "%s" "$DETR" | grep -c "^PROJECT")" = "1" ]'
ck "detect(root): gates the whole workspace"   'printf "%s" "$DETR" | grep -q "^GATED'$'\t''\*$"'
ck "detect(root): no Areas in mono mode"       '! printf "%s" "$DETR" | grep -q "^AREA"'
rm -rf "$W6r"
# config writes (idempotent, replace/upsert)
export VT_DIR="$W6/.4loops"
"$S/vt-config.sh" week-start sun >/dev/null
"$S/vt-config.sh" gated 'a/*' 'b/*' >/dev/null
"$S/vt-config.sh" project PR "Proj One" "me/proj-one" >/dev/null
# shellcheck source=/dev/null
source "$S/vt-priorities-lib.sh"; source "$S/vt-guard-lib.sh"
ck "config: week-start reads back sun"    '[ "$(vt_week_start)" = "sun" ]'
ck "config: gated REPLACES default"       'G=$(vt_gated_globs); printf "%s" "$G" | grep -q "a/\*" && ! printf "%s" "$G" | grep -q "repo-scaffolding"'
ck "config: project row registered"       'grep -q "| PR | Proj One | me/proj-one |" "$VT_DIR/board.md"'
# bootstrap: spawn-from-focus, end to end
A=$("$S/vt-draft.sh" PR "ship the thing" | grep -oE 'PR-[0-9]+')
B=$("$S/vt-draft.sh" PR "write the post" | grep -oE 'PR-[0-9]+')
"$S/vt-week.sh"  "$A" "$B" >/dev/null
"$S/vt-transition.sh" "$A" in-progress >/dev/null
"$S/vt-today.sh" "$A" >/dev/null
ck "bootstrap: rail armed after today"    '[ -f "$VT_DIR/.armed" ]'
ck "bootstrap: A in priorities file"      'grep -q "'"$A"'" "$VT_DIR/current-priorities.md"'
ck "bootstrap: today in-progress shows A" 'sed -n "/In progress today/,/Completed today/p" "$VT_DIR/current-priorities.md" | grep -q "'"$A"'"'
ck "bootstrap: gate now clear (sun)"      '! vt_gate_active'
# whole-project gating (v1.1.1): one glob gates the ENTIRE project, recursively
"$S/vt-config.sh" gated 'proj-one/*' >/dev/null
ck "gate: deep file in project gated"        'vt_is_gated "$W6/proj-one/src/deep/x.js" "$W6"'
ck "gate: new root-level project file gated" 'vt_is_gated "$W6/proj-one/style.css" "$W6"'
ck "gate: Area file not gated"               '! vt_is_gated "$W6/notes/draft.md" "$W6"'
unset VT_DIR

echo "════ 7. Ship-prep fixes (P0-011) ════"
W7=$(mktemp -d); export VT_DIR="$W7/.4loops"
MO=$(date +%Y-%m)
bash "$S/vt-draft.sh" T "just a backlog item" >/dev/null
# shellcheck source=/dev/null
source "$S/vt-priorities-lib.sh"; source "$S/vt-drift-lib.sh"
weekly_rollover >/dev/null 2>&1
ck "no-op rollover: no empty archive dir"     '[ ! -d "$VT_DIR/archive/'"$MO"'" ]'
PID=$(bash "$S/vt-draft.sh" T 'Add foo | bar pipeline' | grep -oE 'T-[0-9]+')
ck "pipe title: full text in board cell"      'grep -q "Add foo │ bar pipeline" "$VT_DIR/board.md"'
ck "pipe title: story_title intact"           'printf "%s" "$(story_title "$PID")" | grep -q "bar pipeline"'
ck "pipe title: no raw pipe leaks"            '! printf "%s" "$(story_title "$PID")" | grep -q "[|]"'
bash "$S/vt-transition.sh" "$PID" done >/dev/null
rm -f "$VT_DIR"/.weekly-rolled-*
weekly_rollover >/dev/null 2>&1
ck "rollover WITH content: dir created"        '[ -d "$VT_DIR/archive/'"$MO"'" ]'
ck "pipe title: archive record intact"         'grep -q "Add foo │ bar pipeline" "$VT_DIR/archive/'"$MO"'/closed.md"'
unset VT_DIR

echo
echo "════ 8. Bash-gate: rm/mv/cp + cd-awareness (v1.1.2) ════"
W8=$(mktemp -d); mkdir -p "$W8/.4loops/.cleared" "$W8/proj/.git" "$W8/proj/sub" "$W8/notes"
export VT_DIR="$W8/.4loops"
"$S/vt-config.sh" gated 'proj/*' >/dev/null
: > "$VT_DIR/.armed"
printf '## Today (2020-01-01)\n\n## Week 1 (2020-01-01 → 01-07)\n' > "$VT_DIR/current-priorities.md"
ck "bash-gate: board is stale (gate active)"  'vt_gate_active'
gate_blocks(){ local o r; o=$(printf '{"tool_input":{"command":"%s"},"session_id":"fresh-z","cwd":"%s"}' "$1" "$W8" | bash "$H/vt-bash-gate.sh" 2>&1); r=$?; printf '%s' "$o" | grep -q '"deny"' || [ "$r" = 2 ]; }
ck "bash-gate: rm of gated file blocked"      'gate_blocks "rm proj/sub/x.js"'
ck "bash-gate: cp into gated blocked"         'gate_blocks "cp /tmp/a.txt proj/a.txt"'
ck "bash-gate: cd-then-rm gated blocked"      'gate_blocks "cd proj && rm sub/x.js"'
ck "bash-gate: rm outside any project ok"     '! gate_blocks "rm notes/x.md"'
unset VT_DIR

echo
echo "════ 9. Story types — DEV vs MODELING (W1, v2) ════"
W9=$(mktemp -d); export VT_DIR="$W9/.4loops"
# shellcheck source=/dev/null
source "$S/vt-priorities-lib.sh"
DID=$(bash "$S/vt-draft.sh" T "dev task" | grep -oE 'T-[0-9]+')
MID=$(bash "$S/vt-draft.sh" T "model task" --type modeling | grep -oE 'T-[0-9]+')
ck "type: dev row omits type token (back-compat)" '! grep "'"$DID"'" "$VT_DIR/board.md" | grep -q "type:"'
ck "type: modeling row carries token"             'grep "'"$MID"'" "$VT_DIR/board.md" | grep -q "type: modeling"'
ck "type: story_type reads dev (default)"         '[ "$(story_type "'"$DID"'")" = "dev" ]'
ck "type: story_type reads modeling"              '[ "$(story_type "'"$MID"'")" = "modeling" ]'
ck "type: story_title strips type token"          '[ "$(story_title "'"$MID"'")" = "model task" ]'
XID=$(bash "$S/vt-draft.sh" T "bogus type" --type nonsense | grep -oE 'T-[0-9]+')
ck "type: invalid --type falls back to dev"       '[ "$(story_type "'"$XID"'")" = "dev" ]'
MWARN=$(bash "$S/vt-transition.sh" "$MID" done 2>&1 >/dev/null)
ck "type: modeling DONE emits decision-log note"  'printf "%s" "$MWARN" | grep -q "MODELING"'
DWARN=$(bash "$S/vt-transition.sh" "$DID" done 2>&1 >/dev/null)
ck "type: dev DONE is silent (no note)"           '! printf "%s" "$DWARN" | grep -q "MODELING"'
ck "type: compact board marks modeling with ◆"    'bash "$S/vt-render.sh" | grep -q "◆"'
unset VT_DIR

echo
echo "════ 10. Archive / abandon / supersede + backdate (W2, v2) ════"
W10=$(mktemp -d); export VT_DIR="$W10/.4loops"
MO=$(date +%Y-%m)
A1=$(bash "$S/vt-draft.sh" T "dead idea"      | grep -oE 'T-[0-9]+')
A2=$(bash "$S/vt-draft.sh" T "replaced idea"  | grep -oE 'T-[0-9]+')
A3=$(bash "$S/vt-draft.sh" T "the replacement" | grep -oE 'T-[0-9]+')
bash "$S/vt-transition.sh" "$A1" abandoned >/dev/null
ck "abandon: removed from active board"        '! grep -q "'"$A1"'" "$VT_DIR/board.md"'
ck "abandon: recorded in abandoned.md"         'grep -q "'"$A1"'" "$VT_DIR/archive/'"$MO"'/abandoned.md"'
ck "abandon: archive note labels it abandoned" 'grep "'"$A1"'" "$VT_DIR/archive/'"$MO"'/abandoned.md" | grep -q "· abandoned"'
ck "abandon: transition logged"                'grep "'"$A1"'" "$VT_DIR/transitions.log" | grep -q "abandoned"'
bash "$S/vt-transition.sh" "$A2" superseded --by "$A3" >/dev/null
ck "supersede: removed from active board"       '! grep -q "'"$A2"'" "$VT_DIR/board.md"'
ck "supersede: records superseded-by link"      'grep "'"$A2"'" "$VT_DIR/archive/'"$MO"'/abandoned.md" | grep -q "superseded-by: '"$A3"'"'
BD=$(bash "$S/vt-draft.sh" T "old work" --backdate 2026-01-15 | grep -oE 'T-[0-9]+')
ck "backdate draft: log carries past date"      'grep "'"$BD"'" "$VT_DIR/transitions.log" | grep -q "^2026-01-15"'
bash "$S/vt-transition.sh" "$BD" abandoned --backdate 2026-01-20 >/dev/null
ck "backdate transition: filed under past month" 'grep -q "'"$BD"'" "$VT_DIR/archive/2026-01/abandoned.md"'
ck "backdate transition: log is past-dated"      'grep "'"$BD"'" "$VT_DIR/transitions.log" | grep -q "^2026-01-20"'
IB=$(bash "$S/vt-draft.sh" T "bad date" --backdate not-a-date 2>/dev/null | grep -oE 'T-[0-9]+')
ck "backdate invalid: story still created"       'grep -q "'"$IB"'" "$VT_DIR/board.md"'
DN=$(bash "$S/vt-draft.sh" T "shipped" | grep -oE 'T-[0-9]+'); bash "$S/vt-transition.sh" "$DN" done >/dev/null
ck "terminal: refuse abandon of a Done story"    '! bash "$S/vt-transition.sh" "$DN" abandoned 2>/dev/null'
ck "abandon: board stays valid (counts line)"    'grep -q "^\*\*Counts:\*\*" "$VT_DIR/board.md"'
unset VT_DIR

echo
echo "════ 11. Midweek priority reconciliation (W3, v2) ════"
W11=$(mktemp -d); export VT_DIR="$W11/.4loops"
# shellcheck source=/dev/null
source "$S/vt-priorities-lib.sh"
P1=$(bash "$S/vt-draft.sh" T "first"  | grep -oE 'T-[0-9]+')
P2=$(bash "$S/vt-draft.sh" T "second" | grep -oE 'T-[0-9]+')
bash "$S/vt-today.sh" "$P1" >/dev/null
ck "priority: today focus starts as P1"           '[ "$(read_focus today)" = "'"$P1"'" ]'
bash "$S/vt-priority.sh" add "$P2" >/dev/null
ck "priority add: appends P2 to focus"            'printf "%s" "$(read_focus today)" | grep -q "'"$P2"'"'
ck "priority add: keeps P1 in focus"              'printf "%s" "$(read_focus today)" | grep -q "'"$P1"'"'
bash "$S/vt-priority.sh" add "$P1" >/dev/null
ck "priority add: no duplicate on re-add"         '[ "$(read_focus today | grep -oE "'"$P1"'" | wc -l | tr -d " ")" = "1" ]'
ck "priority add: today stamp current (gate lift)" '[ "$(read_today_stamp)" = "$(iso_today)" ]'
P3=$(bash "$S/vt-draft.sh" T "added later" | grep -oE 'T-[0-9]+')
SINCE=$(bash "$S/vt-priority.sh" since)
ck "priority since: surfaces newly-added P3"      'printf "%s" "$SINCE" | grep -q "'"$P3"'"'
ck "priority since: omits already-focused P1"     '! printf "%s" "$SINCE" | grep -q "'"$P1"'"'
bash "$S/vt-priority.sh" set "$P3" >/dev/null
ck "priority set: replaces focus with P3 only"    '[ "$(read_focus today)" = "'"$P3"'" ]'
ck "priority: bad subcommand errors"              '! bash "$S/vt-priority.sh" bogus 2>/dev/null'
unset VT_DIR

echo
echo "════ 12. User-only overwrite — rail-owned records (W4, v2) ════"
W12=$(mktemp -d); VT="$W12/.4loops"; mkboard "$VT"; : > "$VT/.armed"; : > "$VT/transitions.log"
pj12(){ printf '{"session_id":"%s","cwd":"%s","tool_input":{"file_path":"%s"}}' "$1" "$W12" "$2"; }
g12(){ printf '%s' "$1" | bash "$H/vt-gate.sh" 2>&1; }
ck "record: Edit board.md blocked"             'O=$(g12 "$(pj12 RZ "$W12/.4loops/board.md")"); isdeny "$O"'
ck "record: Edit current-priorities blocked"   'O=$(g12 "$(pj12 RZ "$W12/.4loops/current-priorities.md")"); isdeny "$O"'
ck "record: other .4loops file allowed"        'O=$(g12 "$(pj12 RZ "$W12/.4loops/config")"); ! isdeny "$O"'
ck "record: override allows + logs"            'O=$(VT_ALLOW_RECORD_WRITE=1 g12 "$(pj12 RZ "$W12/.4loops/board.md")"); ! isdeny "$O" && grep -q VT_ALLOW_RECORD_WRITE "$VT/override.log"'
bj12(){ printf '{"session_id":"%s","cwd":"%s","tool_input":{"command":"%s"}}' "$1" "$W12" "$2"; }
bg12(){ local o r; o=$(printf '%s' "$1" | bash "$H/vt-bash-gate.sh" 2>&1); r=$?; printf '%s' "$o" | grep -q '"deny"' || [ "$r" = 2 ]; }
ck "record: sed -i board.md blocked (bash)"    'bg12 "$(bj12 RZ "sed -i s/x/y/ .4loops/board.md")"'
ck "record: echo >> board.md blocked (bash)"   'bg12 "$(bj12 RZ "echo x >> .4loops/board.md")"'
ck "record: cat board.md (read) allowed"       '! bg12 "$(bj12 RZ "cat .4loops/board.md")"'
ck "record: bash override allows board write"  '! bg12 "$(bj12 RZ "VT_ALLOW_RECORD_WRITE=1 echo x >> .4loops/board.md")"'
unset VT_DIR 2>/dev/null || true

echo
echo "════ 13. File-growth GC — latest-only markers (W5, v2) ════"
W13=$(mktemp -d); export VT_DIR="$W13/.4loops"; mkdir -p "$VT_DIR/.cleared"
# shellcheck source=/dev/null
source "$S/vt-priorities-lib.sh"
CUR=".weekly-rolled-$(week_marker_id)"
: > "$VT_DIR/$CUR"
: > "$VT_DIR/.weekly-rolled-2020-W01"; : > "$VT_DIR/.weekly-rolled-2019-W52"
: > "$VT_DIR/.prompt-nudged-$(iso_today)"; : > "$VT_DIR/.prompt-nudged-2020-01-01"
bash "$S/vt-gc.sh" >/dev/null
ck "gc: keeps current weekly-rolled marker"   '[ -f "$VT_DIR/$CUR" ]'
ck "gc: prunes old weekly-rolled markers"     '[ ! -f "$VT_DIR/.weekly-rolled-2020-W01" ] && [ ! -f "$VT_DIR/.weekly-rolled-2019-W52" ]'
ck "gc: keeps today prompt-nudged marker"     '[ -f "$VT_DIR/.prompt-nudged-$(iso_today)" ]'
ck "gc: prunes old prompt-nudged markers"     '[ ! -f "$VT_DIR/.prompt-nudged-2020-01-01" ]'
unset VT_DIR

echo
echo "════ 14. Task-arranger batch helper (W6, v2) ════"
W14=$(mktemp -d); export VT_DIR="$W14/.4loops"
TSV=$(printf 'P0\tship the thing\tdev\tbecause\t2026-07-15\nP0\tmodel the flow\tmodeling\t\t\n')
DRY=$(printf '%s\n' "$TSV" | bash "$S/vt-arrange.sh" --dry-run)
ck "arrange dry-run: previews the stories"     'printf "%s" "$DRY" | grep -q "ship the thing"'
ck "arrange dry-run: shows inferred type"      'printf "%s" "$DRY" | grep -q "type: modeling"'
ck "arrange dry-run: shows deadline"           'printf "%s" "$DRY" | grep -q "due 2026-07-15"'
ck "arrange dry-run: creates nothing"          '[ ! -f "$VT_DIR/board.md" ]'
printf '%s\n' "$TSV" | bash "$S/vt-arrange.sh" >/dev/null
ck "arrange: drafts the dev story"             'grep -q "ship the thing" "$VT_DIR/board.md"'
ck "arrange: drafts the modeling story"        'grep -q "model the flow" "$VT_DIR/board.md"'
ck "arrange: preserves type=modeling"          'grep "model the flow" "$VT_DIR/board.md" | grep -q "type: modeling"'
ck "arrange: applies deadline from TSV"        'grep "ship the thing" "$VT_DIR/board.md" | grep -q "due: 2026-07-15"'
ck "arrange: both land in Backlog (2 rows)"    '[ "$(grep -cE "ship the thing|model the flow" "$VT_DIR/board.md")" -ge 2 ]'
ck "arrange: skill is user-invoked only"       'grep -q "disable-model-invocation: true" "$PLUGIN/skills/arrange/SKILL.md"'
unset VT_DIR

echo
echo "════ 15. Capture: deadline + context-as-link (W7, v2) ════"
W15=$(mktemp -d); export VT_DIR="$W15/.4loops"
# shellcheck source=/dev/null
source "$S/vt-priorities-lib.sh"
D1=$(bash "$S/vt-draft.sh" P0 "ship by friday" "" "stories/vibe-table/15-v2-spine/README.md" --deadline 2026-07-01 | grep -oE 'P0-[0-9]+')
ck "deadline: row carries due token"          'grep "'"$D1"'" "$VT_DIR/board.md" | grep -q "due: 2026-07-01"'
ck "deadline: story_deadline reads it"        '[ "$(story_deadline "'"$D1"'")" = "2026-07-01" ]'
ck "deadline: story_title excludes due token" '[ "$(story_title "'"$D1"'")" = "ship by friday" ]'
ck "context: renders as markdown link"        'grep "'"$D1"'" "$VT_DIR/board.md" | grep -q "\[15-v2-spine\](stories/vibe-table/15-v2-spine/README.md)"'
D2=$(bash "$S/vt-draft.sh" P0 "bad deadline" --deadline notadate 2>/dev/null | grep -oE 'P0-[0-9]+')
ck "deadline: invalid dropped, story created" 'grep -q "'"$D2"'" "$VT_DIR/board.md" && [ -z "$(story_deadline "'"$D2"'")" ]'
D3=$(bash "$S/vt-draft.sh" P0 "freeform ctx" "" "just some prose not a path" | grep -oE 'P0-[0-9]+')
ck "context: free text is not linkified"      '! grep "'"$D3"'" "$VT_DIR/board.md" | grep -q "]("'
unset VT_DIR

echo
echo "════ 16. Deadline-aware drift (W8, v2) ════"
W16=$(mktemp -d); export VT_DIR="$W16/.4loops"; mkboard "$VT_DIR"; : > "$VT_DIR/transitions.log"
BOARD="$VT_DIR/board.md"; TRANSITIONS="$VT_DIR/transitions.log"; PRIORITIES="$VT_DIR/current-priorities.md"
# shellcheck source=/dev/null
source "$S/vt-priorities-lib.sh"; source "$S/vt-drift-lib.sh"
PAST=$(date -v-5d +%F 2>/dev/null || date -d '5 days ago' +%F)
SOON=$(date -v+2d +%F 2>/dev/null || date -d '2 days' +%F)
FAR=$(date -v+30d +%F 2>/dev/null || date -d '30 days' +%F)
cat >> "$BOARD" <<EOF
|  |  | [P0] **P0-300** overdue thing — due: $PAST |  |  |
|  |  | [P0] **P0-301** soon thing — due: $SOON |  |  |
|  |  | [P0] **P0-302** far thing — due: $FAR |  |  |
|  |  |  |  | [P0] **P0-303** done thing — due: $PAST |
EOF
OV=$(find_overdue)
ck "overdue: flags past-due active story"  'printf "%s" "$OV" | grep -q "P0-300"'
ck "overdue: ignores far-future story"     '! printf "%s" "$OV" | grep -q "P0-302"'
ck "overdue: ignores DONE story"           '! printf "%s" "$OV" | grep -q "P0-303"'
SOONOUT=$(find_due_soon 3)
ck "due-soon: flags story due within 3d"   'printf "%s" "$SOONOUT" | grep -q "P0-301"'
ck "due-soon: excludes far-future"         '! printf "%s" "$SOONOUT" | grep -q "P0-302"'
ck "due-soon: excludes already-overdue"    '! printf "%s" "$SOONOUT" | grep -q "P0-300"'
DR=$(render_drift)
ck "drift line: surfaces overdue"          'printf "%s" "$DR" | grep -q "overdue"'
ck "drift line: surfaces due-soon"         'printf "%s" "$DR" | grep -q "due-soon"'
unset VT_DIR

echo
echo "════ 17. Reconciliation contract — see-then-pick, structured (W9/W10, v2) ════"
ck "today: see-the-board-then-pick (not chat)"  'grep -qi "see the board, then pick" "$PLUGIN/skills/today/SKILL.md"'
ck "today: structured multi-select reconcile"   'grep -qi "structured multi-select" "$PLUGIN/skills/today/SKILL.md"'
ck "today: prints the board once"               'grep -qi "print the board ONCE" "$PLUGIN/skills/today/SKILL.md"'
ck "today: surfaces overdue / due-soon"         'grep -qi "overdue" "$PLUGIN/skills/today/SKILL.md"'
ck "week: wider lens, runs first"               'grep -qi "wider lens" "$PLUGIN/skills/week/SKILL.md"'
ck "week: structured multi-select reconcile"    'grep -qi "structured multi-select" "$PLUGIN/skills/week/SKILL.md"'
ck "priority: in-between cadence"               'grep -qi "in-between" "$PLUGIN/skills/priority/SKILL.md"'
ck "arrange: user-invoked only (capture)"       'grep -q "disable-model-invocation: true" "$PLUGIN/skills/arrange/SKILL.md"'
ck "configure: pin-the-board onboarding tip"    'grep -qi "pin" "$PLUGIN/skills/configure/SKILL.md"'

echo "════ RESULT: $P passed, $F failed ════"
[ "$F" -eq 0 ]