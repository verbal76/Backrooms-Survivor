# Recovery ledger (branch accounting)

Audit date: 2026-10-12. Method: ref/ancestry inventory of all local and remote branches, tags, worktrees and releases;
`git rev-list` against the authoritative line; `git cherry` patch equivalence; per-worktree uncommitted-change check;
file/semantic review of superseded or intentionally changed behavior. Regenerate the table any time with
`tools/branch_inventory.sh origin/dev` (read-only).

**Authoritative line: `dev`** @ `222225a25d7b557b52b622783a699e00e2ac0883` (identical to
`claude/fervent-franklin-hrrnb7` and PR #4's head; the rolling release `dev` and tag `dev` point to the same SHA).
`main` (`33c8e64`, protected production) is an ancestor of it and 41 commits behind; bringing `main` up to date needs the
owner's approval, but nothing requires it (see `docs/RELEASES.md`).

## Branches, tags, releases

| Ref | Tip | Purpose | Classification | Proposed disposition |
|---|---|---|---|---|
| `origin/dev` | 222225a | integration/release line, source of the rolling `dev` release | **Authoritative** | keep |
| `claude/fervent-franklin-hrrnb7` (local+origin) | 222225a | working branch of the Godot port; PR #4 head | Integrated (identical to dev) | keep until PR #4 is merged by owner |
| `origin/main` | 33c8e64 | protected production branch (PR #3 merged) | Integrated (ancestor), outdated | owner merges PR #4 |
| `origin/claude/jolly-cori-g4l8rg` | 916c3e1 | PR #2: folder reorg, Godot skeleton, CC0 assets | Integrated (all commits reachable from dev; its content merged via #3/#4) | owner may close PR #2 as superseded; do not delete without approval |
| `origin/claude/exciting-cerf-8bng06` | 075d2fd | PR #1: LÖVE shortcuts | Obsolete (machine-specific LÖVE shortcuts + local settings file); PR #1 **closed** 2026-10-12 after verification | branch preserved (not deleted); see item L-1 |
| local `main` | f57a2ac | stale local copy of an early commit | Integrated (ancestor) | none (local only) |
| `worktree-agent-a26b4377...` | bb4fe49 | Steam Deck / Linux pass | Integrated | local only; delete only with approval |
| `worktree-agent-a284b0ba...` | 43e5c6a | lighting + FX + chunk visuals | Integrated | same |
| `worktree-agent-a2ecacd0...` | 4cc7a8d | combat (weapons/bombs) | Integrated | same |
| `worktree-agent-a3d64a64...` | 79f7c9a | UI, input, meta progression | Integrated | same |
| `worktree-agent-a88aa55f...` | b3d7fbc | juice pass + held-weapon fix | Integrated | same |
| `worktree-agent-a993d463...` | e707c62 | crow enemy | Integrated | same |
| `worktree-agent-aa324b4b...` | fc9f4e7 | enemies | Integrated | same |
| `worktree-agent-aa86ab5f...` | d42f0de | world objects | Integrated | same |
| `worktree-agent-abcdaf49...` | 9161a5a | tutorial, controls, touch, intro | Integrated | same |
| `worktree-agent-adadeafa...` | f6e9f12 | balance pass + sim harness | Integrated | same |
| `worktree-agent-ae125020...` | 3ae576a | audio system | Integrated | same |
| `worktree-agent-afed0be9...` | 09866dc | traps | Integrated | same |
| tag/release `dev` | 222225a | rolling prerelease (dev build 12: apk, zip, tar.gz, patch.pck, manifest.json) | Built from the authoritative SHA | keep; it is rebuilt from `dev` only |

All 12 worktree branches have 0 commits and 0 patch-unique commits relative to `dev`, and no worktree has uncommitted
tracked changes (one untracked `crow_sheet.png.import` was already committed on the authoritative line).

## Findings by audit category

1. Branches with commits not reachable from the authoritative line: only `origin/claude/exciting-cerf-8bng06` (1 commit).
2. Completed features never integrated: none. Every feature branch (combat, enemies, objects, UI, audio, FX/juice,
   tutorial/controls, balance, crow, traps, Steam Deck) is reachable from `dev`.
3. Bug fixes only on abandoned branches: none found.
4. Performance improvements lost: none found (Deck occluder merge and quality presets are on `dev`).
5. UI/visual improvements missing from current builds: none found. Builds 1-12 were produced from ancestors of `dev`
   and dev build 12 is the authoritative SHA.
6. Platform fixes that never reached other platforms: none. Android's ETC2/ASTC project setting and the CI SDK install
   are in shared project/CI config; Linux/Steam Deck work is in shared code plus an extra export preset.
7. Assets/config/build improvements left behind: none on branches. Known absent by owner decision/license: the
   restricted asset packs (Post Apoc Office, Abandoned Office, Low Poly PSX, Glass UI, scarymobs) and the owner's
   earlier game folders (`BUILD_APK`, `Older versions`, `BR-isometric V1`, `new files temp`) were never in this repo.
8. Experimental work still valuable: none outstanding (traps minimap markers and enemy trap-avoidance are
   documented non-goals in the traps report).
9. Reverted/changed behavior investigated (all intentional or superseded):
   - Held-weapon mirroring: my negative-rect-height fix was **superseded** by the juice agent's
     transform-based fix with hand anchors (`weapon_view.gd`); verified by rendering at 8 angles.
   - Flee-from-headlamp enemy AI: **intentionally removed** (`FLEE_FROM_LIGHT=false`) because the Lua light level was a
     constant so enemies never fled; it made enemies hover outside melee reach.
   - Overlap contact damage (Lua) replaced by reach-based wind-up attacks: **intentional behavior change** (owner request).
   - Stamina/difficulty numbers changed by the balance pass: **intentional**, documented old->new in `godot/docs/BALANCE.md`.
10. Releases built from commits no longer in active development: none; the only release is the rolling `dev` release
    (previous builds 1-11 were replaced in place and were all ancestors of `dev`).

## Open items

- **L-1 (resolved: PR closed, branch kept) `origin/claude/exciting-cerf-8bng06` @ 075d2fd, PR #1 (draft):** adds `Documentation.url`, `LOVE.lnk`,
  `Uninstall.lnk` (Windows shortcuts from a LÖVE install) and `.claude/settings.local.json` (a machine-local agent
  settings file). Not recovered: unrelated to the Godot product, machine-specific, and the settings file should not be
  versioned. Verified that no Godot functionality or installer behavior is lost (the LÖVE packaging files `_installer.iss` and `BUILD_ALL_AND_EXECUTABLE.bat` are already on `dev`). PR #1 was closed; its branch is preserved. No branch has been deleted.
- **L-2:** PR #2 (draft) is superseded by #3/#4; owner may close it.
- **L-3:** `main` lags `dev` by design (see `docs/RELEASES.md`): no protection or workflow requires it to match; it is fast-forwarded to a released `dev` SHA only with owner approval.
- **L-4:** 12 local `worktree-agent-*` branches exist only locally. All their work is on `dev`; delete them only with approval.

## Owner decision register R-1 .. R-6 (resolved 2026-10-12 for everything an agent may do)
Original wording of each item is kept in the first line.

**R-1 - RESOLVED 2026-10-12 (see Integration record). "fast-forward `main` to a validated `dev` SHA (stale unguarded workflow on `main`)". RED.**
`main` = `33c8e64`, which still carries the old `dev-build.yml` (push trigger, `continue-on-error`, no SHA guard). `dev` = `222225a`;
the PR #4 branch contains both and is 12 commits ahead of `dev`. Alternatives: (a) leave as is until release; (b) validate the PR
branch, merge it into `dev`, then fast-forward `main` to that exact SHA; (c) merge PR #4 straight into `main` (its current base)
and fast-forward `dev`. Consequences: no effect on saves, Android/Windows/Linux artifacts or OTA until a push to `dev` happens;
Steam: none. Recommendation: (b), after the owner signs off. Needs the owner (protected branch). Action taken: none.

**R-2 - RESOLVED 2026-10-12 (see Integration record). "stop `dev-build.yml` auto-publishing the OTA channel on push to `dev`". RED.**
Every push to `dev` replaces the rolling `dev` prerelease and so what installed dev builds download. Alternatives: (a) keep;
(b) replace the push trigger with a manual `workflow_dispatch`-only OTA publish; (c) keep automatic OTA but only from a manual
release. Consequences: (b) removes the accidental-publish path (matches the master standard); installed players keep working
(same manifest URL); the OTA and coordinated build numbers must share one sequence (see docs/RELEASES.md ledger caveat).
Recommendation: (b), implemented together with R-1. RED because it changes the production OTA pipeline. Action taken: documented,
a build-number guard (coordinated number must exceed the OTA channel build) added to `release-build.yml`; `dev-build.yml` unchanged.

**R-3 - "OTA authenticity signature + known-good retention/rollback (boot code => native build + `min_base_build.txt` bump)". RED.**
Verified in code (docs/UPDATES.md): SHA-256 integrity, staged download, safe fallback to base on interruption; no signature, no rollback.
Alternatives: (a) accept for dev/test builds and keep OTA out of store builds; (b) add Ed25519 signature check + keep previous patch with
crash-count rollback (needs boot code change => new native APK, `min_base_build` bump, players reinstall once). Recommendation: (a) now,
(b) before OTA is offered beyond the owner's own test devices. RED (native runtime / installed-player compatibility). Action: none.

**R-4 - "release signing (currently debug-signed), Steamworks / GodotSteam / Steam Cloud / Steam text input". RED.**
Debug keystore signs the APK; no release keystore exists (changing signing = players cannot update in place). Steam needs release
export presets without the OTA updater (preset change => native build decision), an App ID, depots, optional GodotSteam. Alternatives:
create a release keystore stored only in a GitHub secret and used by a separate manual job; or keep debug-signed for the test channel.
Recommendation: owner creates the release keystore + Steam app; agents then add release presets and the signing job. Prepared (GREEN):
`tools/steampipe/` templates with placeholders. Action: none beyond templates.

**R-5 - "first hosted run of `release-build.yml`; licence confirmation for Blackcraft.ttf and audio". RED (hosted build + legal).**
Workflow logic is locally tested (`tools/test_release_tools.py`, actionlint, policy_check) but never executed on GitHub. Recommendation:
after R-1/R-2, run once with `platform=all`, `destination=local_only` on a validated `dev` SHA, then inspect artifacts before any
`github_releases` run. Licences: the owner must supply the source/licence for the font and each music/sound file (docs/THIRD_PARTY_ASSETS.md);
if unobtainable, replace with CC0 assets. Action: inventory and attribution list kept current.

**R-6 - "physical-device testing (phone, Windows, Linux, Steam Deck)". RED (requires hardware and the owner).**
Nothing has been run on real devices; all evidence is headless/software-rendered. Checklist: docs/STEAM_HARDWARE_CHECKLIST.md.
Recommendation: one pass per device class before any public release. Action: none possible by an agent.

## Integration record (R-1 / R-2 authorized by the owner, 2026-10-12)
- R-2 implemented in `e33d7d9`: `dev-build.yml` is manual-only (`workflow_dispatch`), authorized by the dispatcher's repository role
  (admin/maintain), one shared build/OTA number sequence (next = latest + 1; currently 13), source = live tip of `dev`, all gates
  repeated inside the publish job (docs/UPDATES.md "Publishing architecture"). Enforced by `tools/workflow_rules.py` (policy_check) and
  `tools/test_release_tools.py`.
- Validation of exactly `e33d7d9`: PR validation run 38314022771 green (policy, tests, result; `full` skipped), plus local smoke test,
  25/25 regression checks, 110+ release-tool checks, actionlint, policy_check.
- R-1 executed with non-forced fast-forwards of the validated SHA: `dev` `222225a` -> `e33d7d9`, then `main` `33c8e64` -> `e33d7d9`
  (both ancestors of the candidate; no commits were discarded). No branch protection blocked either push. GitHub then marked PR #4 merged.
- No workflow run started on either push (the new `dev-build.yml` has no push trigger); the `dev` prerelease is still "Dev build 12"
  (`222225a`); no tag, release, OTA, artifact or store upload was created.
- Still open: R-3 (OTA signature/rollback), R-4 (signing, Steam), R-5 (first hosted run, licences), R-6 (device testing).
