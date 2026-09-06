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
# This suite tests priority mechanics, not the week-before-today rule → bypass the week guard.
VT_ALLOW_TODAY_FIRST=1 bash "$S/vt-today.sh" "$P1" >/dev/null
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
ck "record: bash INLINE override IGNORED (blocked)" 'bg12 "$(bj12 RZ "VT_ALLOW_RECORD_WRITE=1 echo x >> .4loops/board.md")"'
ck "record: bash ENV override allowed"         '! { printf "%s" "$(bj12 RZ "echo x >> .4loops/board.md")" | VT_ALLOW_RECORD_WRITE=1 bash "$H/vt-bash-gate.sh" 2>&1 | grep -q "\"deny\""; }'
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
ck "capture: skill is user-invoked only"       'grep -q "disable-model-invocation: true" "$PLUGIN/skills/capture/SKILL.md"'
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
echo "════ 17. Orientation contract — priorities first, board is a state check (W9/W10 v2 → v2.5 Real C) ════"
ck "today: daily orientation, not board reconciliation" 'grep -qi "daily \*\*orientation\*\*" "$PLUGIN/skills/today/SKILL.md"'
ck "today: --orient is the one print (no board dump)"  'grep -q "vt-today.sh\" --orient" "$PLUGIN/skills/today/SKILL.md" && ! grep -q "vt-render.sh\"$" "$PLUGIN/skills/today/SKILL.md"'
ck "today: board is a state check only"                'grep -qi "state check" "$PLUGIN/skills/today/SKILL.md"'
ck "today: surfaces overdue / due-soon"                'grep -qi "overdue" "$PLUGIN/skills/today/SKILL.md"'
ck "today: free text lands in the store (no detour)"   'grep -qi "free text becomes a store item" "$PLUGIN/skills/today/SKILL.md"'
ck "week: wider lens, runs first"                      'grep -qi "wider lens" "$PLUGIN/skills/week/SKILL.md"'
ck "week: --orient print + honest prune"               'grep -q "vt-week.sh\" --orient" "$PLUGIN/skills/week/SKILL.md" && grep -qi "honest ending" "$PLUGIN/skills/week/SKILL.md"'
ck "today/week: no board multi-select reconcile ritual" '! grep -qi "structured multi-select" "$PLUGIN/skills/today/SKILL.md" && ! grep -qi "structured multi-select" "$PLUGIN/skills/week/SKILL.md"'
ck "prioritize: focus-only escape"              'grep -qi "focus-only" "$PLUGIN/skills/prioritize/SKILL.md"'
ck "prioritize: mid-day direct add + drop"      'grep -q "vt-priority.sh\" drop" "$PLUGIN/skills/prioritize/SKILL.md" && grep -q "week add" "$PLUGIN/skills/prioritize/SKILL.md"'
ck "capture: user-invoked only"                 'grep -q "disable-model-invocation: true" "$PLUGIN/skills/capture/SKILL.md"'
ck "configure: pin-the-board onboarding tip"    'grep -qi "pin" "$PLUGIN/skills/configure/SKILL.md"'

echo "════ 18. Dense-grid cell-scoping — lookups must not bleed across co-located cells (regression) ════"
# The dense grid packs MANY stories onto one physical line. A per-LINE scan grabs a
# neighbour cell's due:/type: token (caught live in the beta sandbox: drift mis-read every
# deadline). story_type/story_deadline must isolate the story's own |-delimited CELL.
W18=$(mktemp -d); export VT_DIR="$W18/.4loops"; mkboard "$VT_DIR"; : > "$VT_DIR/transitions.log"
BOARD="$VT_DIR/board.md"; TRANSITIONS="$VT_DIR/transitions.log"; PRIORITIES="$VT_DIR/current-priorities.md"
# shellcheck source=/dev/null
source "$S/vt-priorities-lib.sh"; source "$S/vt-drift-lib.sh"
DPAST=$(date -v-5d +%F 2>/dev/null || date -d '5 days ago' +%F)
DFAR=$(date -v+30d +%F 2>/dev/null || date -d '30 days' +%F)
# ONE physical line, five co-located cells: Backlog | Planning | InProgress | Testing | Done
cat >> "$BOARD" <<EOF
| [P0] **P0-400** alpha — type: modeling — due: $DFAR | [P0] **P0-401** beta — due: $DPAST | [P0] **P0-402** gamma no-due | [P0] **P0-404** epsilon — due: $DPAST | [P0] **P0-403** delta done — due: $DPAST |
EOF
ck "dense: deadline scoped to own cell (not neighbour)" '[ "$(story_deadline P0-400)" = "'"$DFAR"'" ]'
ck "dense: no-due story stays empty despite neighbours" '[ -z "$(story_deadline P0-402)" ]'
ck "dense: 2nd-cell deadline reads its own date"        '[ "$(story_deadline P0-401)" = "'"$DPAST"'" ]'
ck "dense: type scoped to own cell"                     '[ "$(story_type P0-400)" = "modeling" ]'
ck "dense: neighbour of modeling stays dev"             '[ "$(story_type P0-401)" = "dev" ]'
OV18=$(find_overdue)
ck "dense: overdue flags the right active stories"      'printf "%s" "$OV18" | grep -q "P0-401" && printf "%s" "$OV18" | grep -q "P0-404"'
ck "dense: overdue ignores far-future co-located"       '! printf "%s" "$OV18" | grep -q "P0-400"'
ck "dense: overdue ignores no-due co-located"           '! printf "%s" "$OV18" | grep -q "P0-402"'
ck "dense: overdue ignores DONE co-located"             '! printf "%s" "$OV18" | grep -q "P0-403"'
unset VT_DIR

echo
echo "════ 19. v2.2 rules — config-first · week-before-today · user-only ════"
# WEEK-BEFORE-TODAY (hard, rail-level): on a fresh ISO week /today refuses until /week ran.
W19=$(mktemp -d); export VT_DIR="$W19/.4loops"; mkboard "$VT_DIR"; : > "$VT_DIR/transitions.log"; touch "$VT_DIR/config"
Z1=$(bash "$S/vt-draft.sh" Z "thing" | grep -oE 'Z-[0-9]+')
ck "week-first: vt-today REFUSES on a fresh week" '! bash "$S/vt-today.sh" "'"$Z1"'" 2>/dev/null'
ck "week-first: VT_ALLOW_TODAY_FIRST bypass works" 'VT_ALLOW_TODAY_FIRST=1 bash "$S/vt-today.sh" "'"$Z1"'" >/dev/null 2>&1'
unset VT_DIR
W19b=$(mktemp -d); export VT_DIR="$W19b/.4loops"; mkboard "$VT_DIR"; : > "$VT_DIR/transitions.log"; touch "$VT_DIR/config"
Z2=$(bash "$S/vt-draft.sh" Z "thing" | grep -oE 'Z-[0-9]+'); bash "$S/vt-week.sh" "$Z2" >/dev/null
ck "week-first: vt-today SUCCEEDS after /week"    'bash "$S/vt-today.sh" "'"$Z2"'" >/dev/null 2>&1'
unset VT_DIR
# CONFIG-FIRST: every board command's skill checks for .4loops/config in step 0.
ck "config-first: /today checks config"          'grep -q "\.4loops/config" "$PLUGIN/skills/today/SKILL.md"'
ck "config-first: /week checks config"           'grep -q "\.4loops/config" "$PLUGIN/skills/week/SKILL.md"'
ck "config-first: /sync checks config"            'grep -q "\.4loops/config" "$PLUGIN/skills/sync/SKILL.md"'
ck "config-first: /capture checks config"        'grep -q "\.4loops/config" "$PLUGIN/skills/capture/SKILL.md"'
ck "config-first: /prioritize checks config"     'grep -q "\.4loops/config" "$PLUGIN/skills/prioritize/SKILL.md"'
ck "config-first: /manage checks config"         'grep -q "\.4loops/config" "$PLUGIN/skills/manage/SKILL.md"'
# USER-ONLY: every board-mutating skill is disable-model-invocation; /board stays read-only-invocable.
ck "user-only: /sync"                             'grep -q "disable-model-invocation: true" "$PLUGIN/skills/sync/SKILL.md"'
ck "user-only: /capture"                         'grep -q "disable-model-invocation: true" "$PLUGIN/skills/capture/SKILL.md"'
ck "user-only: /prioritize"                      'grep -q "disable-model-invocation: true" "$PLUGIN/skills/prioritize/SKILL.md"'
ck "user-only: /manage"                          'grep -q "disable-model-invocation: true" "$PLUGIN/skills/manage/SKILL.md"'
ck "user-only: /today"                           'grep -q "disable-model-invocation: true" "$PLUGIN/skills/today/SKILL.md"'
ck "user-only: /week"                            'grep -q "disable-model-invocation: true" "$PLUGIN/skills/week/SKILL.md"'
ck "user-only: /configure"                       'grep -q "disable-model-invocation: true" "$PLUGIN/skills/configure/SKILL.md"'
ck "user-only: /board stays model-invocable"     '! grep -q "disable-model-invocation" "$PLUGIN/skills/board/SKILL.md"'
# GATE MESSAGES must not teach the AGENT to self-bypass (it should stop + have the user reconcile).
ck "gate msg: agent told not to work around"     'grep -q "do NOT work around the gate yourself" "$S/vt-guard-lib.sh"'
ck "gate msg: bypass is the USER's decision"     'grep -q "Bypassing is the USER" "$S/vt-guard-lib.sh"'
ck "gate msg: no agent-actionable bypass hint"   '! grep -q "re-run prefixed with VT_ALLOW" "$S/vt-guard-lib.sh"'
ck "record msg: agent told not to hand-edit"     'grep -q "Do NOT hand-edit them yourself" "$S/vt-guard-lib.sh"'

echo
echo "════ 20. /nav + priority-annotated render (v2.2) ════"
ck "sync: operate-never-simulate contract"        'grep -qi "never simulate\|Re-render as proof" "$PLUGIN/skills/sync/SKILL.md"'
ck "sync: opens on the annotated board"           'grep -q -- "--priorities" "$PLUGIN/skills/sync/SKILL.md"'
W20=$(mktemp -d); export VT_DIR="$W20/.4loops"; mkboard "$VT_DIR"; : > "$VT_DIR/transitions.log"; touch "$VT_DIR/config"
PAST20=$(date -v-3d +%F 2>/dev/null || date -d '3 days ago' +%F)
SOON20=$(date -v+1d +%F 2>/dev/null || date -d '1 day' +%F)
F1=$(bash "$S/vt-draft.sh" N "focus due soon" "" "" --deadline "$SOON20" | grep -oE 'N-[0-9]+')
F2=$(bash "$S/vt-draft.sh" N "overdue thing"  "" "" --deadline "$PAST20" | grep -oE 'N-[0-9]+')
bash "$S/vt-week.sh" "$F1" >/dev/null; bash "$S/vt-today.sh" "$F1" >/dev/null
PRI20=$(bash "$S/vt-render.sh" --priorities)
ck "priorities: ★ on the focused story"          'printf "%s" "$PRI20" | grep "'"$F1"'" | grep -q "★"'
ck "priorities: ⏳ on the due-soon story"          'printf "%s" "$PRI20" | grep "'"$F1"'" | grep -q "⏳"'
ck "priorities: ! on the overdue story"          'printf "%s" "$PRI20" | grep "'"$F2"'" | grep -q "!"'
ck "priorities: no ★ on the non-focused story"   '! { printf "%s" "$PRI20" | grep "'"$F2"'" | grep -q "★"; }'
ck "priorities: default render has no ★/⏳ overlay" '! bash "$S/vt-render.sh" | grep -qE "★|⏳"'
unset VT_DIR

echo
echo "════ 21. Gate is un-bypassable by the agent (env-only override) ════"
GATE="$PLUGIN/hooks/vt-bash-gate.sh"
W21=$(mktemp -d); export VT_DIR="$W21/.4loops"; mkdir -p "$W21/projects/demo/content"
bash "$S/vt-config.sh" week-start mon >/dev/null
bash "$S/vt-config.sh" gated "projects/demo/content/*" >/dev/null
GID=$(bash "$S/vt-draft.sh" D "task" | grep -oE 'D-[0-9]+')
bash "$S/vt-week.sh" "$GID" >/dev/null; bash "$S/vt-today.sh" "$GID" >/dev/null
gy=$(date -v-1d +%F 2>/dev/null || date -d yesterday +%F)   # backdate Today → gate ACTIVE
sed -i.bak -E "s/## Today \([0-9-]+\)/## Today ($gy)/" "$VT_DIR/current-priorities.md"; rm -f "$VT_DIR/current-priorities.md.bak"
: > "$VT_DIR/.armed"
gjson() { printf '{"tool_input":{"command":"%s"},"cwd":"%s","session_id":"s1"}' "$1" "$W21"; }
ck "gate: AGENT inline override is IGNORED (blocked)"  'gjson "VT_ALLOW_STALE_GATE=1 echo x > projects/demo/content/post.md" | bash "$GATE" 2>&1 | grep -q deny'
ck "gate: plain gated write is blocked"                'gjson "echo x > projects/demo/content/post.md" | bash "$GATE" 2>&1 | grep -q deny'
ck "gate: USER env override is honored (allowed)"      '! { gjson "echo x > projects/demo/content/post.md" | VT_ALLOW_STALE_GATE=1 bash "$GATE" 2>&1 | grep -q deny; }'
ck "gate: bash-gate no longer parses override from cmd" '! grep -q "cmd.*in.*VT_ALLOW_STALE_GATE=1" "$PLUGIN/hooks/vt-bash-gate.sh"'
unset VT_DIR

echo
echo "════ 22. Spine seam: branch binding (build-rail foundation) ════"
W22=$(mktemp -d); export VT_DIR="$W22/.4loops"
source "$S/vt-priorities-lib.sh"
# --branch at draft sets the field; a plain draft stays branch-free (v1/v2 back-compat).
BID=$(bash "$S/vt-draft.sh" P0 "rail seam" "" "" --branch feat/seam | grep -oE 'P0-[0-9]+')
NID=$(bash "$S/vt-draft.sh" P0 "no branch here"                      | grep -oE 'P0-[0-9]+')
ck "draft --branch: cell carries the field"       'grep -q "branch: feat/seam" "$VT_DIR/board.md"'
ck "draft --branch: story_branch reads it"        '[ "$(story_branch "$BID")" = "feat/seam" ]'
ck "draft --branch: reverse story_id_by_branch"   '[ "$(story_id_by_branch feat/seam)" = "'"$BID"'" ]'
ck "draft default: branch-free (back-compat)"     '[ -z "$(story_branch "$NID")" ]'
ck "branch: stripped from story_title"            '! printf "%s" "$(story_title "$BID")" | grep -q branch'
ck "branch: hidden in compact board view"         '! bash "$S/vt-render.sh" | grep -q "branch:"'
ck "branch: shown in single-state FULL view"      'bash "$S/vt-render.sh" backlog | grep -q "branch: feat/seam"'
# Bind at the in-progress transition (the chosen UX: branch known when work starts).
TID=$(bash "$S/vt-draft.sh" P0 "bind on start" | grep -oE 'P0-[0-9]+')
bash "$S/vt-transition.sh" "$TID" in-progress --branch feat/start >/dev/null
ck "transition --branch: binds on the move"       '[ "$(story_branch "$TID")" = "feat/start" ]'
ck "transition --branch: story moved too"         '[ "$(story_state "$TID")" = "in-progress" ]'
# Re-binding replaces the old value (no duplicate token, old branch gone).
bash "$S/vt-transition.sh" "$TID" testing --branch feat/renamed >/dev/null
ck "transition --branch: re-bind sets new"        '[ "$(story_branch "$TID")" = "feat/renamed" ]'
ck "transition --branch: old binding removed"     '! grep -q "feat/start" "$VT_DIR/board.md"'
# A plain transition (no --branch) preserves the binding byte-for-byte.
bash "$S/vt-transition.sh" "$TID" done >/dev/null
ck "transition (no flag): branch preserved"       '[ "$(story_branch "$TID")" = "feat/renamed" ]'
# A pipe in the branch name is sanitized so it can't split the cell.
PID=$(bash "$S/vt-draft.sh" P0 "pipe branch" "" "" --branch 'a|b' | grep -oE 'P0-[0-9]+')
ck "draft --branch: pipe sanitized (no raw |)"    '! printf "%s" "$(story_branch "$PID")" | grep -q "[|]"'
unset VT_DIR


echo "════ 23. v2.5 Track A: detached store + expiry state machine ════"
W23=$(mktemp -d); export VT_DIR="$W23/.4loops"
bash "$S/vt-init.sh" >/dev/null
# Capture does not touch board Backlog
BOARD_BEFORE=$(wc -l < "$VT_DIR/board.md" | tr -d ' ')
printf 'P0\tStore happy path item\tdev\tpacket-002 evidence\t2026-09-20\n' | bash "$S/vt-store-capture.sh" >/tmp/vt-store-cap-out.txt
CAP_ID=$(awk '/^captured:/{print $2; exit}' /tmp/vt-store-cap-out.txt)
BOARD_AFTER=$(wc -l < "$VT_DIR/board.md" | tr -d ' ')
ck "store-capture: writes CAP id"                 '[ -n "'"$CAP_ID"'" ] && [ -f "$VT_DIR/store/items/'"$CAP_ID"'" ]'
ck "store-capture: state=captured"                'grep -q "^state=captured$" "$VT_DIR/store/items/'"$CAP_ID"'"'
ck "store-capture: board unchanged (no Backlog dump)" '[ "'"$BOARD_BEFORE"'" = "'"$BOARD_AFTER"'" ]'
# Happy path: captured → active
bash "$S/vt-store-expire.sh" --activate-only >/dev/null
ck "store-expire: captured → active"              'grep -q "^state=active$" "$VT_DIR/store/items/'"$CAP_ID"'"'
# Expiry path: force expire → clear
bash "$S/vt-store-expire.sh" --force-expire "$CAP_ID" >/dev/null
ck "store-expire: active → expired (force)"       'grep -q "^state=expired$" "$VT_DIR/store/items/'"$CAP_ID"'"'
bash "$S/vt-store-expire.sh" --clear-id "$CAP_ID" >/dev/null
ck "store-expire: expired → cleared (moved)"      '[ -f "$VT_DIR/store/cleared/'"$CAP_ID"'" ] && grep -q "^state=cleared$" "$VT_DIR/store/cleared/'"$CAP_ID"'"'
ck "store: transitions.log has full chain"        'grep -q "captured" "$VT_DIR/store/transitions.log" && grep -q "active" "$VT_DIR/store/transitions.log" && grep -q "expired" "$VT_DIR/store/transitions.log" && grep -q "cleared" "$VT_DIR/store/transitions.log"'
# TTL path: backdated active item expires on tick
printf 'P0\tTTL expiry item\tdev\told capture\t\n' | bash "$S/vt-store-capture.sh" >/tmp/vt-store-cap2.txt
CAP2=$(awk '/^captured:/{print $2; exit}' /tmp/vt-store-cap2.txt)
bash "$S/vt-store-expire.sh" --activate "$CAP2" >/dev/null
# Rewrite captured_at to 30 days ago (UTC)
OLD=$(date -u -v-30d +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d '30 days ago' +"%Y-%m-%dT%H:%M:%SZ")
awk -v o="$OLD" 'BEGIN{FS=OFS="="} $1=="captured_at"{$2=o} {print}' "$VT_DIR/store/items/$CAP2" > "$VT_DIR/store/items/$CAP2.tmp" && mv "$VT_DIR/store/items/$CAP2.tmp" "$VT_DIR/store/items/$CAP2"
VT_STORE_TTL_DAYS=14 bash "$S/vt-store-expire.sh" --expire-only >/dev/null
ck "store-expire: TTL active → expired"           'grep -q "^state=expired$" "$VT_DIR/store/items/'"$CAP2"'"'
# Rail tier wiring
source "$S/vt-guard-lib.sh"
ck "rail-tier: vt-store-capture is mutate"        '[ "$(vt_rail_tier vt-store-capture)" = "mutate" ]'
ck "rail-tier: vt-store-list is readonly"         '[ "$(vt_rail_tier vt-store-list)" = "readonly" ]'
ck "rail-record: store path protected"            'vt_is_rail_record "$VT_DIR/store/items/x"'
unset VT_DIR


echo "════ 24. v2.5 Track B: scope promote (capacity only, no board) ════"
W24=$(mktemp -d); export VT_DIR="$W24/.4loops"
bash "$S/vt-init.sh" >/dev/null
printf 'P0\tScope happy path\tdev\tpacket-003\t2026-09-20\n' | bash "$S/vt-store-capture.sh" >/tmp/vt-scope-cap-out.txt
SID=$(awk '/^captured:/{print $2; exit}' /tmp/vt-scope-cap-out.txt)
bash "$S/vt-store-expire.sh" --activate "$SID" >/dev/null
BOARD_SHA_BEFORE=$(shasum -a 256 "$VT_DIR/board.md" | awk '{print $1}')
bash "$S/vt-scope-promote.sh" "$SID" \
  --deadline 2026-09-20 \
  --impact "unblocks dogfood" \
  --resource "1d" >/tmp/vt-scope-promo-out.txt
BOARD_SHA_AFTER=$(shasum -a 256 "$VT_DIR/board.md" | awk '{print $1}')
ck "scope-promote: writes tasks/P0/<id>.md"       '[ -f "$VT_DIR/tasks/P0/'"$SID"'.md" ]'
ck "scope-promote: capacity deadline present"     'grep -q "^deadline: 2026-09-20$" "$VT_DIR/tasks/P0/'"$SID"'.md"'
ck "scope-promote: capacity impact present"       'grep -q "^impact: unblocks dogfood$" "$VT_DIR/tasks/P0/'"$SID"'.md"'
ck "scope-promote: capacity resource present"     'grep -q "^resource: 1d$" "$VT_DIR/tasks/P0/'"$SID"'.md"'
ck "scope-promote: no modeling section"           '! grep -qiE "^##[[:space:]]*(Model|Modeling|Implementation[ -]?[Pp]lan|Architecture|Design)" "$VT_DIR/tasks/P0/'"$SID"'.md"'
ck "scope-promote: board.md hash unchanged"       '[ "'"$BOARD_SHA_BEFORE"'" = "'"$BOARD_SHA_AFTER"'" ]'
ck "scope-promote: store annotated scoped_at"     'grep -q "^scoped_at=" "$VT_DIR/store/items/'"$SID"'"'
ck "scope-promote: store state still active"      'grep -q "^state=active$" "$VT_DIR/store/items/'"$SID"'"'
# Illegal: captured (not active)
printf 'P0\tNot active yet\tdev\tx\t\n' | bash "$S/vt-store-capture.sh" >/tmp/vt-scope-cap2.txt
SID2=$(awk '/^captured:/{print $2; exit}' /tmp/vt-scope-cap2.txt)
if bash "$S/vt-scope-promote.sh" "$SID2" --deadline 2026-09-21 --impact "x" --resource "1h" >/tmp/vt-scope-bad.txt 2>/tmp/vt-scope-bad.err; then
  BAD_RC=0
else
  BAD_RC=$?
fi
ck "scope-promote: refuse non-active"             '[ "'"$BAD_RC"'" != "0" ]'
# Illegal: missing capacity flag
if bash "$S/vt-scope-promote.sh" "$SID" --deadline 2026-09-20 --impact "only" >/dev/null 2>&1; then MISSING_RC=0; else MISSING_RC=$?; fi
ck "scope-promote: refuse missing resource"       '[ "'"$MISSING_RC"'" != "0" ]'
# Double-promote without --force fails; with --force ok
if bash "$S/vt-scope-promote.sh" "$SID" --deadline 2026-09-22 --impact "retry" --resource "2d" >/dev/null 2>&1; then DUP_RC=0; else DUP_RC=$?; fi
ck "scope-promote: refuse duplicate without --force" '[ "'"$DUP_RC"'" != "0" ]'
bash "$S/vt-scope-promote.sh" "$SID" --deadline 2026-09-22 --impact "retry" --resource "2d" --force >/dev/null
ck "scope-promote: --force re-promote"            'grep -q "^deadline: 2026-09-22$" "$VT_DIR/tasks/P0/'"$SID"'.md"'
# list + read
ck "scope-list: shows promoted id"                'bash "$S/vt-scope-list.sh" P0 | grep -q "'"$SID"'"'
ck "scope-read: prints doc"                       'bash "$S/vt-scope-read.sh" "'"$SID"'" | grep -q "Capacity judgment only"'
# Rail tier wiring
source "$S/vt-guard-lib.sh"
ck "rail-tier: vt-scope-promote is mutate"        '[ "$(vt_rail_tier vt-scope-promote)" = "mutate" ]'
ck "rail-tier: vt-scope-list is readonly"         '[ "$(vt_rail_tier vt-scope-list)" = "readonly" ]'
ck "rail-tier: vt-scope-read is readonly"         '[ "$(vt_rail_tier vt-scope-read)" = "readonly" ]'
ck "rail-record: tasks path protected"            'vt_is_rail_record "$VT_DIR/tasks/P0/x.md"'
# cap allows scope
ck "cap-allows: scope covers mutate"              'vt_cap_allows scope mutate'
unset VT_DIR


echo "════ 25. v2.5 Track C: priority levers + thin prioritize ════"
W25=$(mktemp -d); export VT_DIR="$W25/.4loops"
bash "$S/vt-init.sh" >/dev/null
BOARD_SHA_BEFORE=$(shasum -a 256 "$VT_DIR/board.md" | awk '{print $1}')
# default lever=later
printf 'P0\tDefault lever item\tdev\tpacket-004\t2026-09-20\n' | bash "$S/vt-store-capture.sh" >/tmp/vt-lever-cap1.txt
L1=$(awk '/^captured:/{print $2; exit}' /tmp/vt-lever-cap1.txt)
ck "lever-capture: default lever=later"           'grep -q "^lever=later$" "$VT_DIR/store/items/'"$L1"'"'
# explicit today + urgent
printf 'P0\tToday item\tdev\tx\ttoday\n' | bash "$S/vt-store-capture.sh" >/tmp/vt-lever-cap2.txt
L2=$(awk '/^captured:/{print $2; exit}' /tmp/vt-lever-cap2.txt)
printf 'P0\tUrgent item\tdev\tx\turgent\n' | bash "$S/vt-store-capture.sh" >/tmp/vt-lever-cap3.txt
L3=$(awk '/^captured:/{print $2; exit}' /tmp/vt-lever-cap3.txt)
ck "lever-capture: explicit today"                'grep -q "^lever=today$" "$VT_DIR/store/items/'"$L2"'"'
ck "lever-capture: explicit urgent"               'grep -q "^lever=urgent$" "$VT_DIR/store/items/'"$L3"'"'
# due + lever (field5=date, field6=lever)
printf 'P0\tDated today\tdev\tx\t2026-09-21\ttoday\n' | bash "$S/vt-store-capture.sh" >/tmp/vt-lever-cap4.txt
L4=$(awk '/^captured:/{print $2; exit}' /tmp/vt-lever-cap4.txt)
ck "lever-capture: due+lever today"               'grep -q "^lever=today$" "$VT_DIR/store/items/'"$L4"'" && grep -q "^deadline=2026-09-21$" "$VT_DIR/store/items/'"$L4"'"'
# batch --lever
printf 'P0\tBatch urgent\tdev\tx\t\n' | bash "$S/vt-store-capture.sh" --lever urgent >/tmp/vt-lever-cap5.txt
L5=$(awk '/^captured:/{print $2; exit}' /tmp/vt-lever-cap5.txt)
ck "lever-capture: --lever batch urgent"          'grep -q "^lever=urgent$" "$VT_DIR/store/items/'"$L5"'"'
# list/filter by lever (capture then grep — avoid pipefail SIGPIPE with grep -q)
LIST_TODAY=$(bash "$S/vt-store-list.sh" today)
LIST_LATER=$(bash "$S/vt-store-list.sh" later)
LIST_URGENT=$(bash "$S/vt-store-list.sh" --lever urgent)
ck "lever-list: filter today"                     'printf "%s" "$LIST_TODAY" | grep -q "'"$L2"'"'
ck "lever-list: filter later"                     'printf "%s" "$LIST_LATER" | grep -q "'"$L1"'"'
ck "lever-list: --lever urgent"                   'printf "%s" "$LIST_URGENT" | grep -q "'"$L3"'"'
# change lever without board writes
bash "$S/vt-store-lever.sh" "$L1" urgent >/tmp/vt-lever-chg.txt
ck "lever-change: later → urgent"                 'grep -q "^lever=urgent$" "$VT_DIR/store/items/'"$L1"'"'
# pull to today
bash "$S/vt-store-lever.sh" today "$L1" "$L3" >/tmp/vt-lever-today.txt
ck "lever-pull: L1 → today"                       'grep -q "^lever=today$" "$VT_DIR/store/items/'"$L1"'"'
ck "lever-pull: L3 → today"                       'grep -q "^lever=today$" "$VT_DIR/store/items/'"$L3"'"'
BOARD_SHA_AFTER=$(shasum -a 256 "$VT_DIR/board.md" | awk '{print $1}')
ck "lever: board.md hash unchanged"               '[ "'"$BOARD_SHA_BEFORE"'" = "'"$BOARD_SHA_AFTER"'" ]'
# illegal lever
if bash "$S/vt-store-lever.sh" "$L2" someday >/dev/null 2>&1; then BAD_LEV=0; else BAD_LEV=$?; fi
ck "lever-change: refuse invalid lever"           '[ "'"$BAD_LEV"'" != "0" ]'
# transitions log records lever edges
ck "lever: transitions.log has lever edges"       'grep -q "lever:" "$VT_DIR/store/transitions.log"'
# rail tiers
source "$S/vt-guard-lib.sh"
ck "rail-tier: vt-store-lever is mutate"          '[ "$(vt_rail_tier vt-store-lever)" = "mutate" ]'
ck "rail-tier: vt-store-list still readonly"      '[ "$(vt_rail_tier vt-store-list)" = "readonly" ]'
ck "cap-allows: prioritize covers mutate"         'vt_cap_allows prioritize mutate'
# missing lever field on legacy item → later
printf 'id=CAP-LEG\nproject=P0\ntitle=Legacy\ntype=dev\nwhy=\ndeadline=\nstate=active\ncaptured_at=2026-09-06T00:00:00Z\nactivated_at=2026-09-06T00:00:00Z\nexpired_at=\ncleared_at=\n' > "$VT_DIR/store/items/CAP-LEG"
ck "lever-legacy: missing field reads as later"   '[ "$(bash -c "source \"'"$S"'/vt-store-lib.sh\"; vt_store_get_lever \"$VT_DIR/store/items/CAP-LEG\"")" = "later" ]'
unset VT_DIR

echo "════ 26. v2.5 Real C: living priorities — orient · direct add · carry-forward · gate=orientation ════"
W26=$(mktemp -d); export VT_DIR="$W26/.4loops"
D1=$(date -v-1d +%F 2>/dev/null || date -d 'yesterday' +%F)
bash "$S/vt-init.sh" >/dev/null
bash "$S/vt-config.sh" project P0 "dev-os" dev-os >/dev/null
bash "$S/vt-config.sh" week-start mon >/dev/null
bash "$S/vt-draft.sh" P0 "Board story" "why" "" >/dev/null
bash "$S/vt-transition.sh" P0-001 in-progress >/dev/null
printf 'P0\tUrgent cap\tdev\tx\turgent\n'         | bash "$S/vt-store-capture.sh" >/dev/null   # CAP-001
printf 'P0\tToday cap\tdev\tx\ttoday\n'           | bash "$S/vt-store-capture.sh" >/dev/null   # CAP-002
printf 'P0\tDue this week\tdev\tx\t%s\n' "$TODAY" | bash "$S/vt-store-capture.sh" >/dev/null   # CAP-003 later, due today
printf 'P0\tParked\tdev\tx\t\n'                   | bash "$S/vt-store-capture.sh" >/dev/null   # CAP-004 later
B26=$(shasum -a 256 "$VT_DIR/board.md" | awk '{print $1}')
# week orientation: board in-progress → urgent → today → due-this-week; later is a count
WO=$(bash "$S/vt-week.sh" --orient)
ck "week --orient: suggests board work, urgent, today, due-this-week" 'printf "%s" "$WO" | grep -q "^SUGGESTED_FOCUS: P0-001 CAP-001 CAP-002 CAP-003$"'
ck "week --orient: later is a count, not a dump"                      'printf "%s" "$WO" | grep -q "later: 2 parked"'
ck "week --orient: titles + state tags"                               'printf "%s" "$WO" | grep -q "CAP-001  Urgent cap  \[store·urgent\]"'
# week set with a board ID, a CAP, and free text → free text lands in the store (lever=later, active)
bash "$S/vt-week.sh" P0-001 CAP-001 "New week anchor" >/tmp/vt26-week.txt 2>&1
ck "week set: free text → store item, lever=later"  'grep -q "^lever=later$" "$VT_DIR/store/items/CAP-005" && grep -q "^state=active$" "$VT_DIR/store/items/CAP-005"'
ck "week set: focus holds board + CAP + new item"   'grep -q "^Focus: P0-001 · CAP-001 · CAP-005$" "$VT_DIR/current-priorities.md"'
ck "week set: logged to priorities.log"             'grep -q "	week	P0-001 CAP-001 CAP-005	week$" "$VT_DIR/priorities.log"'
# today orientation: no previous focus → board in-progress, then urgent, then today; week anchors marked
TO=$(bash "$S/vt-today.sh" --orient)
ck "today --orient: suggested = board in-progress + urgent + today" 'printf "%s" "$TO" | grep -q "^SUGGESTED_FOCUS: P0-001 CAP-001 CAP-002$"'
ck "today --orient: shows how today meets the week"                 'printf "%s" "$TO" | grep -q "P0-001  Board story  \[in-progress\]  ← in suggested today"'
ck "today --orient: first run stamp"                                'printf "%s" "$TO" | grep -q "Today stamp: none (first run)"'
# today set: CAP + free text → new CAP lever=today; CAP-001 urgent→today; CAP-002 (today, left out) → later
bash "$S/vt-today.sh" CAP-001 "Fix login bug" >/tmp/vt26-today.txt 2>&1
ck "today set: free text → store item, lever=today"    'grep -q "^lever=today$" "$VT_DIR/store/items/CAP-006" && grep -q "^state=active$" "$VT_DIR/store/items/CAP-006"'
ck "today set: focus line + titled items"              'grep -q "^Focus: CAP-001 · CAP-006$" "$VT_DIR/current-priorities.md" && grep -q "^- CAP-006  Fix login bug  \[store·today\]$" "$VT_DIR/current-priorities.md"'
ck "today set: committed CAP urgent → today"           'grep -q "^lever=today$" "$VT_DIR/store/items/CAP-001"'
ck "today set: left-out today item → later (logged)"   'grep -q "^lever=later$" "$VT_DIR/store/items/CAP-002" && grep -q "CAP-002 | lever:today → lever:later | dropped-from-today" "$VT_DIR/store/transitions.log"'
ck "today set: gate clear (today + week fresh)"        '! bash -c "cd \"$W26\" && source \"$S/vt-guard-lib.sh\" && vt_gate_active"'
# mid-day direct add / drop / week add
bash "$S/vt-priority.sh" add "Mid-day surprise" >/tmp/vt26-add.txt 2>&1
ck "priority add: free text → CAP lever=today, in focus"  'grep -q "^lever=today$" "$VT_DIR/store/items/CAP-007" && grep -q "^Focus: CAP-001 · CAP-006 · CAP-007$" "$VT_DIR/current-priorities.md"'
bash "$S/vt-priority.sh" drop CAP-001 >/tmp/vt26-drop.txt 2>&1
ck "priority drop: out of focus, CAP → later"             'grep -q "^Focus: CAP-006 · CAP-007$" "$VT_DIR/current-priorities.md" && grep -q "^lever=later$" "$VT_DIR/store/items/CAP-001"'
bash "$S/vt-priority.sh" week add CAP-002 >/tmp/vt26-wadd.txt 2>&1
ck "priority week add: anchors grow, lever untouched"     'grep -q "^Focus: P0-001 · CAP-001 · CAP-005 · CAP-002$" "$VT_DIR/current-priorities.md" && grep -q "^lever=later$" "$VT_DIR/store/items/CAP-002"'
bash "$S/vt-priority.sh" --project P0 add "Project item" >/dev/null 2>&1
ck "priority add --project: key honored"                  'grep -q "^project=P0$" "$VT_DIR/store/items/CAP-008"'
bash "$S/vt-priority.sh" add P0-999 >/dev/null 2>/tmp/vt26-warn.txt
ck "priority add: unknown ID kept, warned"                'grep -q "P0-999" "$VT_DIR/current-priorities.md" && grep -q "not on the board or in the store" /tmp/vt26-warn.txt'
bash "$S/vt-priority.sh" drop P0-999 >/dev/null 2>&1
SINCE=$(bash "$S/vt-priority.sh" since)
ck "priority since: store items landed since stamp"       'printf "%s" "$SINCE" | grep -q "CAP-003  Due this week  \[store·later\]"'
# carry-forward: expire a focus CAP → dropped from carry; still-alive stays the default
bash "$S/vt-store-expire.sh" --force-expire CAP-006 >/dev/null
ck "carry-forward: expired CAP leaves the default"        '[ "$(bash "$S/vt-today.sh" --default)" = "CAP-007 CAP-008" ]'
TO2=$(bash "$S/vt-today.sh" --orient)
ck "today --orient: dropped shows honest ending"          'printf "%s" "$TO2" | grep -q "dropped (done / retired / expired):" && printf "%s" "$TO2" | grep -q "CAP-006  Fix login bug  \[store·expired\]"'
ck "today --orient: fresh stamp = re-orienting mid-day"   'printf "%s" "$TO2" | grep -q "(fresh — re-orienting mid-day)"'
# yesterday: derived from priorities.log + transitions, not an archive file
printf '%sT08:00:00Z\ttoday\tP0-001 CAP-002\ttoday\n' "$D1" >> "$VT_DIR/priorities.log"
Y=$(bash "$S/vt-today.sh" --yesterday)
ck "yesterday: last Today focus from priorities.log"      'printf "%s" "$Y" | grep -q "Last Today ('"$D1"') focus:" && printf "%s" "$Y" | grep -q "P0-001  Board story"'
ck "yesterday: board + store transitions sections"        'printf "%s" "$Y" | grep -q "Board transitions on '"$D1"':" && printf "%s" "$Y" | grep -q "Store transitions on '"$D1"':"'
# board is a state check: never written by any of the above
ck "real-c: board.md hash unchanged throughout"           '[ "'"$B26"'" = "$(shasum -a 256 "$VT_DIR/board.md" | awk "{print \$1}")" ]'
# gate = orientation: read-only ritual modes are never gated; setting focus still is
ck "rail-tier: vt-today --orient is readonly"             '[ "$(vt_rail_tier_for vt-today "bash \"$S/vt-today.sh\" --orient")" = "readonly" ]'
ck "rail-tier: vt-week --default is readonly"             '[ "$(vt_rail_tier_for vt-week "\"$S/vt-week.sh\" --default")" = "readonly" ]'
ck "rail-tier: vt-today --yesterday is readonly"          '[ "$(vt_rail_tier_for vt-today "$S/vt-today.sh --yesterday")" = "readonly" ]'
ck "rail-tier: chained --orient; set is NOT readonly"     '[ "$(vt_rail_tier_for vt-today "$S/vt-today.sh --orient; $S/vt-today.sh P0-1")" = "gateclear-today" ]'
ck "rail-tier: vt-today <ids> stays gateclear"            '[ "$(vt_rail_tier_for vt-today "$S/vt-today.sh P0-1")" = "gateclear-today" ]'
ck "gate copy: orientation, no state moves required"      'vt_gate_directive | grep -q "orientation stale" && vt_gate_directive | grep -q "no state moves are required"'
unset VT_DIR

echo "════ RESULT: $P passed, $F failed ════"
[ "$F" -eq 0 ]