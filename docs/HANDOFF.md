# Handoff: Backrooms Survivor, LÖVE → Godot 4 port

Paste this whole file into the new chat as the first message. Repo to attach: **verbal76/Backrooms-Survivor** only.
**Do not touch Tartaria-RPG** (the owner does not want this work to have access to it).

## How the owner likes to work
- Ask clarifying questions **before writing code**.
- Windows PC, comfortable with GitHub Desktop and pasting PowerShell, not a heavy CLI user. Give click-by-click or copy-paste steps.
- Wants decisions explained plainly, and honest reporting of what is untested.

## The project
- **Backrooms Survivor**: top-down LÖVE2D (11.4) horror survival game, one life, a day counter (5 min = 1 day), enemies, weapons, items, bombs, orbs, progression, minimap, shaders, gamepad and touch input. Roughly 10,700 lines of Lua (`main.lua` alone is ~5,300, with a section map in its header).
- The owner found it again after losing it (it was in `C:\ProgramData\Microsoft\Windows\Start Menu\Programs\LOVE\Backrooms_Survivor - V23 sprite sheets animation`, plus folders `BUILD_APK`, `Older versions`, `BR-isometric V1`, `image slicer`, `new files temp`). **Those other folders are not in the repo yet.**
- **Goal:** port to **Godot 4.3**, targets **Windows + Android** (later Steam + Google Play, commercial), with a studio-level look and feel (lighting, shadows, post effects, proper UI) using **free/CC0 asset packs**.
- **OTA = a dev pipeline only.** Push to GitHub → Actions builds → dev builds on the owner's PC and phone update themselves. Release builds (Steam/Play) never self-update.

## Where things stand
Repo `verbal76/Backrooms-Survivor` (public). `main` = `c88628e` (the owner's single "Add files via upload" commit).
**Draft PR #2** (`claude/jolly-cori-g4l8rg` → `main`): https://github.com/verbal76/Backrooms-Survivor/pull/2 (nothing merged yet). Two commits:

1. `183a8c5` **Reorganized the flat upload into the folders the Lua code expects.** No Lua changed.
   - `music/` (8 tracks), `sounds/` (56 files), `weapons/` (15 PNGs, from weapons.zip), `enemies/` (sprite grids + `manifest.lua`), `docs/` (3 Word docs), `world_assets/` (already a folder).
   - Removed duplicate zips and the LÖVE engine zip.
   - Left at the root on purpose: `player_spritesheet.png`, `enemy_*_spritesheet.png`, `Blackcraft.ttf`, `BUILD_ALL_AND_EXECUTABLE.bat`, `_installer.iss` (the code or build script loads them from there).
2. `96ace4b` **Godot 4.3 skeleton + dev OTA pipeline** in `godot/` and `.github/workflows/dev-build.yml`.

### Godot skeleton (`godot/`)
- `project.godot` (GL Compatibility renderer, 960×720, landscape), `icon.svg`, `export_presets.cfg` (presets: **Windows Dev**, **Android Dev**, **Patch**), `build_info.json`, `min_base_build.txt`.
- `scenes/boot.tscn` + `scripts/boot.gd`: in **debug exports only** (not editor, not release), fetches `manifest.json`, downloads `patch.pck`, verifies SHA-256, loads it, then starts the game. Falls back to the installed build when offline.
- `scripts/patcher.gd`: build info, installed-patch state in `user://patch/`, hash check, install.
- `scenes/game.tscn` + `scripts/game.gd`: placeholder dark room, headlamp `PointLight2D` following mouse/touch, shadow-casting walls.
- If boot code, export presets, engine version or Android permissions change, bump `min_base_build.txt` (older installs then show "needs a full install").
- `godot/.gitignore` ignores `.godot/`, `build/` and `assets/office_pack/*`.

### CI (`.github/workflows/dev-build.yml`)
- Trigger: push to a branch named **`dev`**, or manual run. (Manual run only appears after the workflow is on the default branch, so PR #2 must be merged first.)
- Container `barichello/godot-ci:4.3`; stamps `build_info.json` with run number + SHA; exports Windows (debug) zip, Android debug APK (`continue-on-error`), `patch.pck` + `manifest.json`; a second job republishes a rolling prerelease tagged **`dev`**.
- **Tested locally with Godot 4.3:** project imports/runs headless, patch export, loading a patch over the base build, SHA helper.
- **NOT tested:** the whole workflow has never run. Expect fixes, most likely the Android SDK/JDK paths inside the godot-ci container.

## Known issues in the original game (not fixed)
- `gunshot.mp3` doesn't match the `gunshot_sound` name `main.lua` searches for, so the pistol sound probably doesn't load.
- `main.lua` looks for `carpet_tile.jpg/png` but the file is `carpet-tile.jpg`.
- `enemies/manifest.lua` isn't `require`d anywhere in the current code.
- The audio (Hell Beast, Demonic Phrase, Delirious, Gasp, In The Walls, UI Horror, etc.) looks like it came from a purchased sound pack. **License unchecked.** If it forbids redistribution, it must come out of the public repo.
- `.wav` files are ~16 MB each (~130 MB of the 245 MB repo); converting to `.ogg` would shrink it a lot but needs filename edits in `music.lua`/`enemysounds.lua`/`main.lua`.

## Asset packs and what we decided
Rule: **anything whose license forbids redistribution does not go in the public repo.** The owner argued a public repo isn't "distribution"; the assistant disagreed (raw files downloadable by anyone = redistribution) and kept them out. The owner then asked to delete those files, and they were deleted. Cleanest fix: **make the repo private** (recommended, undecided).

| Pack | License | Public repo? | Notes |
|---|---|---|---|
| SBS Horror Texture Pack (Screaming Brain Studios), 256×256, 100 PNGs | CC0 | Yes | Floors, walls, brick, metal, stone, misc, stains (transparent). Best fit. |
| Traps (Stealtrix), 6 sheets | CC0 | Yes | 32 px top-down hazards. |
| Free Crow Sprite | CC0 | Yes | Side-view ambient bird. Files not saved, re-upload. |
| Top Down Horror Assets (AIA), aiadev.itch.io/top-down-horror-assets | Free use, no direct sale; credit appreciated | Yes, with credit | Hospital props/pickups (key, battery, pill, floors). Files not saved, re-upload. |
| KayKit RPG Tools Bits (3D) | CC0 | Yes | Cartoony 3D tools; weak fit. |
| Monster Creatures Fantasy (LuizMelo) | CC0 | Yes | Side-view platformer, fantasy; zip looked incomplete (only Attack3 + projectiles). Weak fit. |
| Post Apoc Office (0-mem0ry) | Commercial OK; **no redistribution** | **No** | 32×32 pixel art. |
| Abandoned Office (Cute SCKR, $3.99, owner purchased) | Commercial OK; **no redistribution as standalone resources** | **No** | Great Backrooms fit. |
| Low Poly 3D PSX Horror (Devil's Workshop) | Commercial OK; **no redistribution, even with source files** | **No** | 142 3D models; plan was to pre-render to top-down sprites. |
| Glass Theme Game UI (SunGraphica) | **CC BY-ND 4.0**, credit "SunGraphica" **required** | **No** | ~90 black SVG/PNG icons for the HUD; credit in-game and in CREDITS.md. |
| scarymobs (creatures, Aseprite) | **Unknown** (no license file; itch comments only asked) | **No** | Needs the author's written answer. |

Status of the files: the restricted/unlicensed uploads were deleted from the session and scratch space. The owner still has the originals locally. The only trace in the repo is `godot/assets/office_pack/README.md` and the `.gitignore` lines for it. CC0 packs (textures, traps, KayKit, monsters) were extracted only in scratch space. Re-upload what's needed.

## Open decisions for the owner
1. **Make the repo private?** Needed for CI builds to include the restricted packs (CI can't see git-ignored files). Otherwise store them in a private location and fetch with a secret.
2. License of the existing sound pack in the repo.
3. License/author of scarymobs.
4. Final art direction: the owner's Blender-rendered sprites vs pixel-art packs vs rendering 3D packs to top-down sprites. They clash if mixed carelessly.
5. Merge PR #2 (then create a `dev` branch and push to it to run the pipeline).

## Suggested next steps
1. **Milestone 1: playable vertical slice** in `godot/`: player movement (keyboard, gamepad, touch joystick), generated room with wall collision and CC0 floor/wall textures, headlamp + shadows, one chasing enemy (placeholder art), basic HUD (health, flashlight battery). Add `CREDITS.md` crediting all packs used.
2. Then port in order: map generation, weapons/bullets, items/orbs, progression, enemies + AI, menus, save slots, audio.
3. Get the CI workflow green (fix Android paths), then iterate through dev builds on PC and phone.
4. Later: Steam and Play release pipelines (signing keys in GitHub Secrets, SteamPipe, Play internal track). Play forbids downloading executable code, so no OTA in release builds.

## Housekeeping notes
- A stray branch `claude/jolly-cori-g4l8rg` (identical to `main`, no changes) was pushed to Tartaria-RPG after a stop-hook warning. It can be deleted on GitHub. It is unrelated to this project.
- Two helper scripts exist from earlier but aren't needed now: `Find-Backrooms.ps1` (searched drives for the lost game) and `GitZipPieces.ps1` (split large zips for git).
