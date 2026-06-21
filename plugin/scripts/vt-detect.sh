#!/usr/bin/env bash
# vt-detect.sh — read-only discovery for /configure. Scans a workspace root and
# emits candidate PROJECTS and candidate GATED (build/share) surfaces as TSV the
# skill turns into AskUserQuestion options. NEVER writes.
#
# Output lines (tab-separated):
#   PROJECT<TAB><dirname><TAB><suggested-prefix>   git repos (the auto-suggest heuristic)
#   AREA<TAB><dirname>                             non-repo top-level folders (untracked candidates)
#   GATED<TAB><glob>                               each project's WHOLE dir (<project>/*), root-relative
#
# Usage: vt-detect.sh [root]   (root defaults to $PWD)
set -euo pipefail

ROOT="${1:-$PWD}"
ROOT="${ROOT%/}"

# Suggested prefix = uppercased initials of hyphen/underscore/space tokens,
# capped at 3 chars; fall back to the first two letters if that yields <2.
suggest_prefix() {
  local name="$1" p
  p=$(printf '%s' "$name" | awk -F'[-_ ]+' '{s=""; for(i=1;i<=NF;i++) if($i!="") s=s substr($i,1,1); print toupper(s)}')
  p=$(printf '%s' "$p" | tr -cd 'A-Z0-9')
  if [ "${#p}" -lt 2 ]; then
    p=$(printf '%s' "$name" | tr -cd 'A-Za-z' | tr '[:lower:]' '[:upper:]' | cut -c1-2)
  fi
  printf '%s' "${p:0:3}"
}

# Collect git repos (excluding node_modules/.4loops), separating the
# workspace's OWN root repo from nested ones — they imply different shapes:
#   nested repos present        → workspace mode (each nested repo is a project)
#   no nested but root is a repo → mono/root mode (the root IS the single project)
# A git repo is the high-confidence auto-suggest; /configure lets the user promote
# an Area or demote a suggestion. We do NOT treat a bare marker file on its own
# as a project (that wrongly tracked plain doc folders) — track at the repo boundary.
ALL_GITS=$(find "$ROOT" -maxdepth 4 \( -name node_modules -o -name .4loops \) -prune \
     -o -type d -name .git -print 2>/dev/null)
NESTED=""; ROOT_IS_REPO=0
while IFS= read -r g; do
  [ -z "$g" ] && continue
  pd=$(dirname "$g")
  if [ "$pd" = "$ROOT" ]; then
    ROOT_IS_REPO=1
  else
    case "$(basename "$pd")" in .*) continue ;; esac
    NESTED="${NESTED}${pd}"$'\n'
  fi
done <<EOF
$ALL_GITS
EOF
NESTED=$(printf '%s' "$NESTED" | awk 'NF' | sort -u)

{
  if [ -z "$NESTED" ] && [ "$ROOT_IS_REPO" = 1 ]; then
    # Mono/root mode: the workspace root itself is the project; gate the WHOLE
    # thing ('*' spans everything — hard-exempt paths still flow). No Areas:
    # top-level folders are part of the root project, not separate.
    name=$(basename "$ROOT")
    printf 'PROJECT\t%s\t%s\n' "$name" "$(suggest_prefix "$name")"
    printf 'GATED\t*\n'
  else
    # Workspace mode: nested repos are projects (whole-project gated, <project>/* —
    # the gate's '*' spans slashes, so it covers everything inside). Non-repo
    # top-level folders are Areas: evolving/untracked, promotable in /configure.
    while IFS= read -r pd; do
      [ -z "$pd" ] && continue
      name=$(basename "$pd")
      printf 'PROJECT\t%s\t%s\n' "$name" "$(suggest_prefix "$name")"
      printf 'GATED\t%s/*\n' "${pd#"$ROOT"/}"
    done <<EOF
$NESTED
EOF
    for d in "$ROOT"/*/; do
      [ -d "$d" ] || continue
      name=$(basename "$d")
      case "$name" in .*|node_modules|dist|build|public) continue ;; esac
      # No `| head`: under set -e + pipefail, head SIGPIPEs find and aborts. Let
      # find complete (exit 0); emptiness ⇒ no repo inside ⇒ an Area.
      found=$(find "$d" -maxdepth 4 \( -name node_modules -o -name .4loops \) -prune \
                   -o -type d -name .git -print 2>/dev/null)
      # `if` (not `&&`): a short-circuiting trailing `&&` makes the loop/pipeline
      # exit non-zero, which set -e would treat as fatal.
      if [ -z "$found" ]; then printf 'AREA\t%s\n' "$name"; fi
    done
  fi
} | sort -u
