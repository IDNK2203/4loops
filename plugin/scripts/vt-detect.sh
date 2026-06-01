#!/usr/bin/env bash
# vt-detect.sh — read-only discovery for /configure. Scans a workspace root and
# emits candidate PROJECTS and candidate GATED (build/share) surfaces as TSV the
# skill turns into AskUserQuestion options. NEVER writes.
#
# Output lines (tab-separated):
#   PROJECT<TAB><dirname><TAB><suggested-prefix>
#   GATED<TAB><glob>                       (root-relative, deduped)
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

# Projects: (a) top-level dirs with a project marker, and (b) nested git repos
# (depth 2–3) — both forms named in the spec. Deduped by name.
{
  for d in "$ROOT"/*/; do
    [ -d "$d" ] || continue
    name=$(basename "$d")
    case "$name" in .*|node_modules|dist|build|public) continue ;; esac
    for m in .git package.json go.mod Cargo.toml pyproject.toml requirements.txt CLAUDE.md README.md; do
      [ -e "$d$m" ] && { printf 'PROJECT\t%s\t%s\n' "$name" "$(suggest_prefix "$name")"; break; }
    done
  done
  find "$ROOT" -maxdepth 4 \( -name node_modules -o -name .vibe-table \) -prune \
       -o -type d -name .git -print 2>/dev/null \
  | while IFS= read -r g; do
    pd=$(dirname "$g")
    [ "$pd" = "$ROOT" ] && continue          # the workspace's own repo, not a project
    name=$(basename "$pd")
    case "$name" in .*) continue ;; esac
    printf 'PROJECT\t%s\t%s\n' "$name" "$(suggest_prefix "$name")"
  done
} | sort -u

# Gated surfaces: build/share dirs (any depth up to 3) → generalized glob.
# Generalize the segment immediately before the matched dir to '*' so one glob
# covers every project (projects/p0/content → projects/*/content/*).
for pat in content dist build public out site _site gists; do
  find "$ROOT" -maxdepth 3 -name node_modules -prune -o -type d -name "$pat" -print 2>/dev/null
done | while IFS= read -r hit; do
  rel="${hit#"$ROOT"/}"
  printf '%s\n' "$rel"
done | awk -F/ '{
  n=NF
  if (n>=2) $(n-1)="*"
  s=$1; for(i=2;i<=n;i++) s=s"/"$i
  print "GATED\t" s "/*"
}' | sort -u
