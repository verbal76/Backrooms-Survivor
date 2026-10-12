# Branch strategy and release process (permanent)

## Branches
| Branch | Role | Rules |
|---|---|---|
| `dev` | **The single authoritative development and release source.** The rolling `dev` prerelease and every platform build come from its tip. | All validated work ends here. Releases are built only from its current tip. It must always contain `main`. |
| `main` | GitHub's default branch and the **record of owner-approved releases**. It is *not* a second source of truth and never receives work that is not already on `dev`. | Fast-forward only, from a `dev` SHA that passed validation, and only with explicit owner approval. May lag `dev`. Never developed on directly. |
| feature / repair / agent branches (`claude/*`, `worktree-agent-*`, ...) | Temporary workspaces with one purpose. | Start from the current `dev`; merged into `dev` after validation (PR into `dev`, or a validated fast-forward); never per-platform; not deleted without owner approval. |

Why `main` is not merged "for symmetry": verified 2026-10-12 via the GitHub API - neither `main` nor `dev` has branch
protection, no repository rulesets apply, and no workflow requires `main` to contain anything. The only coupling is the
`guard` job rule "the built SHA must contain `main`", which keeps `main` from ever holding work that `dev` lacks. GitHub
shows `main` (the default branch) on the repo page and `workflow_dispatch` needs workflow files on it, so when the owner
authorizes a release they may fast-forward `main` to the released `dev` SHA; until then `dev` is authoritative.

## Workflows (all under `.github/workflows/`)
- `build-all.yml` (reusable): `guard` (pins ONE SHA, `main` ancestry, policy check, branch inventory) -> `build`
  (smoke test, then Windows, Linux, Android and OTA patch exported from that SHA, `release_manifest.json` written) ->
  `verify` (fresh runner: manifest + hashes + SHA parity, then each artifact opened and its embedded build info
  checked). Any failure fails the run. No `continue-on-error`.
- `validate-build.yml`: runs `build-all.yml` in `validate` mode on pull requests (and manual dispatch). Read-only
  permissions, never publishes. This is how changes are proven before they reach `dev`.
- `dev-build.yml`: on push to `dev`, runs `build-all.yml` in `release` mode (SHA must equal the tip of `dev`) and, only
  if verification succeeded, replaces the rolling `dev` prerelease. **Pushing to `dev` publishes**, so it requires owner
  authorization.

## Release steps (owner-authorized)
1. Work lands on `dev` through a validated PR (the `validate-build` check must be green).
2. Owner approves publication; push/merge to `dev`. `dev-build.yml` builds, verifies and publishes.
3. Check `release_manifest.json` in the release: one source SHA for all four artifacts.
4. Optionally (owner approval) fast-forward `main` to that SHA.

## OTA
Unchanged: debug builds fetch `manifest.json` + `patch.pck` from the rolling release. Changes to boot code, export
presets, engine version or Android permissions need a new native build: bump `godot/min_base_build.txt`.

## Enforcement and tools
`python3 tools/policy_check.py`, `tools/branch_inventory.sh origin/dev`, `python3 tools/verify_release.py`,
`python3 tools/verify_artifacts.py`, `godot --headless --path godot -s tools/smoke_test.gd`.
