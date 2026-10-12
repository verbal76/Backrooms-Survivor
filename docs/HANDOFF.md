# Handoff: Backrooms Survivor, LÖVE → Godot 4 port

Read `/CLAUDE.md` first (permanent policy), then this file. Repo: **verbal76/Backrooms-Survivor** only.
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

## Where things stand (updated 2026-10-12)
**Stage: C - release qualification / awaiting owner and physical-device testing.** The Godot port is feature-complete
against the Lua game plus owner-requested additions; builds are verified; no owner-authorized production release yet.

- **Authoritative line: `dev`** (see `docs/RELEASE.md`). `dev` = `222225a` (dev build 12 is the published rolling prerelease).
  Working branch `claude/fervent-franklin-hrrnb7` (PR #4) is ahead of `dev` with policy/CI/test work; head at the time of
  writing is listed under "Source" below. `main` (`33c8e64`) intentionally lags; PR #1 closed (branch kept), PR #2 superseded.
- **Game (`godot/`):** ported player, map, combat (8 weapons, bombs), 6 enemy types incl. crows, items/orbs/props/chests/portal,
  traps (bear/spike/pit/fire/push), progression/saves/perks, HUD/minimap/menus, tutorial + context tips + How to Play, rebindable
  controls with auto-detect, Android touch controls, audio (OGG, synth SFX), lighting/FX/juice, Steam Deck/Linux support, studio splash
  and icon (Hot Attic Games). Balance retuned (`godot/docs/BALANCE.md`).
- **Platforms:** Android APK, Windows zip, Linux tar.gz (Steam Deck native), all from one source/SHA via `.github/workflows/build-all.yml`.
- **Policy/CI:** single-source-of-truth policy (`docs/ENGINEERING_POLICY.md`), ledger (`docs/RECOVERY_LEDGER.md`), `validate-build.yml`
  (non-publishing, runs on PRs), `dev-build.yml` (publishes - **a push to `dev` publishes**, needs owner approval), smoke + regression tests.
- **Tests:** `tools/policy_check.py`, `godot/tools/smoke_test.gd`, `godot/tools/regression_tests.gd` (17 checks), balance sim
  (`godot/tools/balance_sim.gd`). CI validation of the full build+verify pipeline passed on `f096650` and `f9e2dec`; a deliberate
  Linux failure (`37c2f70`) failed the whole run as designed.

## Known issues / not verified
- **Nothing has been played on real hardware by the assistant.** Unverified on device: touch feel and hit-testing, gamepad analog
  input, Steam Deck/Proton behavior, haptics/rumble, audio mix, phone performance and battery, icon/splash on a phone.
- Crow size/dive dodgeability, trap damage feel, and enemy wind-up timing are untuned by play.
- Easy difficulty was not re-run to death after crows/traps (see BALANCE.md addendum).
- Sanity still has little gameplay cost for a player who stays in light (only FX and fumbled swings below 25 %).
- Original-game quirks fixed in the port: gunshot sound name, carpet texture name; `enemies/manifest.lua` is unused.
- Sound pack license (Hell Beast, Demonic Phrase, Delirious, ...) is **unchecked**; it is in the public repo and in the builds.

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
1. Authorize a release: push/merge validated work to `dev` (publishes the rolling prerelease) and optionally fast-forward `main`.
2. License of the sound pack; license/author of scarymobs; final art direction (Blender sprites vs pixel packs).
3. Delete stale branches (12 local `worktree-agent-*`, PR #2/#1 branches) only when you say so.
4. Steam: Steamworks app id, SteamPipe, release export presets, GodotSteam (see `godot/docs/STEAMDECK.md`).

## Next actions (highest value first)
1. Owner playtest of the latest build on phone + PC (+ Deck if available); triage feedback into fixes.
2. Re-run Easy balance (`godot/tools/run_balance.py --diffs 1 --seeds 1-4`) after any enemy/loot change.
3. Release signing for Google Play (keystore in GitHub Secrets) and Steam release export presets.
4. Optional polish: trap minimap markers, enemy trap avoidance, sanity gameplay cost.

