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
- `release-build.yml` (manual only): the coordinated release (see "Coordinated releases" below).
- `dev-build.yml` (manual only): authorized OTA publication of the rolling `dev` prerelease (see docs/UPDATES.md). **It has no automatic
  trigger**: pushing/merging to `dev` publishes nothing.

## Release steps (owner-authorized)
1. Work lands on `dev` through a validated PR (the `validate-build` check must be green).
2. Owner decides what to ship and dispatches `release-build.yml` (coordinated native build) and/or `dev-build.yml` (OTA) manually,
   using the next number in the single sequence. Each run authorizes the dispatcher, re-checks the sequence and re-verifies provenance.
3. Check `build-manifest.json` / `release_manifest.json`: one source SHA for every artifact.
4. `main` is fast-forwarded to the released `dev` SHA.

## OTA
Unchanged: debug builds fetch `manifest.json` + `patch.pck` from the rolling release. Changes to boot code, export
presets, engine version or Android permissions need a new native build: bump `godot/min_base_build.txt`.

## Enforcement and tools
`python3 tools/policy_check.py`, `tools/branch_inventory.sh origin/dev`, `python3 tools/verify_release.py`,
`python3 tools/verify_artifacts.py`, `godot --headless --path godot -s tools/smoke_test.gd`.

## Verification record (non-publishing CI, 2026-10-12)
- Run `38195511435` (PR #4 head `f09665043998c5ee364ad84031b293701f922d52`): `guard`, `build`, `verify`, `result` all green. Windows,
  Linux, Android and OTA patch were exported from that single SHA; `verify` independently confirmed each artifact's
  format (MZ exe + pck, ELF x86-64 with exec bit, signed arm64 APK with package id, GDPC pck) and the embedded
  `build_info.json` carried the same full SHA. The existing `dev` release (build 12) and the `dev` branch/tag were not touched.
- Negative test, run `38195761637` (head `37c2f70`, Linux preset deliberately broken, since reverted): `Export Linux` failed, the
  patch/Android/manifest/upload steps were skipped, no artifact was uploaded, `verify` was skipped and `result` failed.
  A failure on any required platform therefore fails the whole validation; nothing can publish.

## Coordinated releases (`release-build.yml`, manual, never automatic)
Inputs: `platform` (`all` | `android` | `windows` | `linux`), `source_sha` (full SHA, must be the tip of `dev`),
`build_number` (integer), `destination` (`local_only` | `github_releases`, default `local_only`).
Preflight refuses: a malformed SHA or a SHA that is not the tip of `dev`; a dispatcher without the admin/maintain role, a ref other than `dev`, a build number that is not exactly latest + 1 of the single sequence (duplicates, stale numbers and gaps); `github_releases`
with anything but `platform=all` (a coordinated release never ships a missing platform).
Flow: preflight -> `build-all.yml` (one SHA, ONE build number stamped into build info, Android versionCode and the OTA
manifest; verified for exactly the requested platforms) -> `package_release.py` -> optional publish.
Assets of build NN: `Backrooms Survivor Build NN APK.apk`, `... EXE.zip`, `... Linux.tar.gz`, `checksums.sha256`
(`sha256sum -c` compatible), `build-manifest.json`. Publishing creates the immutable tag/release `build-NN`; it never
edits or replaces an existing release and never touches the OTA channel.
Status: added, local logic tested, **never run on GitHub**; the first hosted run needs owner approval.
Release signing is still debug-signed (R-4).

## Build-number ledger (verified 2026-10-12 via the GitHub API)
| Build | Kind | Source | Notes |
|---|---|---|---|
| 12 | rolling OTA prerelease `dev` ("Dev build 12") | `222225a` | the only release/tag in the repository; no `build-NN` tag exists |
Rule: see "Single number sequence" below.

## Single number sequence (R-2)
Native/coordinated builds (`build-NN` tags) and OTA patches share ONE sequence: next = `max(OTA channel build, build-NN tags) + 1`
(`tools/ci_guard.py sequence`). Because an installed build N ignores OTA patches numbered <= N, this also keeps OTA ordering valid.
The ledger above is the starting point: next number is 13.
