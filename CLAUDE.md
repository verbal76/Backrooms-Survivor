# Backrooms Survivor - instructions for every developer and AI agent

One game, one codebase. The LÖVE2D Lua files in the repo root are the **legacy reference implementation** of the same
game (kept until the owner signs off full parity; never built or shipped). The product is the Godot 4.3 project in
`godot/` which builds Android, Windows and Linux/Steam Deck from the same source.

Read before working: `godot/ARCHITECTURE.md` (system contract), `docs/PLATFORM_SUPPORT.md` (platform differences),
`docs/BRANCH_LEDGER.md` (branch accounting), `godot/docs/BALANCE.md`, `docs/STEAM_HARDWARE_CHECKLIST.md`.

## SINGLE-SOURCE-OF-TRUTH POLICY (mandatory; full text: docs/ENGINEERING_POLICY.md)

Every change belongs to ONE authoritative product history. Every supported platform builds from that history.
Every abandoned branch must be accounted for before valuable work is discarded.

1. **One codebase, many targets.** Android, Windows, Linux/Steam Deck are build targets of the same `godot/` source -
   never separate versions. Platform differences are isolated (input schemes in `systems/input.gd`, `scripts/platform/*`,
   per-target export presets) and documented in `docs/PLATFORM_SUPPORT.md`. A fix for one platform is evaluated for all of them.
   Do not change gameplay, balance, physics or content per platform.
2. **Authoritative line = `dev`** (the integration/release branch; it must always contain `main`). `main` is only the record of
   owner-approved releases (fast-forward from a validated `dev` SHA, owner approval required) - never a second source of truth.
   See `docs/RELEASES.md` (manual coordinated release: `release-build.yml`; OTA stays separate). Feature/agent/repair branches are temporary workspaces: they
   start from the current `dev`, have one purpose, and are merged back into `dev` after validation. Never maintain a
   branch (or branch name) per platform, never fork the app per agent, never leave finished work unmerged.
3. **Agents/worktrees:** branch from current `dev` (`git merge`/branch from it first), keep changes scoped, report the
   branch + SHA, and make sure the integrator merges it. Do not delete branches; run `tools/branch_inventory.sh` to see
   unmerged work and record disposition in `docs/BRANCH_LEDGER.md`.
4. **Releases:** all artifacts of one release come from the SAME full source SHA, pinned by the `guard` job of
   `.github/workflows/build-all.yml`, recorded in `release_manifest.json`, and checked by `tools/verify_release.py`.
   No platform step may be skipped silently (no `continue-on-error`). If a platform fails, the release fails.
   `validate-build.yml` runs the same build/verify jobs without publishing (use it on PRs). Publishing/OTA only happens through
   the MANUAL workflows `dev-build.yml` (OTA) and `release-build.yml` (coordinated release). Nothing publishes automatically: a push, merge, tag,
   PR or schedule never publishes. Both gate on the dispatcher's repository role (admin/maintain), the live `dev` tip and ONE shared
   build/OTA number sequence (latest + 1); see `docs/RELEASES.md`. Agents must not publish, dispatch these workflows, trigger releases or deploy OTA
   unless the owner explicitly asks in the current conversation.
5. **OTA:** keep the existing pipeline (`godot/scripts/patcher.gd`, `boot.gd`, `min_base_build.txt`, `manifest.json`). If boot
   code, export presets, engine version or Android permissions change, bump `godot/min_base_build.txt` (a native build is
   required). OTA is never a second source history.
6. **Preserve the product:** don't change established feel, scope, visual identity, save formats (without migration),
   application ids or signing without owner approval. Destructive or irreversible actions need approval.
7. **Repository boundaries:** this policy applies per repository. Never access, merge or consolidate other repositories
   unless explicitly authorized.

### Enforcement (run these; CI runs them)
- `python3 tools/policy_check.py` - this policy exists and the release workflow has not regressed.
- `godot --headless --path godot -s tools/smoke_test.gd` - shared smoke test (must print `SMOKE TEST PASSED`).
- `godot --headless --path godot -s tools/regression_tests.gd` - regression tests for playtest defects (all must PASS).
- `tools/branch_inventory.sh origin/dev` - read-only branch accounting.
- `python3 tools/verify_release.py <out-dir> --sha <40-char-sha>` - release manifest / SHA-parity gate.
- `python3 tools/verify_artifacts.py <out-dir> --sha <40-char-sha>` - opens each platform artifact and checks the embedded source SHA.

## Working in `godot/` (quick rules)
- GDScript 4.3; headless import first: `godot --headless --import --path godot`.
- Don't commit `.godot/`. Commit under `godot/`, `tools/`, `docs/`, `.github/`.
- `project.godot` must keep `textures/vram_compression/import_etc2_astc=true` (Android export fails validation silently without it).
- Android debug export needs a full SDK (cmdline-tools, platform-tools, build-tools 34.0.0, android-34); the CI installs it.
