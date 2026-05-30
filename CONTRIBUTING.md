# Contributing to Vibe Table

Thanks for considering a contribution. Vibe Table is a Claude Code plugin — all bash + markdown, no build step. Below is what you need to land a PR fast.

## Ground rules

1. **One PR, one concern.** Bug fixes and refactors do not share a PR.
2. **Open an issue first** if the change is larger than ~50 lines or adds a new skill/hook. Saves both of us from a wasted afternoon.
3. **Match the existing style.** No reformatting unrelated code. Hooks fail open — a guard bug must never brick the user's ability to work.
4. **No secrets, ever.**

## Dev setup

```
git clone https://github.com/idnk2203/vibe-table.git
cd vibe-table
```

There is no install/build step. To exercise changes, enable the plugin from the local marketplace in a scratch workspace:

```
/plugin marketplace add /path/to/vibe-table
/plugin install vt
```

Then drive the loop (`/vt:today`, `/vt:board`, …) in that workspace. State lands in `<workspace>/.vibe-table/`.

## Running tests

```
bash tests/run.sh
```

Tests must pass before merge. They are plain bash assertions over the scripts and hooks — no test runner required.

## Authoring a new skill

1. Create `plugin/skills/<your-skill>/SKILL.md` with frontmatter (`name`, `description`, `allowed-tools`, `user-invocable`).
2. Put the executable logic in `plugin/scripts/vt-<your-skill>.sh` (sourced libs are not `chmod +x`).
3. Register any hook in `plugin/.claude-plugin/plugin.json`.
4. Add a case to `tests/run.sh`.
5. Update the README "The loop" table if the command is user-facing.

## Commit conventions

```
<type>(<scope>): <subject>
```

Types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`. Scope is the directory or skill name.

Examples:
- `feat(skills/recall): add /vt:recall over the archive`
- `fix(hooks/vt-gate): exempt workspace-root docs`
- `docs(readme): clarify the focus gate`

## Reporting issues

Use the bug-report or feature-request templates. Reproducible steps are non-negotiable for bugs.

## License

By contributing, you agree your contribution is licensed under MIT (the project license).
