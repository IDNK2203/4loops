#!/usr/bin/env bash
# vt-detect.sh — read-only discovery for /configure. Scans a workspace root and
# emits candidate PROJECTS and candidate GATED (build/share) surfaces as TSV the
# skill turns into AskUserQuestion options. NEVER writes.
#
# Output lines (tab-separated):
#   PROJECT<TAB><dirname><TAB><suggested-prefix>   git repos (the auto-suggest heuristic)
#   AREA<TAB><dirname>                             non-repo top-level folders (untracked candidates)
#   GATED<TAB><glob>                               build/share surfaces, per-repo (root-relative, deduped)
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

# Projects: git repos at any depth (2–4), excluding the workspace's own root repo.
# A git repo is the high-confidence *auto-suggest* — /configure lets the user
# promote an Area (non-repo folder) to a Project, or demote a suggestion. We do
# NOT treat a bare marker file (README/package.json) as a project on its own:
# that wrongly tracked plain doc folders. Track at the repo boundary.
find "$ROOT" -maxdepth 4 \( -name node_modules -o -name .vibe-table \) -prune \
     -o -type d -name .git -print 2>/dev/null \
| while IFS= read -r g; do
  pd=$(dirname "$g")
  [ "$pd" = "$ROOT" ] && continue            # the workspace's own repo, not a project
  name=$(basename "$pd")
  case "$name" in .*) continue ;; esac
  printf 'PROJECT\t%s\t%s\n' "$name" "$(suggest_prefix "$name")"
done | sort -u

# Areas: top-level folders that contain NO git repo — neither a Project (a repo)
# nor project-space (a parent that houses repos). These are evolving/untracked
# folders (notes, docs, context). /configure offers them for promotion; untracked
# by default.
for d in "$ROOT"/*/; do
  [ -d "$d" ] || continue
  name=$(basename "$d")
  case "$name" in .*|node_modules|dist|build|public) continue ;; esac
  # No `| head`: under set -e + pipefail, head closing the pipe SIGPIPEs find and
  # aborts the script. Let find complete (exit 0); emptiness ⇒ no repo ⇒ an Area.
  found=$(find "$d" -maxdepth 4 \( -name node_modules -o -name .vibe-table \) -prune \
               -o -type d -name .git -print 2>/dev/null)
  # `if` (not `&&`): a trailing `&&` that short-circuits makes the loop body — and
  # thus the `… | sort` pipeline — exit non-zero, which set -e would treat as fatal.
  if [ -z "$found" ]; then printf 'AREA\t%s\n' "$name"; fi
done | sort -u

# Gated surfaces: build/share dirs (depth ≤3) → literal per-repo glob. We do NOT
# generalize the parent segment to '*' (the old projects/*/content/* form) — track
# at the repo boundary so each project's surfaces gate explicitly.
for pat in content dist build public out site _site gists; do
  find "$ROOT" -maxdepth 3 -name node_modules -prune -o -type d -name "$pat" -print 2>/dev/null
done | while IFS= read -r hit; do
  rel="${hit#"$ROOT"/}"
  printf 'GATED\t%s/*\n' "$rel"
done | sort -u
