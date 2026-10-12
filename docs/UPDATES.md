# Updates (OTA) - how they work and what is not yet guaranteed

Debug/dev builds update themselves; release builds of a coordinated `build-NN` are fresh installs.

- Channel: `https://github.com/verbal76/Backrooms-Survivor/releases/download/dev/manifest.json` (baked into the app; do not move).
- `godot/scripts/boot.gd` + `godot/scripts/patcher.gd`: fetch manifest, compare build number, check `min_base_build.txt`
  (native build required when boot code, export presets, engine version or Android permissions change), download
  `patch.pck`, verify its SHA-256 against the manifest, store it in `user://patch`, load it on the next start.
- Published by `dev-build.yml` (rolling `dev` prerelease, replaced on every push to `dev`).
- Offline play: the game never requires the network; a failed update check starts the installed version.

## Gaps (all owner decisions; none changed here, boot code is frozen)
1. No authenticity signature: SHA-256 proves integrity against the manifest, not who published it.
2. No known-good retention or crash rollback: installing a patch deletes the previous one.
3. Automatic publish on push to `dev` (see docs/RELEASES.md).
Fixing 1-2 changes boot code => native rebuild + `min_base_build.txt` bump. Do not do it without approval.
