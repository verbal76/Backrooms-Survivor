# Universal Engineering Directive: Single Source of Truth, Cross-Platform Builds, Branch Recovery

Permanent repository-level engineering policy (owner directive, 2026-10-12). Applies to all development, builds,
releases and restructuring in this repository. The short operating version for agents is in `/CLAUDE.md`; this file is
the full policy. Enforcement scripts: `tools/policy_check.py`, `tools/branch_inventory.sh`, `tools/verify_release.py`,
`godot/tools/smoke_test.gd`, and the `guard`/`verify` jobs in `.github/workflows/dev-build.yml`.

## 1. Fundamental architecture rule
One authoritative, continuously integrated source codebase. Platforms are build targets of that one source, not
independent versions. Android, Windows, Linux/Steam Deck (and any future iOS/macOS/web) derive from the same source
revision whenever they are the same release. Use the mechanism that fits the stack (here: GDScript shared modules,
per-platform adapters such as `systems/input.gd` and `scripts/platform/*`, Godot export presets and feature tags).
Do not introduce a new engine, framework or build system to satisfy this policy. One codebase does not mean one binary.

## 2. Platform parity
Core behavior (gameplay systems, physics, progression, procedural generation, AI, balance, content) is shared and
identical on every platform. Allowed, isolated and documented differences: touch vs keyboard/mouse vs gamepad
controls, OS integrations, rendering/quality settings required by hardware. Differences are listed in
`docs/PLATFORMS.md`. A fix on one platform must be evaluated against all supported platforms. No platform may fall
behind the authoritative line.

## 3. Branches are temporary workspaces
Feature, repair and agent/worktree branches may exist when justified, must originate from the current authoritative
line, have one clear purpose, and be integrated after validation. They must not become permanent independent histories
or per-platform products. Release workflows must not build from abandoned or outdated branches. Parallel agents must
not maintain separate implementations of the same application. Unmerged work must remain discoverable
(`tools/branch_inventory.sh`, `docs/RECOVERY_LEDGER.md`). Platform names in branch names grant no permission to fork.

## 4. Abandoned-branch recovery audit
Maintain a forensic inventory (commit ancestry, merge bases, patch equivalence, file and semantic comparison - not
branch names or commit counts). Classify work as: already integrated; integrated through an equivalent implementation;
missing and suitable for recovery; missing but requiring conflict resolution; superseded; intentionally removed;
experimental/incomplete; unknown (owner review). Keep the ledger in `docs/RECOVERY_LEDGER.md` (branch, SHA, description,
classification, disposition). Do not auto-restore everything, do not delete branches because they look obsolete.

## 5. Recovering missing work
Prefer targeted integration over blind merges; preserve current behavior, UX, visual identity, data compatibility and
performance; do not reintroduce obsolete or rejected systems. If the right choice is uncertain or materially changes the
product, ask the owner.

## 6. Unified build and release architecture
One source-selection mechanism: the `guard` job pins the full SHA of `dev`; every platform checks out that SHA. Every
build records: exact commit SHA, source ref, application version, target platform, build configuration, engine/toolchain
versions and build timestamp (`godot/build_info.json` inside the app; `release_manifest.json` in the release). A
coordinated release uses the same SHA for every target. If a platform fails validation the whole release fails - no
silent substitution of another revision.

## 7. OTA and native compatibility
Keep the validated OTA pipeline (`patcher.gd`, `boot.gd`, `manifest.json`, `min_base_build.txt`). A change that touches
boot code, export presets, engine version, native dependencies or Android permissions requires a new native binary:
bump `godot/min_base_build.txt`. OTA never creates a second source history; patches are traceable to the SHA recorded in
`manifest.json`/`release_manifest.json`.

## 8. Automated enforcement
Implemented: guard job (release only from `dev`, `dev` must contain `main`), SHA pinning, repository policy check,
read-only branch inventory in the CI summary, shared smoke test before any export, no `continue-on-error`, release
manifest with per-artifact hashes and source SHA, verify job enforcing SHA parity and presence of every required
platform artifact, publish only after verification. Keep enforcement simple and deterministic.

## 9. Preserve the existing product
This is an architectural correction, not a redesign. Do not change established feel, physics, scope, visual identity,
workflows, save data formats (without migration), application identifiers, working OTA compatibility, or signing and
release credentials. Do not degrade a working platform to achieve parity.

## 10. Persistent instructions
This policy is recorded in `/CLAUDE.md` (read by Claude Code agents) and here, and is checked by
`tools/policy_check.py` in CI. Every change belongs to one authoritative product history; every supported platform builds
from it; every abandoned branch is accounted for before valuable work is discarded.

## 11. Repository boundaries
Applies per repository. Do not access, inspect, clone, modify or merge another repository without explicit
authorization; do not consolidate unrelated projects.

## 12. Execution authority (agents)
Allowed: audit, inspect history, document recovery candidates, implement safe architectural corrections, add build/CI
safeguards, run local tests, commit validated changes on a working branch. Not allowed without owner approval:
publish APK/EXE or other artifacts, deploy OTA, trigger production publishing, delete branches, rewrite shared history,
merge into protected production branches, access unrelated repositories, redesign the app, restore uncertain or
intentionally abandoned features, take destructive/irreversible actions.

## 13. Final operating principle
We are developing ONE GAME that runs on Android, Windows and Linux/Steam Deck. One authoritative codebase, one
integrated history, multiple build targets, no silent platform divergence, no forgotten completed work.

## 14. Permanent branch strategy (verified 2026-10-12)
`dev` is the single authoritative development and release source. `main` is only the default-branch record of
owner-approved releases: fast-forward from a validated `dev` SHA with owner approval, never a source of new work, and
allowed to lag. Verified facts: no branch protection and no rulesets exist, and no workflow requires `main` to match `dev`;
the only coupling is the guard rule "the built SHA must contain `main`". Builds are validated on pull requests by
`validate-build.yml` (non-publishing, same jobs as release) and published only by `dev-build.yml` after
verification. Details and the verification record: `docs/RELEASE.md`.
