# Platform differences (the only places platforms may diverge)

All gameplay, AI, physics, balance, progression, generation and content live in shared code under `godot/scripts/`
and are identical on every target. Targets: **Android** (APK), **Windows** (zip; also what Steam Deck runs under
Proton), **Linux x86_64** (tar.gz; native Steam Deck / SteamOS / desktop). Each release builds all of them from the
same source SHA (`release_manifest.json`).

| Area | Shared | Platform-specific (isolated here) |
|---|---|---|
| Input | action model, `game.input` API (`move`, `aim_world`, `fire`, `just()` ...) | `godot/scripts/systems/input.gd`: keyboard+mouse, gamepad, touch sticks/buttons; auto-detect and switching; prompts per scheme |
| Display / UI | HUD, menus, tutorial, layouts | UI scale, safe-area insets (touch), Deck 1280x800 defaults (`scripts/platform/platform.gd`) |
| Quality / performance | game logic | quality presets and frame limit (`scripts/platform/quality.gd`), Deck default Medium |
| Detection | - | `platform.gd`: Steam Deck / SteamOS / Proton / Big Picture env detection |
| Haptics / rumble | triggers in shared systems | `Input.vibrate_handheld` (touch), `Input.start_joy_vibration` (pad) |
| Packaging | project, assets, scripts | `godot/export_presets.cfg`: "Windows Dev" (console wrapper, s3tc/bptc), "Android Dev" (arm64-v8a, etc2/astc, INTERNET, debug signing), "Linux Dev" (embedded pck) |
| Project settings | all | `textures/vram_compression/import_etc2_astc=true` (needed so Android validates; harmless elsewhere) |
| Build | one workflow | `.github/workflows/dev-build.yml` installs the Android SDK, exports each target from the pinned SHA |
| OTA | one patch.pck for all platforms | updater runs only in debug exports; `min_base_build.txt` gates native-binary changes |

Rules: no platform-named code directories or branches; no `if platform:` gameplay or balance differences; any new
difference must be added to this table in the same change. Legacy LÖVE2D files in the repo root are the reference
implementation of the same game and are not a platform target.

## Android phone UI scale (owner playtest of Build 13)
On a real mobile device the whole UI is drawn about **2x** larger (`ui.phone_boost()`: 2.0 on phones, easing to 1.25 on tablets by
physical screen size; desktop, Windows, Linux and Steam Deck keep boost 1.0, enforced by a regression test). It multiplies Options >
UI Scale and is capped so each page still fits. What changed on phones only:
- **HUD:** stats panel top-left, info panel top-right, minimap in the strip between them (left-handed play mirrors the panels); the
  minimap is bigger with larger markers; counters and captions on the touch buttons ~40% larger. The touch sticks keep their size.
- **Level-up:** larger cards, titles and descriptions, a lighter unselected card, both cards always fully visible.
- **Tip cards:** larger text, placed between the two thumb clusters so they never cover a stick or button.
- **Pause, Options, How To Play, Death, Title:** compact 2x layouts (tighter header, scrolling lists, drag-to-scroll).
- Not changed (still ~1.4x, screens too dense for a 360 px tall canvas): Upgrades shop, character select, name entry.
Evidence: `docs/android_ui_before_after/` (same seed and game state, 1280x580). Tests: `t_phone_ui`, `t_phone_menus` in
`godot/tools/regression_tests.gd` check the scale, on-screen bounds and overlap with every touch control at five phone sizes.

## Automatic targeting and attack input (release-candidate pass)
- **Facing authority:** for touch and gamepad the combat facing is decided in ONE place, `GameInput._update_auto_facing()`: face the nearest
  living enemy within 10 tiles that has a clear tile-grid line of sight (`has_clear_los`, exact traversal of the real level collision; the
  shooter's and the target's own tiles never count); no target -> face the way you walk; standing still -> keep the last facing. It writes
  `aim_world`, the player turns to it instantly (`snap_facing`), and the body sprite, held weapon, swing / bullet direction and hit test all read
  `player.angle`. The movement stick never steers the facing while a target exists. Walls, range and corners behave as in
  `tools/regression_tests.gd` tests A-J.
- **No manual aim:** there is no right aim joystick on touch, the gamepad right stick is menu-only, and the Aim Assist option is gone.
  Keyboard + mouse keeps cursor aim (it has no stick to take over); that is the only manual aim left and is an owner decision to keep or remove.
- **ATTACK input:** every press is latched and buffered for 0.16 s (`FIRE_BUFFER`); `weapons.gd` consumes it when an attack really starts, so
  short taps, taps during hit-stop and taps just before the cooldown ends register, while the weapon cooldown, stamina cost and damage are untouched.
- **Weapon mirroring:** the side the weapon is drawn on follows the facing (with a dead band at vertical), never the animated swing angle.
- **HUD:** compact stats / combat panels (about 50% / 45% smaller), notifications drawn below the character.
