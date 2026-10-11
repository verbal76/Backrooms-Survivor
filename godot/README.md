# Godot port (work in progress)

Godot 4.3 project that will replace the LÖVE game in the repo root. The LÖVE version
stays untouched until the port is playable.

## Dev OTA pipeline

Push to the `dev` branch (or run **Actions → Dev build (OTA) → Run workflow**). GitHub Actions then:

1. stamps `build_info.json` with the run number + commit,
2. exports a Windows debug build, an Android debug APK (best-effort), and `patch.pck`,
3. writes `manifest.json` (build number, SHA-256, size, `min_base_build`),
4. replaces the rolling **`dev` prerelease** with those files.

**Installing:** download `BackroomsSurvivor-windows-dev.zip` or `BackroomsSurvivor-dev.apk` from the
[`dev` release](../../releases/tag/dev) once.

**Updating:** after that, every launch of a dev build checks `manifest.json`, downloads `patch.pck`
if its build is newer, verifies the SHA-256, loads it over the installed game, and starts. Code, scenes,
art and audio all update this way. Offline or failed updates just start the installed build.

**When a patch isn't enough:** if you change the boot code (`scripts/boot.gd`, `scripts/patcher.gd`),
export presets, engine version or Android permissions, bump the number in `min_base_build.txt` to the
build number of the first run that contains the change. Older installs then show "needs a new full
install" with a link instead of loading an incompatible patch.

**Release builds never update themselves.** The updater only runs in debug exports (not the editor,
not release exports), so Steam / Play builds update only through their stores. Pass `--no-update` to
skip it on a dev build.

## Layout

- `scenes/boot.tscn` + `scripts/boot.gd` – update check, then loads the game (keep stable)
- `scenes/game.tscn` + `scripts/game.gd` – placeholder game scene with a headlamp + shadow demo
- `scripts/patcher.gd` – patch state, hash check, install
- `export_presets.cfg` – Windows Dev, Android Dev, Patch
- `assets/office_pack/` – git-ignored third-party pack (see its README)

## Not yet verified

The Windows export and Android export steps in CI haven't run yet. The patch export, loading and
SHA check were tested locally with Godot 4.3. Expect a round or two of fixes on the first CI run,
most likely in the Android SDK/JDK paths inside the `barichello/godot-ci` container.
