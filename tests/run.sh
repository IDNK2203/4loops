#!/usr/bin/env bash
# 4loops mechanical regression suite. Repo-relative; run from anywhere:
#   bash tests/run.sh
# Covers the headline behaviors + regressions for the bugs found in the
# 2026-05-29 battle-test fan-out. The LIVE behaviors (does CC honor a plugin
# PreToolUse deny, AskUserQuestion render, version-cache, SessionStart cwd) are
# NOT here — they're the live walkthrough in DOGFOOD-PLAN.md.
set -uo pipefail
export VT_DIR_QUIET=1   # tests point VT_DIR at mktemp dirs while cwd sits under a real workspace

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
ck "legacy: pre-006 Focus: line still parses (upgrade path)" '[ "$(read_focus today)" = "P0-100" ]'
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
printf '# Current Priorities — w\n\n## Today (%s)\n- [ ] P0-007  Hard gate foundation\n\n## Week %s (r)\n- [ ] P0-007  Hard gate foundation\n' "$TODAY" "$WK" > "$VT/current-priorities.md"
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
# 5 stories: planning {T-001,T-005}, in-progress {T-002,T-004}, testing {T-003}.
# Dense grid → 2 body rows (max column height). A staircase would be 5.
NR=$(awk '/^\| Planning \| In Progress/{b=1;getline;next} b&&/^\|/{c++} END{print c+0}' "$VT_DIR/board.md")
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
ck "bootstrap: A is an open checkbox on Today" 'sed -n "/^## Today/,/^## Week/p" "$VT_DIR/current-priorities.md" | grep -q "^- \[ \] '"$A"'  ship the thing$"'
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
bash "$S/vt-draft.sh" T "just a parked item" >/dev/null
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
ck "arrange: both land in Planning (2 rows)"   '[ "$(grep -cE "ship the thing|model the flow" "$VT_DIR/board.md")" -ge 2 ]'
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
ck "today: mid-day pull-from-week, not the orientation" 'grep -qi "mid-day pull" "$PLUGIN/skills/today/SKILL.md" && grep -qi "not required" "$PLUGIN/skills/today/SKILL.md"'
ck "today: --orient is the one print (no board dump)"  'grep -q "vt-today.sh\" --orient" "$PLUGIN/skills/today/SKILL.md" && ! grep -q "vt-render.sh\"$" "$PLUGIN/skills/today/SKILL.md"'
ck "today: board is a state check only"                'grep -qi "state check" "$PLUGIN/skills/today/SKILL.md"'
ck "today: today ⊆ week, 2–3"                          'grep -q "only from the week" "$PLUGIN/skills/today/SKILL.md" && grep -q "2–3" "$PLUGIN/skills/today/SKILL.md"'
ck "today: free text lands in the store (no detour)"   'grep -qi "free text becomes a store item" "$PLUGIN/skills/today/SKILL.md"'
ck "week: one-shot orientation, gate clears, no /today needed" 'grep -qi "one-shot orientation" "$PLUGIN/skills/week/SKILL.md" && grep -q "Gate clears after this flow" "$PLUGIN/skills/week/SKILL.md"'
ck "week: --orient print, Monday vs Tue+ look-back, set --today" 'grep -q "vt-week.sh\" --orient" "$PLUGIN/skills/week/SKILL.md" && grep -q "Monday (new week)" "$PLUGIN/skills/week/SKILL.md" && grep -q "Tue+ (follow-up day)" "$PLUGIN/skills/week/SKILL.md" && grep -q "set <week items…> --today" "$PLUGIN/skills/week/SKILL.md"'
ck "today/week: no Keep/Edit/Skip board theater"         '! grep -q "Keep \`\[SUGGESTED_FOCUS\]\`" "$PLUGIN/skills/today/SKILL.md" && ! grep -q "Keep \`\[SUGGESTED_FOCUS\]\`" "$PLUGIN/skills/week/SKILL.md" && ! grep -qi "structured multi-select" "$PLUGIN/skills/week/SKILL.md"'
ck "prioritize: focus-only escape"              'grep -qi "focus-only" "$PLUGIN/skills/prioritize/SKILL.md"'
ck "prioritize: mid-day direct add + drop + done"  'grep -q "vt-priority.sh\" drop" "$PLUGIN/skills/prioritize/SKILL.md" && grep -q "week add" "$PLUGIN/skills/prioritize/SKILL.md" && grep -q "vt-priority.sh\" done" "$PLUGIN/skills/prioritize/SKILL.md"'
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
ck "branch: shown in single-state FULL view"      'bash "$S/vt-render.sh" planning | grep -q "branch: feat/seam"'
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
# Capture does not touch the board at all
BOARD_BEFORE=$(wc -l < "$VT_DIR/board.md" | tr -d ' ')
printf 'P0\tStore happy path item\tdev\tpacket-002 evidence\t2026-09-20\n' | bash "$S/vt-store-capture.sh" >/tmp/vt-store-cap-out.txt
CAP_ID=$(awk '/^captured:/{print $2; exit}' /tmp/vt-store-cap-out.txt)
BOARD_AFTER=$(wc -l < "$VT_DIR/board.md" | tr -d ' ')
ck "store-capture: writes CAP id"                 '[ -n "'"$CAP_ID"'" ] && [ -f "$VT_DIR/store/items/'"$CAP_ID"'" ]'
ck "store-capture: state=captured"                'grep -q "^state=captured$" "$VT_DIR/store/items/'"$CAP_ID"'"'
ck "store-capture: board unchanged (no board dump)"   '[ "'"$BOARD_BEFORE"'" = "'"$BOARD_AFTER"'" ]'
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


# Track B is DEAD as a product surface and the /scope skill is gone (Packet 009b).
# The rails below stay — they still work, still carry a tier, and are reachable from
# a session holding any other capability — so they stay covered here.
echo "════ 24. v2.5 Track B (rails only — /scope skill removed): scope promote ════"
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
# `scope` is no longer a capability: the skill that minted it was removed, so the
# string can never appear in a cap token. The rails ride another command's grant.
ck "cap-allows: scope is no longer a capability"  '! vt_cap_allows scope mutate'
ck "cap-allows: another grant still drives the scope rails" 'vt_cap_allows sync mutate && vt_cap_allows manage mutate'
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

echo "════ 26. v2.5 Packet 006: one-shot /week — checkbox priorities · week≤5 from store · today 2–3 ⊆ week · day-add⇒week · look-back · gate ════"
W26=$(mktemp -d); export VT_DIR="$W26/.4loops"
D1=$(date -v-1d +%F 2>/dev/null || date -d 'yesterday' +%F)
LW=$(date -v-7d +%V 2>/dev/null || date -d "7 days ago" +%V)
bash "$S/vt-init.sh" >/dev/null
bash "$S/vt-config.sh" project P0 "dev-os" dev-os >/dev/null
bash "$S/vt-config.sh" week-start mon >/dev/null
bash "$S/vt-draft.sh" P0 "Board story" "why" "" >/dev/null
bash "$S/vt-transition.sh" P0-001 in-progress >/dev/null
printf 'P0\tUrgent cap\tdev\tx\turgent\n'         | bash "$S/vt-store-capture.sh" >/dev/null   # CAP-001
printf 'P0\tToday cap\tdev\tx\ttoday\n'           | bash "$S/vt-store-capture.sh" >/dev/null   # CAP-002
printf 'P0\tDue this week\tdev\tx\t%s\n' "$TODAY" | bash "$S/vt-store-capture.sh" >/dev/null   # CAP-003 later, due today
printf 'P0\tParked\tdev\tx\t\n'                   | bash "$S/vt-store-capture.sh" >/dev/null   # CAP-004 later
bash "$S/vt-store-expire.sh" --activate-only >/dev/null
B26=$(shasum -a 256 "$VT_DIR/board.md" | awk '{print $1}')
# ── orient (first run = new week): file · look-back · store pick list · machine lines
WO=$(bash "$S/vt-week.sh" --orient)
ck "week --orient: MODE new-week on first run"                      'printf "%s" "$WO" | grep -q "^MODE: new-week$"'
ck "week --orient: week suggested = store pull (urgent, today, due), cut to cap" 'printf "%s" "$WO" | grep -q "^WEEK_SUGGESTED: CAP-001 CAP-002 CAP-003$"'
ck "week --orient: today suggested ⊆ week suggested, max 3"         'printf "%s" "$WO" | grep -q "^TODAY_SUGGESTED: CAP-001 CAP-002 CAP-003$"'
ck "week --orient: cap arithmetic printed"                          'printf "%s" "$WO" | grep -q "cap 5: 0 open on the week → up to 5 new"'
ck "week --orient: board work is pickable, not the source"          'printf "%s" "$WO" | grep -q "board work in flight (also pickable):" && printf "%s" "$WO" | grep -q "P0-001  Board story  \[in-progress\]"'
ck "week --orient: later is listed (store is THE source), due item not duplicated" 'printf "%s" "$WO" | grep -q "later (1 parked):" && [ "$(printf "%s" "$WO" | grep -c "CAP-003  Due this week")" = "1" ]'
ck "week --orient: no Keep/Edit/Skip, no board dump"                '! printf "%s" "$WO" | grep -qi "keep\|edit\|skip" && ! printf "%s" "$WO" | grep -q "| Backlog |"'
# ── the one-shot commit: week (board + CAP + free text) + today, one call, gate clears
bash "$S/vt-week.sh" set P0-001 CAP-001 CAP-002 "New week item" --today P0-001 CAP-001 >/tmp/vt26-set.txt 2>&1
ck "one-shot set: both sections announced"              'grep -q "^Week set: P0-001 CAP-001 CAP-002 CAP-005$" /tmp/vt26-set.txt && grep -q "^Today set: P0-001 CAP-001$" /tmp/vt26-set.txt'
ck "checkbox format: today lines"                        'grep -q "^- \[ \] P0-001  Board story$" "$VT_DIR/current-priorities.md" && grep -q "^- \[ \] CAP-001  Urgent cap$" "$VT_DIR/current-priorities.md"'
ck "checkbox format: no Focus:/activity columns"         '! grep -q "^Focus:" "$VT_DIR/current-priorities.md" && ! grep -q "In progress" "$VT_DIR/current-priorities.md"'
ck "checkbox format: free text → store item lever=later, on week" 'grep -q "^lever=later$" "$VT_DIR/store/items/CAP-005" && grep -q "^- \[ \] CAP-005  New week item$" "$VT_DIR/current-priorities.md"'
ck "one-shot set: today ⊆ week"                          '[ "$(bash "$S/vt-today.sh" --current)" = "P0-001 CAP-001" ] && [ "$(bash "$S/vt-week.sh" --current)" = "P0-001 CAP-001 CAP-002 CAP-005" ]'
ck "one-shot set: gate clear (today + week fresh)"       '! bash -c "cd \"$W26\" && source \"$S/vt-priorities-lib.sh\" && vt_gate_active"'
ck "one-shot set: logged week + today"                   'grep -q "	week	P0-001 CAP-001 CAP-002 CAP-005	week$" "$VT_DIR/priorities.log" && grep -q "	today	P0-001 CAP-001	week$" "$VT_DIR/priorities.log"'
ck "one-shot set: committed CAP urgent → today; today CAP left off → later" 'grep -q "^lever=today$" "$VT_DIR/store/items/CAP-001" && grep -q "^lever=later$" "$VT_DIR/store/items/CAP-002"'
# ── caps
if bash "$S/vt-week.sh" add CAP-003 CAP-004 >/dev/null 2>/tmp/vt26-cap.txt; then CAP_RC=0; else CAP_RC=$?; fi
ck "week cap: 4 on → 2 new refused (exit 4) with arithmetic" '[ "'"$CAP_RC"'" = "4" ] && grep -q "4 already on the week, so at most 1 new (you named 2)" /tmp/vt26-cap.txt'
ck "week cap: refusal writes nothing"                       '[ "$(bash "$S/vt-week.sh" --current)" = "P0-001 CAP-001 CAP-002 CAP-005" ]'
bash "$S/vt-week.sh" add CAP-003 >/dev/null 2>&1
ck "week cap: 1 new accepted → 5 open"                      '[ "$(bash "$S/vt-week.sh" --current)" = "P0-001 CAP-001 CAP-002 CAP-005 CAP-003" ]'
if bash "$S/vt-today.sh" P0-001 CAP-001 CAP-002 CAP-003 >/dev/null 2>/tmp/vt26-t4.txt; then T4_RC=0; else T4_RC=$?; fi
ck "today cap: 4 refused (exit 4)"                          '[ "'"$T4_RC"'" = "4" ] && grep -q "today holds 2–3 items (you named 4)" /tmp/vt26-t4.txt'
if bash "$S/vt-today.sh" P0-001 CAP-004 >/dev/null 2>/tmp/vt26-orph.txt; then ORPH_RC=0; else ORPH_RC=$?; fi
ck "today ⊆ week: off-week pick at week cap refused (no orphan, no overflow)" '[ "'"$ORPH_RC"'" = "4" ] && grep -q "week cap" /tmp/vt26-orph.txt && ! grep -q "CAP-004" "$VT_DIR/current-priorities.md"'
# ── done: checkbox persists, store → done, frees a week slot
bash "$S/vt-priority.sh" done CAP-001 >/dev/null 2>&1
ck "done: [x] on today AND week"                            '[ "$(grep -c "^- \[x\] CAP-001  Urgent cap$" "$VT_DIR/current-priorities.md")" = "2" ]'
ck "done: store item state=done, logged"                    'grep -q "^state=done$" "$VT_DIR/store/items/CAP-001" && grep -q "CAP-001 | active → done | done" "$VT_DIR/store/transitions.log" && grep -q "	done	CAP-001	done$" "$VT_DIR/priorities.log"'
WOD=$(bash "$S/vt-week.sh" --orient)
ck "done: leaves the live store pull"                       'printf "%s" "$WOD" | grep -A1 "^    urgent:$" | grep -q "(none)"'
bash "$S/vt-priority.sh" add CAP-004 >/tmp/vt26-add.txt 2>&1
ck "day-add ⇒ week-add: promoted onto the week (slot freed by done)" 'grep -q "promoted to the week (today ⊆ week): CAP-004" /tmp/vt26-add.txt && [ "$(grep -c "^- \[ \] CAP-004  Parked$" "$VT_DIR/current-priorities.md")" = "2" ] && [ "$(bash "$S/vt-week.sh" --current)" = "P0-001 CAP-001 CAP-002 CAP-005 CAP-003 CAP-004" ]'
ck "day-add: today holds it, lever=today"                   '[ "$(bash "$S/vt-today.sh" --current)" = "P0-001 CAP-001 CAP-004" ] && grep -q "^lever=today$" "$VT_DIR/store/items/CAP-004"'
bash "$S/vt-priority.sh" add "Mid-day surprise" >/dev/null 2>/tmp/vt26-add2.txt
ck "day-add: free text over the WEEK cap refused BEFORE creating the item" 'grep -q "week cap is 5" /tmp/vt26-add2.txt && [ ! -f "$VT_DIR/store/items/CAP-006" ]'
bash "$S/vt-priority.sh" week drop CAP-005 >/dev/null 2>&1
bash "$S/vt-priority.sh" add "Mid-day surprise" >/dev/null 2>&1
ck "day-add: free text → CAP lever=today, on today + week"   'grep -q "^lever=today$" "$VT_DIR/store/items/CAP-006" && [ "$(grep -c "^- \[ \] CAP-006  Mid-day surprise$" "$VT_DIR/current-priorities.md")" = "2" ]'
bash "$S/vt-priority.sh" add "Fourth thing" >/dev/null 2>/tmp/vt26-add3.txt
ck "day-add: 4th today item refused BEFORE creating the item" 'grep -q "today holds 2–3 items (you named 4)" /tmp/vt26-add3.txt && [ ! -f "$VT_DIR/store/items/CAP-007" ]'
bash "$S/vt-priority.sh" drop CAP-004 >/dev/null 2>&1
ck "drop (today): off today, stays on week, CAP → later"     '[ "$(bash "$S/vt-today.sh" --current)" = "P0-001 CAP-001 CAP-006" ] && grep -q "^- \[ \] CAP-004  Parked$" "$VT_DIR/current-priorities.md" && grep -q "^lever=later$" "$VT_DIR/store/items/CAP-004"'
bash "$S/vt-priority.sh" week drop CAP-006 >/dev/null 2>&1
ck "week drop: also off today (today ⊆ week)"                '! grep -q "CAP-006" "$VT_DIR/current-priorities.md"'
bash "$S/vt-priority.sh" --project P0 add "Project item" >/dev/null 2>&1
ck "priority add --project: key honored"                     'grep -q "^project=P0$" "$VT_DIR/store/items/CAP-007"'
bash "$S/vt-priority.sh" week drop CAP-007 >/dev/null 2>&1
bash "$S/vt-priority.sh" add P0-999 >/dev/null 2>/tmp/vt26-warn.txt
ck "priority add: unknown ID kept, warned"                   'grep -q "P0-999" "$VT_DIR/current-priorities.md" && grep -q "not on the board or in the store" /tmp/vt26-warn.txt'
bash "$S/vt-priority.sh" week drop P0-999 >/dev/null 2>&1
ck "real-c: board.md untouched by every priorities rail"     '[ "'"$B26"'" = "$(shasum -a 256 "$VT_DIR/board.md" | awk "{print \$1}")" ]'
# ── board Done → [x] without a ritual (vt-transition refreshes the file)
bash "$S/vt-transition.sh" P0-001 done >/dev/null
ck "board Done → [x] in the file, stamps untouched"         '[ "$(grep -c "^- \[x\] P0-001  Board story$" "$VT_DIR/current-priorities.md")" = "2" ] && grep -q "^## Today ('"$TODAY"')$" "$VT_DIR/current-priorities.md"'
# ── follow-up day (Tue+): look-back since yesterday, not a week replay
perl -pi -e "s/^## Today \(\d{4}-\d{2}-\d{2}\)/## Today ($D1)/" "$VT_DIR/current-priorities.md"
WO2=$(bash "$S/vt-week.sh" --orient)
ck "follow-up: MODE follow-up, look-back since yesterday"   'printf "%s" "$WO2" | grep -q "^MODE: follow-up$" && printf "%s" "$WO2" | grep -q "^Look-back · since '"$D1"':$" && ! printf "%s" "$WO2" | grep -q "last week"'
ck "follow-up: done shown [x]"                              'printf "%s" "$WO2" | grep -q "\[x\] P0-001  Board story" && printf "%s" "$WO2" | grep -q "\[x\] CAP-001  Urgent cap"'
ck "follow-up: stale today → gate active"                   'bash -c "cd \"$W26\" && source \"$S/vt-priorities-lib.sh\" && vt_gate_active"'
bash "$S/vt-week.sh" today CAP-002 CAP-003 >/dev/null 2>&1
ck "follow-up: today beat alone clears the gate (no /today needed)" '! bash -c "cd \"$W26\" && source \"$S/vt-priorities-lib.sh\" && vt_gate_active" && [ "$(bash "$S/vt-today.sh" --current)" = "CAP-002 CAP-003" ]'
ck "follow-up: today set logged"                             'grep -q "	today	CAP-002 CAP-003	week$" "$VT_DIR/priorities.log"'
# ── new week (Monday): last-week look-back (done vs carried), week-only set leaves gate active until today
perl -pi -e "s/^## Week \d+ /## Week $LW /" "$VT_DIR/current-priorities.md"
perl -pi -e "s/^## Today \(\d{4}-\d{2}-\d{2}\)/## Today ($D1)/" "$VT_DIR/current-priorities.md"
WO3=$(bash "$S/vt-week.sh" --orient)
ck "new week: look-back = last week done vs carried"        'printf "%s" "$WO3" | grep -q "^MODE: new-week" && printf "%s" "$WO3" | grep -q "^Look-back · last week (Week '"$LW"'): 2 done · 3 carried$"'
ck "new week: carried items marked, done marked"            'printf "%s" "$WO3" | grep -q "\[ \] CAP-002  Today cap  (carried)" && printf "%s" "$WO3" | grep -q "\[x\] CAP-001  Urgent cap"'
ck "new week: week suggested = carry first, cut to cap"     'printf "%s" "$WO3" | grep -q "^WEEK_SUGGESTED: CAP-002 CAP-003 CAP-004$"'
ck "new week: /today refuses (exit 3) — /week is the one shot" 'bash "$S/vt-today.sh" CAP-002 CAP-003 >/dev/null 2>&1; [ $? = 3 ]'
bash "$S/vt-week.sh" set CAP-002 CAP-003 >/dev/null 2>&1
ck "new week: week-only set → week fresh, today still stale, gate ACTIVE" 'bash -c "cd \"$W26\" && source \"$S/vt-priorities-lib.sh\" && week_stamp_current \"\$(read_week_stamp)\" && vt_gate_active"'
bash "$S/vt-week.sh" today CAP-002 CAP-003 >/dev/null 2>&1
ck "new week: today beat → gate CLEAR"                      '! bash -c "cd \"$W26\" && source \"$S/vt-priorities-lib.sh\" && vt_gate_active"'
ck "today min is advisory: 1 item allowed with a note"      'bash "$S/vt-today.sh" CAP-002 >/dev/null 2>/tmp/vt26-min.txt && grep -q "target is 2–3" /tmp/vt26-min.txt'
# ── read-only rails + gate copy
printf '%sT08:00:00Z\ttoday\tP0-001 CAP-002\ttoday\n' "$D1" >> "$VT_DIR/priorities.log"
Y26=$(bash "$S/vt-today.sh" --yesterday); PR26=$(bash "$S/vt-week.sh" --print)
ck "yesterday: last Today from priorities.log"              'printf "%s" "$Y26" | grep -q "Last Today ('"$D1"') focus:"'
ck "--print: the checkbox file"                             'printf "%s" "$PR26" | grep -q "^## Today ('"$TODAY"')$"'
source "$S/vt-guard-lib.sh"
ck "rail-tier: vt-week --orient is readonly"                '[ "$(vt_rail_tier_for vt-week "bash \"$S/vt-week.sh\" --orient")" = "readonly" ]'
ck "rail-tier: vt-week --print is readonly"                 '[ "$(vt_rail_tier_for vt-week "\"$S/vt-week.sh\" --print")" = "readonly" ]'
ck "rail-tier: vt-today --yesterday is readonly"            '[ "$(vt_rail_tier_for vt-today "$S/vt-today.sh --yesterday")" = "readonly" ]'
ck "rail-tier: chained --orient; set is NOT readonly"       '[ "$(vt_rail_tier_for vt-week "$S/vt-week.sh --orient; $S/vt-week.sh set P0-1 --today P0-1")" = "gateclear-week" ]'
ck "rail-tier: vt-week set stays gateclear-week"            '[ "$(vt_rail_tier_for vt-week "$S/vt-week.sh set P0-1")" = "gateclear-week" ]'
ck "gate copy: orientation, one shot, no state moves"       'vt_gate_directive | grep -q "orientation stale" && vt_gate_directive | grep -q "no state moves are required" && vt_gate_directive | grep -q "/4loops:week: one shot"'
ck "gate copy: never points at /4loops:today"               '! vt_gate_directive | grep -q "/4loops:today"'
unset VT_DIR

echo "════ 27. v2.5 Packet 006: VT_DIR / cwd priorities-path resolution (dogfood mixup) ════"
W27=$(mktemp -d); mkdir -p "$W27/web-app/src"
( cd "$W27" && env -u VT_DIR bash "$S/vt-init.sh" >/dev/null && touch .4loops/config && env -u VT_DIR bash "$S/vt-draft.sh" P0 "thing" >/dev/null )
# unset VT_DIR from a SUBDIRECTORY → walks up to the workspace, no stray .4loops
( cd "$W27/web-app/src" && env -u VT_DIR bash "$S/vt-week.sh" set P0-001 --today P0-001 >/dev/null 2>&1 )
ck "vt_dir: unset from subdir → writes the workspace file"   'grep -q "^- \[ \] P0-001  thing$" "$W27/.4loops/current-priorities.md"'
ck "vt_dir: unset from subdir → no stray .4loops"            '[ ! -e "$W27/web-app/.4loops" ] && [ ! -e "$W27/web-app/src/.4loops" ]'
ck "vt_dir: doc title from the records, not the cwd"         'grep -q "^# Current Priorities — $(basename "$W27")$" "$W27/.4loops/current-priorities.md"'
# explicit VT_DIR wins (dry-runs rely on it), is absolutized, and a mismatch WARNS loudly
W27b=$(mktemp -d)
( cd "$W27" && VT_DIR="$W27b/.4loops" bash "$S/vt-init.sh" >/dev/null 2>&1 && VT_DIR="$W27b/.4loops" bash "$S/vt-draft.sh" P0 "other" >/dev/null 2>&1 && VT_DIR="$W27b/.4loops" VT_DIR_QUIET=0 bash "$S/vt-week.sh" set P0-001 --today P0-001 >/dev/null 2>/tmp/vt27-warn.txt )
ck "vt_dir: explicit VT_DIR wins over the cwd workspace"     'grep -q "^- \[ \] P0-001  other$" "$W27b/.4loops/current-priorities.md" && grep -q "^- \[ \] P0-001  thing$" "$W27/.4loops/current-priorities.md"'
ck "vt_dir: mismatch warned (the Packet 005 dogfood symptom)" 'grep -q "but this workspace.s records are at $W27/.4loops" /tmp/vt27-warn.txt'
ck "vt_dir: VT_DIR_QUIET=1 silences the warning"             '( cd "$W27" && VT_DIR="$W27b/.4loops" VT_DIR_QUIET=1 bash "$S/vt-week.sh" --current 2>&1 ) | { ! grep -q "records are at"; }'
ck "vt_dir: relative VT_DIR absolutized (no drift after cd)"  '( cd "$W27" && VT_DIR=./.4loops VT_DIR_QUIET=1 bash -c "source \"$S/vt-priorities-lib.sh\"; [ \"\$VT_DIR\" = \"$W27/.4loops\" ]" )'
ck "vt_dir: relative default from a subdir resolves to the workspace" '( cd "$W27/web-app" && VT_DIR=./.4loops VT_DIR_QUIET=1 bash -c "source \"$S/vt-priorities-lib.sh\"; [ \"\$VT_DIR\" = \"$W27/.4loops\" ]" )'
ck "sandbox: launcher pins VT_DIR to the workspace"          'grep -q "exec env VT_DIR=\"\$ws/.4loops\" claude" "$PLUGIN/../sandbox/sandbox.sh" && grep -q "exec env VT_DIR=\"\$ws/.4loops\" VT_ALLOW_STALE_GATE=1 claude" "$PLUGIN/../sandbox/sandbox.sh"'
ck "hooks + rails agree: the gate reads the file the rail wrote" '( cd "$W27/web-app/src" && printf "{\"session_id\":\"S27\",\"cwd\":\"%s\",\"tool_input\":{\"file_path\":\"%s\"}}" "$W27/web-app/src" "$W27/web-app/src/x.js" | env -u VT_DIR bash "$H/vt-gate.sh" 2>&1 ) | { ! grep -q "\"deny\""; }'

echo "════ 28. v2.5 Packet 007: orient survives an empty done-set + the midweek (Tue+) dogfood seed ════"
# The 2026-09-07 dogfood crash: _transitions_since ended with `[ -n "$d" ] && { … }`, so an empty
# done-set returned 1 and `set -euo pipefail` in vt-week.sh killed --orient BEFORE the machine
# lines. Nothing marked done is the NORMAL state, so orient must complete and exit 0.
W28=$(mktemp -d); export VT_DIR="$W28/.4loops"
bash "$S/vt-init.sh" >/dev/null
bash "$S/vt-config.sh" project P0 "dev-os" dev-os >/dev/null
bash "$S/vt-config.sh" week-start mon >/dev/null
bash "$S/vt-draft.sh" P0 "Board story" "why" "" >/dev/null
printf 'P0\tUrgent cap\tdev\tx\turgent\n' | bash "$S/vt-store-capture.sh" >/dev/null   # CAP-001
printf 'P0\tToday cap\tdev\tx\ttoday\n'   | bash "$S/vt-store-capture.sh" >/dev/null   # CAP-002
bash "$S/vt-store-expire.sh" --activate-only >/dev/null
bash "$S/vt-week.sh" set P0-001 CAP-001 --today P0-001 CAP-001 >/dev/null 2>&1
# ── follow-up day (Tue+), nothing marked done: the exact crash shape
perl -pi -e "s/^## Today \(\d{4}-\d{2}-\d{2}\)/## Today ($D1)/" "$VT_DIR/current-priorities.md"
ck "empty done-set: priorities.log really has no done rows" '! grep -q "	done	" "$VT_DIR/priorities.log"'
if WO28=$(bash "$S/vt-week.sh" --orient 2>/tmp/vt28-err.txt); then RC28=0; else RC28=$?; fi
ck "orient (follow-up, nothing done): exits 0"              '[ "'"$RC28"'" = "0" ]'
ck "orient (follow-up, nothing done): runs to the machine lines" 'printf "%s" "$WO28" | grep -q "^MODE: follow-up$" && printf "%s" "$WO28" | grep -q "^WEEK_SUGGESTED: " && printf "%s" "$WO28" | grep -q "^TODAY_SUGGESTED: "'
ck "orient (follow-up, nothing done): look-back printed, no done section" 'printf "%s" "$WO28" | grep -q "^Look-back · since '"$D1"':$" && ! printf "%s" "$WO28" | grep -q "marked done since"'
# ── new week (Monday), nothing marked done: same guard on the last-week look-back
perl -pi -e "s/^## Week \d+ /## Week $LW /" "$VT_DIR/current-priorities.md"
if WO28B=$(bash "$S/vt-week.sh" --orient 2>>/tmp/vt28-err.txt); then RC28B=0; else RC28B=$?; fi
ck "orient (new-week, nothing done): exits 0 and prints the machine lines" '[ "'"$RC28B"'" = "0" ] && printf "%s" "$WO28B" | grep -q "^MODE: new-week" && printf "%s" "$WO28B" | grep -q "^TODAY_SUGGESTED: "'
# ── and it still PRINTS the done section when there is one
bash "$S/vt-priority.sh" done CAP-001 >/dev/null 2>&1
WO28C=$(bash "$S/vt-week.sh" --orient)
ck "orient: a non-empty done-set is still reported"         'printf "%s" "$WO28C" | grep -q "marked done since" && printf "%s" "$WO28C" | grep -q "^TODAY_SUGGESTED: "'
# ── archived story keeps its title in the look-back (the "[x] API-003  ?" dogfood print)
bash "$S/vt-transition.sh" P0-001 done >/dev/null 2>&1
bash "$S/vt-close.sh" --weekly >/dev/null 2>&1
ck "archived story: off the board"                          '! grep -q "P0-001" "$VT_DIR/board.md"'
ck "archived story: look-back keeps the title, not \"?\"" 'WOA=$(bash "$S/vt-week.sh" --orient); printf "%s" "$WOA" | grep -q "\[x\] P0-001  Board story" && ! printf "%s" "$WOA" | grep -q "P0-001  ?"'
# ── same class: drift rails must not leave a non-zero status behind
ck "drift: vt-drift.sh exits 0 with drift present"          'bash "$S/vt-drift.sh" >/dev/null 2>&1'
ck "drift: vt-close.sh daily exits 0"                       'bash "$S/vt-close.sh" >/dev/null 2>&1'
unset VT_DIR
# ── the midweek (Tue+) dogfood seed: week stamp CURRENT, only Today stale
SB="$PLUGIN/../sandbox/sandbox.sh"
ck "sandbox: demo c takes --midweek"                        'grep -q -- "--midweek|--tue) midweek=1" "$SB" && grep -q -- "--midweek applies to demo c only" "$SB"'
ck "sandbox: --midweek keeps the week stamp on the current ISO week" 'grep -q "if \[ \"\$midweek\" != 1 \]; then" "$SB"'
if MWOUT=$(bash "$SB" demo c --midweek --no-launch 2>&1); then MW_RC=0; else MW_RC=$?; fi
ck "sandbox: demo c --midweek exits 0"                      '[ "$MW_RC" = "0" ]'
MWWS=$(printf "%s" "$MWOUT" | grep -o "/tmp/vt-sandbox-beta-realc-midweek-[0-9-]*/workspace" | head -1)
ck "sandbox: --midweek builds a distinctly-named sandbox"   '[ -n "'"$MWWS"'" ] && [ -d "'"$MWWS"'/.4loops" ]'
ck "sandbox: midweek walk written to DOGFOOD-REAL-C.md"     'grep -q "MIDWEEK (Tue+) variant" "'"$MWWS"'/DOGFOOD-REAL-C.md"'
ck "sandbox: midweek seed = current Week header, yesterday Today" 'grep -q "^## Week '"$WK"' " "'"$MWWS"'/.4loops/current-priorities.md" && grep -q "^## Today ('"$D1"')$" "'"$MWWS"'/.4loops/current-priorities.md"'
MWO=$(VT_DIR="$MWWS/.4loops" bash "$S/vt-week.sh" --orient)
ck "sandbox midweek: orient completes — follow-up, since-yesterday, machine lines" 'printf "%s" "$MWO" | grep -q "^MODE: follow-up$" && printf "%s" "$MWO" | grep -q "^Look-back · since '"$D1"':$" && printf "%s" "$MWO" | grep -q "^TODAY_SUGGESTED: "'
ck "sandbox midweek: no last-week dump"                     '! printf "%s" "$MWO" | grep -q "Look-back · last week"'
ck "sandbox midweek: gate ACTIVE on launch (Today stale)"   'bash -c "cd \"'"$MWWS"'\" && VT_DIR=\"'"$MWWS"'/.4loops\" source \"$S/vt-priorities-lib.sh\" && vt_gate_active"'
# default demo c is unchanged: prior week ⇒ new-week look-back
if DCOUT=$(bash "$SB" demo c --no-launch 2>&1); then DC_RC=0; else DC_RC=$?; fi
ck "sandbox: demo c exits 0"                                '[ "$DC_RC" = "0" ]'
DCWS=$(printf "%s" "$DCOUT" | grep -o "/tmp/vt-sandbox-beta-realc-[0-9-]*/workspace" | head -1)
DCO=$(VT_DIR="$DCWS/.4loops" bash "$S/vt-week.sh" --orient)
ck "sandbox demo c (default): still new-week with a last-week look-back" 'printf "%s" "$DCO" | grep -q "^MODE: new-week" && printf "%s" "$DCO" | grep -q "^Look-back · last week (Week '"$LW"'):" && printf "%s" "$DCO" | grep -q "^TODAY_SUGGESTED: "'
rm -rf "$(dirname "$MWWS")" "$(dirname "$DCWS")" 2>/dev/null || true

echo
echo "════ 30. v2.5 Track D: board = pure active state (manage) ════"
W30=$(mktemp -d); export VT_DIR="$W30/.4loops"
bash "$S/vt-init.sh" >/dev/null
ck "board shape: fresh board is the 4-state pipeline"  'grep -qxF "| Planning | In Progress | Testing | Done |" "$VT_DIR/board.md"'
ck "board shape: no Backlog column"                    '! grep -q "Backlog" "$VT_DIR/board.md"'
ck "counts: header drops Backlog"                      'grep -q "^\*\*Counts:\*\* Planning 0 · In Progress 0 · Testing 0 · Done 0$" "$VT_DIR/board.md"'

# ── 1. Capture never creates a board cell; a draft is a COMMITMENT → Planning
B30=$(wc -l < "$VT_DIR/board.md" | tr -d " ")
printf "P0\tstore-only item\tdev\t\tlater\n" | bash "$S/vt-store-capture.sh" >/dev/null
ck "capture: board untouched (store owns intake)"      '[ "$(wc -l < "$VT_DIR/board.md" | tr -d " ")" = "'"$B30"'" ]'
bash "$S/vt-draft.sh" P0 "committed work" "we said we would" >/dev/null
ck "draft: lands in Planning, not an intake pen"       '[ "$(VT_DIR="$VT_DIR" bash -c "source \"$S/vt-priorities-lib.sh\"; story_state P0-001")" = "planning" ]'
ck "draft: logs ∅→planning"                            'grep -q "P0-001.*∅→planning" "$VT_DIR/transitions.log"'
ck "transition: backlog is refused with a pointer"     'O=$(bash "$S/vt-transition.sh" P0-001 backlog 2>&1); [ "$?" != "0" ] || printf "%s" "$O" | grep -q "no longer a board state"'

# ── 2. Done dwell → archive flush (reversible)
bash "$S/vt-draft.sh" P0 "shipped ages ago" >/dev/null
bash "$S/vt-draft.sh" P0 "shipped just now" >/dev/null
bash "$S/vt-transition.sh" P0-002 done --backdate "$D10" >/dev/null
bash "$S/vt-transition.sh" P0-003 done >/dev/null
FDRY=$(bash "$S/vt-flush.sh" --dry-run)
ck "flush dry-run: only the ripe row is listed"        'printf "%s" "$FDRY" | grep -q "P0-002" && ! printf "%s" "$FDRY" | grep -q "P0-003"'
ck "flush dry-run: changes nothing"                    'grep -q "P0-002" "$VT_DIR/board.md"'
bash "$S/vt-flush.sh" >/dev/null
MO30=$(date +%Y-%m)
ck "flush: ripe Done row leaves the grid"              '! grep -q "P0-002" "$VT_DIR/board.md"'
ck "flush: still-dwelling Done row stays"              'grep -q "P0-003" "$VT_DIR/board.md"'
ck "flush: archive gains the row"                      'grep -q "P0-002" "$VT_DIR/archive/'"$MO30"'/closed.md"'
ck "flush: logged as done→archived"                    'grep -q "P0-002.*done→archived" "$VT_DIR/transitions.log"'
bash "$S/vt-flush.sh" --restore P0-002 >/dev/null
ck "flush --restore: row is back on the board"         'grep -q "P0-002" "$VT_DIR/board.md"'
ck "flush --restore: archive record is kept (append-only)" 'grep -q "P0-002" "$VT_DIR/archive/'"$MO30"'/closed.md"'
ck "flush: --dwell 0 takes the whole column"           'bash "$S/vt-flush.sh" --all >/dev/null; ! grep -qE "P0-002|P0-003" "$VT_DIR/board.md"'
ck "close --flush: wired to the same rail"             'bash "$S/vt-close.sh" --flush --dry-run | grep -q "flush"'
unset VT_DIR

# ── 3. Task CRUD (P0-048): edit · merge · remove, proven by re-render from disk
W31=$(mktemp -d); export VT_DIR="$W31/.4loops"
bash "$S/vt-draft.sh" WEB "Wire metrics" "shell is empty" "web-app/src/D.jsx" --deadline 2026-10-01 >/dev/null
bash "$S/vt-draft.sh" WEB "Metrics wiring dup" >/dev/null
bash "$S/vt-draft.sh" WEB "typo row" >/dev/null
bash "$S/vt-transition.sh" WEB-001 in-progress >/dev/null
bash "$S/vt-edit.sh" WEB-001 --title "Wire up the live metrics panel" --why "dashboard shell is empty" >/dev/null
ck "edit: new title is on disk"                        'grep -q "Wire up the live metrics panel" "$VT_DIR/board.md"'
ck "edit: new why is on disk"                          'grep -q "why: dashboard shell is empty" "$VT_DIR/board.md"'
ck "edit: state is untouched (content ≠ transition)"   '[ "$(VT_DIR="$VT_DIR" bash -c "source \"$S/vt-priorities-lib.sh\"; story_state WEB-001")" = "in-progress" ]'
ck "edit: deadline + context survive a title change"   'grep -q "due: 2026-10-01" "$VT_DIR/board.md" && grep -q "context: \[D\](web-app/src/D.jsx)" "$VT_DIR/board.md"'
ck "edit: --clear drops a field"                       'bash "$S/vt-edit.sh" WEB-001 --clear due >/dev/null; ! grep -q "due: 2026-10-01" "$VT_DIR/board.md"'
bash "$S/vt-merge.sh" WEB-002 WEB-001 >/dev/null
ck "merge: the folded story leaves the grid"           '! grep -q "\\*\\*WEB-002\\*\\*" "$VT_DIR/board.md"'
ck "merge: survivor records what it absorbed"          'grep -q "merged WEB-002: Metrics wiring dup" "$VT_DIR/board.md"'
ck "merge: survivor keeps its column"                  '[ "$(VT_DIR="$VT_DIR" bash -c "source \"$S/vt-priorities-lib.sh\"; story_state WEB-001")" = "in-progress" ]'
ck "merge: archived, so it is reversible"              'grep -q "WEB-002" "$VT_DIR/archive/'"$MO30"'/merged.md"'
bash "$S/vt-remove.sh" WEB-003 --reason "mis-capture" >/dev/null
ck "remove: row is off the board"                      '! grep -q "WEB-003" "$VT_DIR/board.md"'
ck "remove: archived with its reason"                  'grep -q "mis-capture" "$VT_DIR/archive/'"$MO30"'/removed.md"'
ck "remove: restorable"                                'bash "$S/vt-flush.sh" --restore WEB-003 --to planning >/dev/null; grep -q "WEB-003" "$VT_DIR/board.md"'
ck "CRUD proof: re-render from disk shows the edits"   'bash "$S/vt-render.sh" in-progress | grep -q "Wire up the live metrics panel" && bash "$S/vt-render.sh" in-progress | grep -q "merged WEB-002"'
ck "cell rewrite: the row keeps exactly 4 columns"     '[ "$(awk -F"|" "/[*][*]WEB-001[*][*]/{print NF; exit}" "$VT_DIR/board.md")" = "6" ]'

# ── 4. Key ops (P0-049): rename carries IDs, counter and trail; collisions refused
bash "$S/vt-key.sh" rename WEB APP >/dev/null
ck "key rename: board cells re-tagged"                 'grep -q "\[APP\] \*\*APP-001\*\*" "$VT_DIR/board.md"'
ck "key rename: old key is gone"                       '! grep -q "WEB-" "$VT_DIR/board.md"'
ck "key rename: Projects table row moved"              'grep -q "^| APP | " "$VT_DIR/board.md"'
ck "key rename: ID counter carried over"               '[ -f "$VT_DIR/.ids/APP.counter" ] && [ ! -f "$VT_DIR/.ids/WEB.counter" ]'
ck "key rename: archive trail follows"                 'grep -q "APP-002" "$VT_DIR/archive/'"$MO30"'/merged.md"'
ck "key rename: next draft continues the sequence"     'bash "$S/vt-draft.sh" APP "next one" | grep -q "APP-004"'
ck "key rename: collision refused"                     'bash "$S/vt-draft.sh" ZZ x >/dev/null; ! bash "$S/vt-key.sh" rename APP ZZ 2>/dev/null'
ck "key ops: abandon still archives"                   'bash "$S/vt-transition.sh" APP-004 abandoned >/dev/null; grep -q "APP-004" "$VT_DIR/archive/'"$MO30"'/abandoned.md"'
unset VT_DIR

# ── 5. Legacy boards: readable, migratable, never hand-edited
W32=$(mktemp -d); export VT_DIR="$W32/.4loops"; mkdir -p "$VT_DIR/.ids" "$VT_DIR/archive"; : > "$VT_DIR/transitions.log"
cat > "$VT_DIR/board.md" <<EOF
# 4loops

**Counts:** Backlog 2 · Planning 0 · In Progress 1 · Testing 0 · Done 0

## Projects

| Key | Project | Repo |
| --- | ------- | ---- |
| WEB | web-app | web-app |

---

| Backlog | Planning | In Progress | Testing | Done |
| ------- | -------- | ----------- | ------- | ---- |
| [WEB] **WEB-001** parked copy — why: stale |  | [WEB] **WEB-003** in flight |  |  |
| [WEB] **WEB-002** parked spike — type: modeling — due: 2026-10-01 |  |  |  |  |
EOF
echo 3 > "$VT_DIR/.ids/WEB.counter"
ck "legacy: a 5-column board still parses"             '[ "$(VT_DIR="$VT_DIR" bash -c "source \"$S/vt-priorities-lib.sh\"; story_state WEB-001")" = "backlog" ]'
ck "legacy: render never shows Backlog as a column"    '! bash "$S/vt-render.sh" | grep -q "^| Backlog |"'
ck "legacy: render surfaces the migration notice"      'bash "$S/vt-render.sh" | grep -q "still sit in the legacy Backlog column"'
MDRY=$(bash "$S/vt-migrate-backlog.sh" --dry-run)
ck "migrate dry-run: lists both parked stories"        'printf "%s" "$MDRY" | grep -q "WEB-001" && printf "%s" "$MDRY" | grep -q "WEB-002"'
ck "migrate dry-run: touches nothing"                  'grep -q "WEB-001" "$VT_DIR/board.md"'
bash "$S/vt-migrate-backlog.sh" --to planning --only WEB-001 >/dev/null
ck "migrate --to planning: committed work is promoted" '[ "$(VT_DIR="$VT_DIR" bash -c "source \"$S/vt-priorities-lib.sh\"; story_state WEB-001")" = "planning" ]'
bash "$S/vt-migrate-backlog.sh" >/dev/null
ck "migrate --to store: the rest becomes store items"  'grep -rq "title=parked spike" "$VT_DIR/store/items/"'
ck "migrate: store item lands on lever later"          'grep -rq "^lever=later$" "$VT_DIR/store/items/"'
ck "migrate: deadline survives the move"               'grep -rq "^deadline=2026-10-01$" "$VT_DIR/store/items/"'
ck "migrate: an archive record makes it reversible"    'grep -q "WEB-002" "$VT_DIR/archive/'"$MO30"'/migrated.md"'
ck "migrate: the Backlog column is gone"               'grep -qxF "| Planning | In Progress | Testing | Done |" "$VT_DIR/board.md" && ! grep -q "Backlog" "$VT_DIR/board.md"'
ck "migrate: in-flight story is untouched"             '[ "$(VT_DIR="$VT_DIR" bash -c "source \"$S/vt-priorities-lib.sh\"; story_state WEB-003")" = "in-progress" ]'
ck "migrate: counts drop the Backlog segment"          'grep -q "^\*\*Counts:\*\* Planning 1 · In Progress 1 · Testing 0 · Done 0$" "$VT_DIR/board.md"'
ck "migrate: re-running is a clean no-op"              'bash "$S/vt-migrate-backlog.sh" | grep -q "already has no Backlog column"'
unset VT_DIR

# ── 6. The rails say so: no skill sends intake to the board
ck "manage: offers no Backlog target"                  '! grep -qE "^- \`/manage <id> .*backlog" "$PLUGIN/skills/manage/SKILL.md"'
ck "manage: documents the CRUD + flush + key rails"    'grep -q "vt-edit.sh" "$PLUGIN/skills/manage/SKILL.md" && grep -q "vt-merge.sh" "$PLUGIN/skills/manage/SKILL.md" && grep -q "vt-remove.sh" "$PLUGIN/skills/manage/SKILL.md" && grep -q "vt-flush.sh" "$PLUGIN/skills/manage/SKILL.md" && grep -q "vt-key.sh" "$PLUGIN/skills/manage/SKILL.md"'
ck "manage: documents the migration path"              'grep -q "vt-migrate-backlog.sh" "$PLUGIN/skills/manage/SKILL.md"'
ck "board skill: describes the 4-column pipeline"      'grep -q "Planning | In Progress | Testing | Done" "$PLUGIN/skills/board/SKILL.md"'
# The new lifecycle rails are board writers — they must sit in the capability table,
# or the bash gate would fail open and let an unprompted agent drive them.
( source "$S/vt-guard-lib.sh"
  for r in vt-edit vt-merge vt-remove vt-flush vt-key vt-migrate-backlog; do
    [ "$(vt_rail_tier "$r")" = "mutate" ] || exit 1
    vt_cap_allows manage "$(vt_rail_tier "$r")" || exit 1
    vt_cap_allows "" "$(vt_rail_tier "$r")" && exit 1
  done; exit 0 ) && TIER_OK=1 || TIER_OK=0
ck "guard: Track D rails are mutate-tier under /manage"  '[ "$TIER_OK" = "1" ]'

echo "════ 31. v2.5 Packet 009: coherence — /week always prints priorities · matrix invariants ════"
SK="$PLUGIN/skills"
# ── the orient rail actually emits the surface the skill promises
W27=$(mktemp -d); export VT_DIR="$W27/.4loops"
bash "$S/vt-init.sh" >/dev/null
bash "$S/vt-config.sh" project P0 "dev-os" dev-os >/dev/null
printf 'P0\tOrient marker\tdev\tx\ttoday\n' | bash "$S/vt-store-capture.sh" >/dev/null
bash "$S/vt-store-expire.sh" --activate-only >/dev/null
O27=$(bash "$S/vt-week.sh" --orient)
ck "orient: prints the Priorities header (the section Ese missed)"  'printf "%s" "$O27" | grep -q "^── Priorities (current-priorities.md) ──$"'
ck "orient: Priorities comes BEFORE the look-back"                  '[ "$(printf "%s" "$O27" | grep -n "── Priorities" | cut -d: -f1)" -lt "$(printf "%s" "$O27" | grep -n "── Look-back" | cut -d: -f1)" ]'
bash "$S/vt-week.sh" set CAP-001 --today CAP-001 >/dev/null 2>&1
O27B=$(bash "$S/vt-week.sh" --orient)
ck "orient: checkbox markers are in the print once the file exists"  'printf "%s" "$O27B" | grep -q "^- \[ \] CAP-001  Orient marker$"'
ck "orient: a second run still prints it (not once-per-day)"         '[ "$(bash "$S/vt-week.sh" --orient | grep -c "── Priorities")" = "1" ]'
ck "orient: --orient stays readonly-tier even after the week is set"  '[ "$(bash -c "source \"$S/vt-guard-lib.sh\"; vt_rail_tier_for vt-week \"$S/vt-week.sh --orient\"")" = "readonly" ]'
unset VT_DIR; rm -rf "$W27"
# ── the /week skill contract: Step 1 is unconditional (the Packet 009 bug)
ck "week skill: no 'skip to Step 3' shortcut past the orient print"  '! grep -q "skip to Step 3" "$SK/week/SKILL.md"'
ck "week skill: says Step 1 is unconditional"                        'grep -q "This step is unconditional" "$SK/week/SKILL.md"'
ck "week skill: \$ARGUMENTS may only skip Step 2"                    'grep -q "only skips \*\*Step 2\*\*" "$SK/week/SKILL.md"'
ck "week skill: states the never-skip invariant up front"            'grep -q "^\*\*Invariant:\*\* every .*--orient.* stdout verbatim" "$SK/week/SKILL.md"'
ck "week skill: Step 1 heading carries ALWAYS"                       'grep -q "^## Step 1 — Orient (print ONCE, ALWAYS" "$SK/week/SKILL.md"'
ck "week skill: the orient call sits before the two picks"           '[ "$(grep -n "vt-week.sh\" --orient" "$SK/week/SKILL.md" | head -1 | cut -d: -f1)" -lt "$(grep -n "^## Step 2 — Two picks" "$SK/week/SKILL.md" | cut -d: -f1)" ]'
ck "week skill: no AskUserQuestion is described before Step 1"       '[ "$(sed -n "/^---$/,/^---$/!p" "$SK/week/SKILL.md" | grep -n "AskUserQuestion" | head -1 | cut -d: -f1)" -gt "$(sed -n "/^---$/,/^---$/!p" "$SK/week/SKILL.md" | grep -n "^## Step 1 — Orient" | cut -d: -f1)" ]'
ck "today skill: same rule, no question-skip past the print"         'grep -q "This step is unconditional" "$SK/today/SKILL.md" && ! grep -q "skip the question and go straight to Step 2" "$SK/today/SKILL.md"'
ck "sync skill: orient prints are unconditional too"                 'grep -q "prints above are unconditional" "$SK/sync/SKILL.md" && ! grep -q "skip straight to step 2 and act on it" "$SK/sync/SKILL.md"'
# ── invocation-matrix invariants: the SoT table must stay true of the code
ck "matrix: board is the ONLY model-invokable skill"                 '[ "$(grep -L "disable-model-invocation: true" "$SK"/*/SKILL.md)" = "$SK/board/SKILL.md" ]'
ck "matrix: every skill is user-invocable"                           '[ "$(grep -l "^user-invocable: true$" "$SK"/*/SKILL.md | wc -l | tr -d " ")" = "$(ls -d "$SK"/*/ | wc -l | tr -d " ")" ]'
# No rail may fall through vt_rail_tier: an unclassified vt-*.sh is a fail-open
# hole in the bash gate (empty tier → allowed with no capability).
( source "$S/vt-guard-lib.sh"
  for f in "$S"/vt-*.sh; do
    r=$(basename "$f" .sh); case "$r" in *-lib) continue ;; esac
    [ -n "$(vt_rail_tier "$r")" ] || { echo "$r" >&2; exit 1; }
  done; exit 0 ) 2>/tmp/vt27-untiered.txt && TIER27=1 || TIER27=0
ck "matrix: every non-lib rail has a tier (no bash-gate fail-open)"  '[ "$TIER27" = "1" ]' "untiered: $(cat /tmp/vt27-untiered.txt)"
ck "matrix: the gate-clearing rails are exactly vt-week + vt-today"  'bash -c "source \"$S/vt-guard-lib.sh\"; [ \"\$(vt_rail_tier vt-week)\" = gateclear-week ] && [ \"\$(vt_rail_tier vt-today)\" = gateclear-today ]"'
ck "matrix: a capability-less session gets no mutate rail"           'bash -c "source \"$S/vt-guard-lib.sh\"; ! vt_cap_allows \"\" mutate && vt_cap_allows \"\" readonly"'
ck "matrix: /board mints a cap that unlocks readonly only"           'bash -c "source \"$S/vt-guard-lib.sh\"; vt_cap_allows board readonly && ! vt_cap_allows board mutate && ! vt_cap_allows board gateclear-week"'
ck "matrix: week cap does not clear the today ritual (and back)"     'bash -c "source \"$S/vt-guard-lib.sh\"; ! vt_cap_allows week gateclear-today && ! vt_cap_allows today gateclear-week"'
# ── Packet 009 finding: a "read-only" invocation that actually WRITES.
# vt-week.sh has no --yesterday, and its dispatch ends in a catch-all that treats
# a bare token as free text — so `vt-week.sh --yesterday` used to create a store
# item and set the week while vt_rail_tier_for called it readonly (= no capability
# needed). Both sides are now closed.
ck "tier: vt-week --yesterday is NOT readonly (the rail has no such mode)"  '[ "$(bash -c "source \"$S/vt-guard-lib.sh\"; vt_rail_tier_for vt-week \"$S/vt-week.sh --yesterday\"")" = "gateclear-week" ]'
ck "tier: vt-today --yesterday IS readonly (that rail does have it)"        '[ "$(bash -c "source \"$S/vt-guard-lib.sh\"; vt_rail_tier_for vt-today \"$S/vt-today.sh --yesterday\"")" = "readonly" ]'
ck "tier: a readonly mode glued to more args is not readonly"               '[ "$(bash -c "source \"$S/vt-guard-lib.sh\"; vt_rail_tier_for vt-week \"$S/vt-week.sh --orientX\"")" = "gateclear-week" ]'
ck "tier: every declared readonly mode is one the rail really dispatches"   'bash -c "source \"$S/vt-guard-lib.sh\"
  for r in vt-week vt-today; do
    IFS=\"|\" read -ra ms <<< \"\$(vt_rail_readonly_modes \$r)\"
    for m in \"\${ms[@]}\"; do grep -q -- \"^  --\$m)\" \"$S/\$r.sh\" || exit 1; done
  done; exit 0"'
W31=$(mktemp -d); export VT_DIR="$W31/.4loops"
bash "$S/vt-init.sh" >/dev/null; bash "$S/vt-config.sh" project P0 "dev-os" dev-os >/dev/null
bash "$S/vt-week.sh" --yesterday >/dev/null 2>/tmp/vt31-wy.txt; WY_RC=$?
ck "rail: vt-week --yesterday is refused, not parsed as an item"           '[ "'"$WY_RC"'" = "2" ] && grep -q "has no --yesterday mode" /tmp/vt31-wy.txt'
ck "rail: the refusal creates nothing (no CAP-001, no week)"               '[ ! -d "$VT_DIR/store/items" ] || [ -z "$(ls -A "$VT_DIR/store/items")" ]'
bash "$S/vt-today.sh" --bogus >/dev/null 2>/tmp/vt31-tb.txt; TB_RC=$?
ck "rail: vt-today rejects an unknown flag too"                            '[ "'"$TB_RC"'" = "2" ] && grep -q "has no --bogus mode" /tmp/vt31-tb.txt'
ck "rail: the known read-only modes still work"                            'bash "$S/vt-week.sh" --print >/dev/null && bash "$S/vt-week.sh" --orient >/dev/null && bash "$S/vt-today.sh" --yesterday >/dev/null'
unset VT_DIR; rm -rf "$W31"
# ── deny copy names WHICH gate (Ese: "agent says can't without saying which")
source "$S/vt-guard-lib.sh"
ck "deny copy: rail-capability block names the bash-gate"            'vt_cap_deny_reason | grep -q "BASH-GATE (rail capability" && vt_cap_deny_reason | grep -q "NOT the orientation gate"'
ck "deny copy: rail-capability block says read-only is never blocked" 'vt_cap_deny_reason | grep -q "NEVER blocked"'
ck "deny copy: rail-record block names the bash-gate"                'vt_record_deny_reason | grep -q "BASH-GATE (rail-owned record"'
ck "deny copy: orientation gate says it is NOT the bash-gate"        'vt_gate_directive | grep -q "ORIENTATION GATE" && vt_gate_directive | grep -q "NOT the rail-capability bash-gate"'
# ── audit: no skill still claims a Track B/D behaviour that never shipped
ck "audit: /manage no longer points at a /today reconcile that is gone" '! grep -q "like \`/today\`'"'"'s reconcile" "$SK/manage/SKILL.md"'

echo "════ 32. v2.5 Packet 009b: gated globs are patterns · /scope removed · gate-scope docs ════"
SK="$PLUGIN/skills"
# ── The dogfood bug: `gated: web-app/*` was expanded as a PATHNAME, not kept as a
# pattern. When the guard's cwd happened to contain web-app/, the config glob became
# the LISTING (web-app/README.md, web-app/src, …), so a nested product file matched
# nothing and the orientation gate silently stopped gating it. The §6 tests missed it
# because their cwd (the repo) has no such directory — so this one runs FROM INSIDE
# the workspace, where the expansion actually fires.
W32=$(mktemp -d)
mkdir -p "$W32/.4loops" "$W32/web-app/src/components" "$W32/notes"
printf '# readme\n' > "$W32/web-app/README.md"          # makes web-app/* expandable
printf 'gated: web-app/*\n' > "$W32/.4loops/config"
G32=$( cd "$W32" && VT_DIR="$W32/.4loops" bash -c '
  source "'"$S"'/vt-guard-lib.sh"
  echo "GLOBS:$(vt_gated_globs | tr "\n" ",")"
  vt_is_gated "'"$W32"'/web-app/src/components/Dashboard.jsx" "'"$W32"'" && echo NESTED:yes || echo NESTED:no
  vt_is_gated "'"$W32"'/web-app/README.md" "'"$W32"'"              && echo TOP:yes    || echo TOP:no
  vt_is_gated "'"$W32"'/notes/draft.txt" "'"$W32"'"                && echo OUT:yes    || echo OUT:no
' )
ck "globs: a config glob stays a pattern (no pathname expansion)" '[ "$(printf "%s" "$G32" | grep "^GLOBS:")" = "GLOBS:web-app/*," ]' "$G32"
ck "globs: nested product file IS gated (the dogfood miss)"       'printf "%s" "$G32" | grep -q "^NESTED:yes$"' "$G32"
ck "globs: top-level product file is still gated"                 'printf "%s" "$G32" | grep -q "^TOP:yes$"' "$G32"
ck "globs: a file outside the gated glob is NOT gated"            'printf "%s" "$G32" | grep -q "^OUT:no$"' "$G32"
# several globs on one config line must still split into several patterns
printf 'gated: web-app/* notes/*\n' > "$W32/.4loops/config"
G32B=$( cd "$W32" && VT_DIR="$W32/.4loops" bash -c 'source "'"$S"'/vt-guard-lib.sh"; vt_gated_globs | tr "\n" ","' )
ck "globs: two globs on one line still split (word-splitting kept)" '[ "'"$G32B"'" = "web-app/*,notes/*," ]' "$G32B"
# and the end-to-end guard agrees, through the real PreToolUse hook
printf 'gated: web-app/*\n' > "$W32/.4loops/config"
: > "$W32/.4loops/.armed"
GJ=$(printf '{"session_id":"S32","cwd":"%s","tool_input":{"file_path":"%s"}}' \
      "$W32" "$W32/web-app/src/components/Dashboard.jsx")
GOUT=$( cd "$W32" && printf '%s' "$GJ" | bash "$H/vt-gate.sh" 2>&1 )
ck "gate: stale + nested gated product file is DENIED end to end" 'printf "%s" "$GOUT" | grep -q "\"permissionDecision\"[[:space:]]*:[[:space:]]*\"deny\""' "$GOUT"
# the caller's noglob setting is restored either way
ck "globs: caller's noglob flag is left as it was" 'bash -c "source \"$S/vt-guard-lib.sh\"; export VT_DIR=\"$W32/.4loops\"; vt_gated_globs >/dev/null; case \$- in *f*) exit 1 ;; esac; set -f; vt_gated_globs >/dev/null; case \$- in *f*) exit 0 ;; esac; exit 1"'
rm -rf "$W32"
# ── /scope is gone (Track B dead — Ese lock 2026-09-13)
ck "scope: the skill directory is removed"                   '[ ! -d "$SK/scope" ]'
ck "scope: eight skills ship (was nine)"                     '[ "$(ls -d "$SK"/*/ | wc -l | tr -d " ")" = "8" ]'
ck "scope: no skill still points the user at /scope"         '! grep -rn "4loops:scope\|\`/scope\`" "$SK" >/dev/null 2>&1'
ck "scope: no capability named scope unlocks anything"       'bash -c "source \"$S/vt-guard-lib.sh\"; ! vt_cap_allows scope mutate && ! vt_cap_allows scope gateclear-week && ! vt_cap_allows scope gateclear-today"'
ck "scope: the rails survive and keep their tiers"           'bash -c "source \"$S/vt-guard-lib.sh\"; [ \"\$(vt_rail_tier vt-scope-promote)\" = mutate ] && [ \"\$(vt_rail_tier vt-scope-list)\" = readonly ]"'
ck "scope: the rails are marked UNSURFACED in their headers" 'grep -q "UNSURFACED" "$S/vt-scope-promote.sh" && grep -q "UNSURFACED" "$S/vt-scope-lib.sh"'
# ── locks 2-4: the docs must say what the code already does
source "$S/vt-guard-lib.sh"
ck "lock2: orientation deny says it covers the CODEBASE ONLY"     'vt_gate_directive | grep -q "CODEBASE ONLY"'
ck "lock2: orientation deny says the board is NOT frozen"         'vt_gate_directive | grep -qi "capability-gated" && vt_gate_directive | grep -qi "never orientation-gated"'
ck "lock2: /manage says a stale gate does not block it"           'grep -q "Stale orientation does not block .*/manage" "$SK/manage/SKILL.md"'
ck "lock2: /sync says the same"                                   'grep -q "Stale orientation does not block .*/sync" "$SK/sync/SKILL.md"'
ck "lock2: /week names the gate's real scope"                     'grep -q "gated product surfaces" "$SK/week/SKILL.md"'
ck "lock3: read-only carve-out stated in week/today/board/sync"   'grep -qi "read-only rails are never gated" "$SK/week/SKILL.md" && grep -qi "read-only rails are never gated" "$SK/today/SKILL.md" && grep -qi "read-only rails are never gated" "$SK/sync/SKILL.md" && grep -q "read-only rail" "$SK/board/SKILL.md"'
ck "lock3: the gate deny itself points at the read-only rails"    'vt_gate_directive | grep -q "vt-week --orient"'
ck "lock4: last-slash-wins is documented as intentional"          'grep -q "LAST SLASH WINS" "$S/vt-guard-lib.sh" && grep -q "last slash wins" "$SK/manage/SKILL.md" && grep -q "last slash wins" "$SK/sync/SKILL.md"'

echo "════ RESULT: $P passed, $F failed ════"
[ "$F" -eq 0 ]