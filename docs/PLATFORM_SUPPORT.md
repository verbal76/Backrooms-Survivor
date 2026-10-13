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
