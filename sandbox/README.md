# Vibe Table — Sandbox

Disposable clean-room workspaces to dogfood `vt` exactly as a fresh user would. The
script automates the manual fresh-install setup, so the live walkthrough (B1–B5) is one
command and resettable.

```bash
sandbox/sandbox.sh new        # persistent isolated sandbox, injection, seeded board
```

It prints the exact `claude …` launch line. Open it, walk the steps, throw it away.

## Two modes

Two independent axes — config fidelity (does it work standalone?) and persistence (can I
live in it?). The two modes pick one pole of each:

| Mode | Location | Config | Loads vt via | Use it for |
| --- | --- | --- | --- | --- |
| `--isolated` (default) | `~/Ship/vt-sandbox/<name>/` (persistent) | hermetic | `--bare --settings` or real install | the true fresh-user env; B1–B5 |
| `--light` | `/tmp/vt-sandbox-<name>/` (throwaway) | your real config | `--plugin-dir` | fast flow/reconcile iteration |

`--light` is fast but **not** a "works standalone" proof — your global hooks still load.

## Two install paths (isolated only)

How `vt` actually reaches the session — different machinery, different coverage:

| Path | Mechanism | Tests | Skips |
| --- | --- | --- | --- |
| injection (default) | `claude --bare --settings sandbox-settings.json` — loaded in-place, no cache | runtime: B1, B2, B3, B5 | install-UX, B4 (no cache to go stale) |
| `--real-install` | `marketplace add` + `install` via `$HOME` override — real cache/versioning | install-UX (skills appear), **B4** | (slower per run) |

Run injection for the fast loop; run `--real-install` for the occasional full-fidelity + B4 pass.

## Seed

Each sandbox gets a **mock project tree** whose gated paths match `vt`'s real default
globs (`projects/*/{repo-scaffolding,content,gists}/*`), so the rail has real targets:

```
workspace/
├── .vibe-table/                    # seeded board (omitted with --empty)
├── projects/acme-demo/
│   ├── content/post.md             # GATED  → B1 blocks an edit here
│   ├── repo-scaffolding/README.md  # GATED
│   ├── gists/snippet.js            # GATED
│   └── src/app.js                  # allowed
└── study/notes.md                  # exempt → always allowed, even gate-up
```

- `--seeded` (default): stories across all states (seeded by driving the **real** `vt`
  CLI), the rail **pre-armed**, and **no focus set** — so the gate is *active* and B1 is
  demoable immediately. (The first armed session also performs the weekly rollover, which
  archives the seeded Done story — expected.)
- `--empty`: no board at all. Confirms `vt` is silent in a non-VT workspace, then you run
  **`/vt:configure`** — the first-run flow: it detects the mock tree's gated surfaces, you
  confirm projects + week-start, and bootstrap spawns this week's focus. The session should
  end on a board full of your stories, not a template.

## The walkthrough (seeded, isolated)

1. **B3** — launch; the sentinel dashboard renders (cwd = workspace root).
2. **B1** — ask Claude to **attempt** an edit to `projects/acme-demo/content/post.md` (don't
   let it pre-judge — make it run the Edit). The Edit tool returns the PreToolUse hook denial
   = the rail blocking. Then edit `study/notes.md` → **allowed** (exempt). (Drop `jq` off
   `PATH` to prove the `exit 2` fallback also blocks.) Seed files are neutral — the *path* is
   what's gated, so the rail (not the file's text) is what denies.
3. **B2** — a fresh board has no week stamp (new ISO week), so run `/vt:week` **then**
   `/vt:today`. Now retry the gated edit in the **same session** → must be **allowed** (the
   session-id handshake holds across the lift).
4. **B5** — `/vt:today` shows the 4-group `multiSelect` (starting / →testing / done / park);
   selections map back to story IDs.
5. **B4** (`--real-install` only) — edit a hook header, bump the version in both manifests,
   `/plugin update`, `/reload-plugins`, new session → confirm the new hook runs.

Record each as `#<step> · expected · actual · PASS/FAIL/SURPRISE · note`.

## Managing sandboxes

```bash
sandbox/sandbox.sh new [--light|--isolated] [--real-install] [--empty|--seeded] [name]
sandbox/sandbox.sh refresh <name>   # board back to seed (keeps the workspace)
sandbox/sandbox.sh list             # all sandboxes, both locations
sandbox/sandbox.sh rm <name>        # delete
```

Default name is `demo`. Light sandboxes live in `/tmp` (gone on reboot); isolated ones
persist under `~/Ship/vt-sandbox/` until you `rm` them.
