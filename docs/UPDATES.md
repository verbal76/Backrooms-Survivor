# Updates (OTA) - how they work and what is not yet guaranteed

Debug/dev builds update themselves; release builds of a coordinated `build-NN` are fresh installs.

- Channel: `https://github.com/verbal76/Backrooms-Survivor/releases/download/dev/manifest.json` (baked into the app; do not move).
- `godot/scripts/boot.gd` + `godot/scripts/patcher.gd`: fetch manifest, compare build number, check `min_base_build.txt`
  (native build required when boot code, export presets, engine version or Android permissions change), download
  `patch.pck`, verify its SHA-256 against the manifest, store it in `user://patch`, load it on the next start.
- Published ONLY by the manual `dev-build.yml` (rolling `dev` prerelease). See "Publishing architecture" below.
- Offline play: the game never requires the network; a failed update check starts the installed version.

## Gaps (all owner decisions; none changed here, boot code is frozen)
1. No authenticity signature: SHA-256 proves integrity against the manifest, not who published it.
2. No known-good retention or crash rollback: installing a patch deletes the previous one.
3. (closed by R-2) Automatic publish on push to `dev` no longer exists.
Fixing 1-2 changes boot code => native rebuild + `min_base_build.txt` bump. Do not do it without approval.

## Verified behaviour (code read 2026-10-12; no OTA was published or run)
- **Identity / boundary:** base build number baked in `res://build_info.json`; a patch applies only if `patch.build > base_build`
  and `state.base_build == base_build`; `min_base_build` in the manifest blocks patches that need a newer native build.
  Package id `com.verbal76.backroomssurvivor` and signing are unchanged.
- **Integrity:** SHA-256 of `patch.pck` must equal the manifest value before install (integrity, not authenticity).
- **Staging / activation:** download goes to `user://patch_download.tmp`, is verified, then renamed to `user://patch/patch_<build>.pck`
  and recorded in `state.json`; it is loaded on the next start, before game code.
- **Interrupted download:** only the `.tmp` file is affected; the installed patch (or base game) keeps running.
- **Interrupted install:** the old patch is deleted just before the rename. A crash in that window leaves `state.json` pointing at a
  missing file, which `apply_installed` treats as "no patch" -> the base game starts. Safe, but the previous patch is lost.
- **Rollback:** none. A patch that passes the hash but is faulty stays installed until a newer one replaces it (R-3).
- **Installed players:** unaffected by this branch's CI/docs/tooling work; the glyph/title-version changes ship in the next patch only.

## Publishing architecture (R-2, implemented)
`dev-build.yml` has exactly one trigger, `workflow_dispatch`. A push, merge, tag, pull request or schedule cannot publish.
Jobs: `authorize` -> `build` (reusable `build-all.yml`, read-only) -> `publish` (the only job with `contents: write`).
- **Authorization** is decided from GitHub's own context (event name, `refs/heads/dev`, `github.actor` == `github.triggering_actor`,
  run attempt 1) and the initiator's repository role read from the permission API (`admin` or `maintain`). Dispatch form values
  (`source_sha`, `build_number`, confirmation phrase) are validated, never used as authorization.
- **One number sequence:** the next number must be exactly `max(OTA channel build, every build-NN tag) + 1`. Duplicates, stale numbers,
  gaps and unreadable lookups are refused (fail closed). `release-build.yml` uses the same gate.
- **Source:** `source_sha` must be the live tip of `dev`; `build-all.yml` re-pins it and verifies every artifact's embedded SHA.
- **Repeated in the publish job:** authorization, source, sequence, `verify_release`, `verify_artifacts` and an OTA compatibility check
  (`manifest.json` hash/size/build/sha/`min_base_build` against the actual `patch.pck` and `godot/min_base_build.txt`).
- Both workflows share the concurrency group `build-sequence`, so two publications cannot interleave.
- Code: `tools/publish_gate.sh`, `tools/ci_guard.py`, `tools/workflow_rules.py`; tests: `tools/test_release_tools.py` (run on every PR).
- Limits: SHA-256 is integrity, not publisher authentication (R-3). A dispatcher with write access could dispatch a modified workflow
  from another branch, but the gate refuses any ref other than `dev`; enable a branch ruleset/protected environment on `dev` for defence in depth (owner action).
