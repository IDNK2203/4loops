# Good first issues — seed list

Seed these as actual GitHub issues at repo launch with the `good first issue` label. Goal: 3–5 visible entry points for first-time contributors. Curate against the live backlog before launch.

---

## #1 — Make the default gated-globs portable

**Label**: `good first issue`, `enhancement`

**Why**: The PreToolUse gate's default gated surfaces are `projects/*/repo-scaffolding/*`, `projects/*/content/*`, `projects/*/gists/*` — a layout specific to one workspace. A fresh user's gate matches nothing useful unless they hand-write `.vibe-table/config`. The default should be universal (or opt-in), with config documented.

**Where**: `vt_gated_globs()` in `plugin/scripts/vt-guard-lib.sh`.

**Acceptance**:
- A fresh workspace gets a sensible default (or a clearly-documented opt-in)
- `.vibe-table/config` `gated:` override behavior is documented in the README
- `tests/run.sh` covers the default + an override case

**Size**: ~30 lines.

---

## #2 — Document the focus gate + SessionStart sentinel

**Label**: `good first issue`, `docs`

**Why**: New users see a banner at session start and hit a gate on writes, without a single page explaining the model (date-stamp staleness, per-session clearance, the override, what's exempt).

**Where**: `docs/the-gate.md` (new). Link from the README "How it enforces" section.

**Acceptance**:
- Explains gate-active vs cleared, per-session carry-across-midnight, and `VT_ALLOW_STALE_GATE=1`
- Lists exempt surfaces (research/notes always flow)
- ≥200 words, ≤500 words

**Size**: docs only.

---

## #3 — Implement `/vt:recall` over the archive

**Label**: `good first issue`, `enhancement`

**Why**: Closed and abandoned stories live in `.vibe-table/archive/` and every transition in `transitions.log`, but there is no way to query them. A `/vt:recall` makes past work retrievable.

**Where**: new `plugin/skills/recall/SKILL.md` + `plugin/scripts/vt-recall.sh`; register in `plugin/.claude-plugin/plugin.json`.

**Acceptance**:
- `/vt:recall <query>` searches `archive/*/closed.md` + `abandoned.md` + `transitions.log`
- Supports `--project`, `--state`, `--since`
- A `tests/run.sh` case asserts a known archived ID is found

**Size**: ~60 lines.

---

## #4 — Audit the `jq`-absent fallbacks

**Label**: `good first issue`, `chore`

**Why**: The hooks claim graceful degradation without `jq` (a sed-based `vt_json_field`, exit-2/stderr deny path). That path is less exercised than the `jq` path and may drift.

**Where**: `vt_json_field()` / `vt_emit_deny()` in `plugin/scripts/vt-guard-lib.sh`; the sentinel's stdout fallback in `plugin/hooks/sentinel.sh`.

**Acceptance**:
- A `tests/run.sh` case runs a guard with `jq` masked off `PATH` and asserts correct allow/deny
- Any drift between the two paths is fixed or documented

**Size**: ~40 lines.

---

## Authoring tips for issue seeding

- Title: imperative + scope-tagged. `Add X to Y`, `Fix Z when W`, `Document N`.
- Body sections (mandatory): _Why_ / _Where_ / _Acceptance_ / _Size_.
- Link to the relevant file(s) by path.
- Tag `good first issue` only if a competent contributor unfamiliar with the codebase could land it in ≤2 hours.
