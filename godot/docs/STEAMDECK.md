# Steam Deck / Steam Machine support

Target: **Steam Deck Verified** for both the native Linux build (`BackroomsSurvivor.x86_64`) and the Windows build running
under Proton, plus a comfortable Steam Machine (1080p) experience. Everything below was done in code and checked on a
desktop with synthetic input and software rendering. **Nothing has been run on real Steam hardware yet** (see "Not tested").

## What was done

| Area | Change |
|---|---|
| Linux export | New export preset **Linux Dev** (Linux/X11, x86_64, embedded pck, debug). CI exports it and publishes `BackroomsSurvivor-linux-dev.tar.gz` (execute bit kept) on the rolling `dev` release next to the Windows zip and the APK. |
| Detection | `scripts/platform/platform.gd`: Steam Deck (`SteamDeck=1`, DMI board `Jupiter`/`Galileo`), SteamOS (`SteamOS`, `/etc/os-release`), Big Picture (`SteamTenfoot`), Steam launch (`SteamGameId`, `SteamAppId`), Proton (`STEAM_COMPAT_*`). |
| Deck defaults | Applied only when no saved `options.json` value exists: borderless fullscreen at the panel's native size (1280x800), controller-first prompts, vsync on, 60 fps cap, **Medium** quality, UI scale 110%, cursor hidden while the pad is used. Desktop keeps windowed / High / uncapped+vsync. |
| Scaling | Project stretch is `canvas_items` + `expand` from a 960x720 base, so the canvas is 1152x720 at 1280x800 (16:10), 1280x720 at 1280x720, 1280x720 at 1920x1080, 1152x720 at 1920x1200 and 1280x720 at 3840x2160 (3x). Nothing is cropped or letter-boxed. |
| Legibility | Smallest text anywhere is `UITheme.MIN_FS` = 12 canvas px (about 13 real px at 1280x800). Body text is 14-19, HUD 14-15, tip cards 17, How To Play 12-19 (auto-fit). New Options: **UI Scale 80-150%** (HUD, minimap, overlays, menus, How To Play, tip cards) and **High Contrast Text**. Dim hint colours were brightened. |
| Controller | Every screen and flow is completable with the pad (see walkthrough). Xbox-style prompts (A/B/X/Y, LB/RB, LT/RT, L3/R3, View, Menu, D-Pad, L4/L5/R4/R5) from one place (`GameInput.prompt/hint/fill`). Back grips are remappable quick actions. Rumble with Options toggle + strength. Radial rescaled stick dead zone (Options), trigger fire threshold 0.30. |
| Text entry | Built-in on-screen keyboard works with the pad (D-Pad/sticks, A type, B delete, X space, Y page, Menu done) with 3 pages: letters+digits, accented letters, symbols. A `KBD` key / the "System Keyboard" option call `DisplayServer.virtual_keyboard_show`; on the Deck the Steam keyboard (Steam + X) types real key events into the same box. |
| Performance | Options: **Quality** (Low/Medium/High), **Frame Limit** (30/40/45/60/uncapped; 40 = the Deck's 40 Hz mode), **VSync**. Hot spots fixed: light occluders merged vertically (5362 -> 1821 nodes in the stress scene), decals culled to the camera, per-quality caps on particles / dust motes / decals / ceiling lights / shadow filter / post-FX / chunk streaming radius. |
| Focus / suspend | `NOTIFICATION_APPLICATION_FOCUS_OUT` / `WM_WINDOW_FOCUS_OUT` pause the run, mute the Master bus and stop rumble; coming back unmutes and leaves the pause menu up (no surprise hits). |
| Steam-readiness | Saves and options are small JSON under `user://` (`backrooms_save.json` + `.bak`, `options.json`); no absolute paths, registry, admin rights, launcher or EULA; no network except the OTA updater, which only exists in **debug** builds. |

## Steam Deck Verified checklist

Status: **PASS** = implemented and verified here; **PASS (code)** = implemented, cannot be verified without hardware;
**OPEN** = needs the owner or a real device.

### Input
| # | Requirement | Status | Notes |
|---|---|---|---|
| 1 | Default controller config reaches ALL content, no settings changes | PASS | `padwalk` script (synthetic joypad events): story skip, save slots, name entry, title, How To Play, options (+ sub pages, rebinding capture), shop, character screen, run start, gameplay, tips, pause, focus loss, perk choice, portal prompt, escape/victory, death (try again / main menu), EXIT. |
| 2 | Supports the Deck's controls: both sticks, triggers, bumpers, D-Pad, face buttons, View/Menu, L3/R3, back grips | PASS (grips: code) | Left stick move / right stick aim / RT attack / LT map / bumpers / D-Pad / face buttons / L3 R3 / View / Menu all mapped. Back grips map to `JOY_BUTTON_PADDLE1-4` (rebindable; defaults quick heal / drink / bomb / lamp). Steam Input's XInput-style virtual pad does not expose paddles unless bound in the Steam configurator, see "Steam Input". |
| 3 | Steam Controller inputs | PASS (code) | Same Xbox-style layout through Steam Input. |
| 4 | Trackpads | n/a | Recommended config leaves them unbound; with "Gamepad with Mouse Trackpad" they act as a mouse and the UI switches to keyboard/mouse prompts only after real mouse movement (40 px hysteresis while a pad is in use). |
| 5 | Touchscreen | PASS | Taps are emulated mouse clicks and work in all menus (tested). They never switch the game into the on-screen touch controls on desktop/Deck unless the player forces "Touch". |

### Glyphs / prompts
| # | Requirement | Status | Notes |
|---|---|---|---|
| 6 | Prompts match the ACTIVE device | PASS | `GameInput.hint(kb, pad, touch)`, `prompt()`, `fill()` are the only sources. Auto-detects the last used device; touch labels are hidden unless touch is active. |
| 7 | No keyboard/mouse glyphs or words while a controller is used | PASS | Audited: title, pause, options, controls page (keyboard table hidden), shop, perk, portal, death, character screen, name entry, story/splash skip hints, How To Play pages (the `[kb]` lines and the other schemes are hidden), tips and tip footer, overlays (stats / map / controls), HUD quick-item row. |
| 8 | Xbox-style names, one function so real glyph textures can replace them | PASS | `GameInput.PAD_NAMES`. Real Steam Input glyph textures need GodotSteam (not included), swap the body of `prompt()` / `pad_name()`. |

### Text input
| # | Requirement | Status | Notes |
|---|---|---|---|
| 9 | Name entry completable with the controller alone | PASS | See "What was done". |
| 10 | Accented / extra characters | PASS, with a limitation | The 2nd and 3rd pages cover Latin-1, common Latin Extended-A letters and symbols; a physical or Steam keyboard can type any letter the font has. The stylised display font (Blackcraft) draws accents as decorated glyphs, so the name box and key caps switch to the plain face when a name contains non-ASCII. CJK / Cyrillic / Arabic are not offered. |

### Display
| # | Requirement | Status | Notes |
|---|---|---|---|
| 11 | Supports 1280x800 (preferred) and 1280x720 | PASS | Screenshot-checked all screens at 1280x800, 1280x720, 1920x1080, 1920x1200 (pad) and 1280x800 (keyboard). |
| 12 | Smallest on-screen text never below 9 px at 1280x800, aim for >= 12 | PASS | Floor is 12 canvas px (about 13 real px at 1280x800, 12 at 1280x720). Audited every `UITheme.text/head/wrapped` caller and every direct `draw_string` (touch labels floored at 12, the options-page touch preview at 9, it is a scaled-down diagram). UI scale and High Contrast available. |

### Performance
| # | Requirement | Status | Notes |
|---|---|---|---|
| 13 | Default config holds >= 30 fps at 1280x800 (Deck) | PASS (code) / OPEN | Deck default is Medium + 60 fps cap + vsync. Measured only relatively on a software renderer, see below. Needs a real Deck run. |
| 14 | 30 fps at 1080p on Steam Machine | OPEN | High is the desktop default; if it is slow the player can pick Medium/Low in Options. |

### Seamless experience
| # | Requirement | Status | Notes |
|---|---|---|---|
| 15 | No launcher, no EULA, no unsupported-hardware or OS warnings | PASS | None exist. |
| 16 | No mandatory network | PASS | The only network code is the OTA updater (debug builds only, 8 s timeout, offline = starts the installed build). Release exports skip it (`Patcher.updater_enabled()`). |
| 17 | Quits cleanly from the pad | PASS | Title > EXIT, pause > QUIT TO MENU. Options are flushed on window close. |
| 18 | Pauses on suspend / overlay | PASS (code) | Focus-out notifications (tested by sending the notification). |

### Proton
| # | Requirement | Status | Notes |
|---|---|---|---|
| 19 | Nothing in the Windows build breaks under Proton | PASS (code) / OPEN | No registry, launcher, admin, absolute or Windows-only paths; saves via `user://`; `DisplayServer.keyboard_get_keycode_from_physical` is skipped under Proton / on the Deck (key names come from the physical keycode). Renderer is OpenGL compatibility (works through Wine's GL). Needs a real Proton run. |

## Controller map (defaults)

| Button | Gameplay | Menus |
|---|---|---|
| Left stick | Move | Navigate |
| Right stick | Aim (auto-aim when idle, Easy/Normal) | Navigate |
| RT | Attack | |
| LT (hold) | Tactical map | |
| RB / LB | Throw bomb / headlamp | |
| A | Sprint | Confirm |
| B | Next weapon | Back |
| X / Y | Use bandage / drink water | X: delete subject |
| D-Pad Left / Right | Eat / previous weapon | Navigate |
| D-Pad Up / Down (hold) | Status panel / run stats | Navigate |
| L3 / R3 | Replace battery / controls help (hold) | |
| Menu | Pause | Resume (pause), start (title), done (name entry) |
| View | Dismiss tip (hold: tips off) | |
| L4 / L5 / R4 / R5 | Quick heal / quick drink / quick bomb / quick lamp (rebindable) | |

Perk choice and the portal prompt only accept D-Pad/sticks + A on a pad (gameplay buttons are ignored) because the portal
choice is irreversible.

## Quality presets

| | Low | Medium (Deck default) | High (desktop default) |
|---|---|---|---|
| Effect particles | 40% | 70% | 100% |
| Dust motes | 0 | 22 | 44 |
| Floor decals kept | 70 | 130 | 200 |
| Ceiling lights | 3 | 5 | 8 |
| Headlamp shadow filter | hard | PCF5, smooth 1 | PCF5, smooth 2 |
| Post-FX pass | off | on, no grain / aberration / warp / dust / haze | full |
| Chunk stream radius | 22 tiles | 26 | 32 |

The existing adaptive budget in `fx.gd` still drops particle counts further when frame time climbs.

## Profiling (relative, software renderer)

Measured with Mesa llvmpipe under Xvfb at 1280x800, stress scene = 40 enemies (about 52 alive) + explosions / gibs / blood every
20 frames while walking. **Absolute numbers are meaningless for a Deck, only the ratios are**; the real GPU is orders of
magnitude faster at the fill-rate that dominates here.

| Run (1280x800, ~50 enemies alive) | frame ms | draw calls | primitives | nodes |
|---|---|---|---|---|
| Before this work, High | 455 | 412 | 17.1k | 7033 |
| After: **Low** | 134 | 288 | 11.7k | 3441 |
| After: **Medium** | 189 | 320 | 13.1k | 3538 |
| After: **High** | 215 | 414 | 17.7k | 3499 |
| After: High, no enemies | 129 | 182 | 11.5k | 3335 |

At 1920x1080 (Steam Machine class): Low 255 ms, Medium 342 ms, High 316 ms (Medium/High differ by noise in software), no enemies 235 ms.
Pixel count scales the software numbers about 1.9x (800p -> 1080p), i.e. the stress scene is fill-rate bound there.

What the toggles showed on the original High build (frame ms): everything on 455, post-FX pass off 136, headlamp shadow off 206,
all ceiling/orb/chest lights off 216, **all light occluders removed 142**, decals hidden 217.

Fixes made from that:
* **Light occluders** (`chunk_view.gd`): horizontal wall runs that repeat on consecutive rows are merged into one taller rectangle
  (identical shadows, 5362 -> 1821 `LightOccluder2D`): High went 455 -> 238 ms on the stress scene.
* **Decals** (`fx.gd`): only decals within 1000 px of the camera are recorded (re-recorded when the camera moves 260 px), plus a per-quality cap.
* **Post-FX** (`post_fx.gd`): Medium skips grain, dust, haze, aberration and warp; Low drops the full-screen pass (the single most expensive item on a
  GPU-less box, it forces a back-buffer copy in the Compatibility renderer).
* Quality caps on particles / motes / ceiling lights / shadow filter / chunk radius (table above).

Script CPU in the same scene (Godot debug build, ms per frame): Enemies tick 3.4 (53 enemies), input 1.0, Objects 0.5, FX 0.2, Lighting 0.1, Traps 0.1,
everything else below 0.1, total about 5.5 ms, so roughly 2 ms in a release build: the CPU side is far from the 16.6 ms budget; the GPU side is what the presets control.

## Recommended Steam Input configuration

* Open the game's **Controller settings** in Steam (Deck: Controller icon > Edit layout) and choose the **Gamepad** template
  (not "Gamepad with Mouse Trackpad", not "Keyboard (WASD) and Mouse"). Trackpads stay unbound.
* Left stick = left stick, right stick = right stick, triggers/bumpers/face buttons/D-Pad/L3/R3 = the matching Xbox buttons,
  View = Select/Back, Menu = Start. Do **not** map Menu to Escape.
* Back grips: the template leaves L4/L5/R4/R5 empty. Either leave them (quick actions are a bonus) or bind them to extra
  buttons you want, for example L4 = Y, L5 = X, R4 = RB, R5 = LB (same effect, no game support needed). With Steam Input disabled for
  the game, SDL may expose them as paddles (`JOY_BUTTON_PADDLE1-4`), the game already maps those.
* Steam Input glyph textures (real button art) need GodotSteam; the game shows Xbox-style text names which match the Deck's face buttons.
* Set the Steam game's frame-rate limit in the Quick Access menu or use Options > Frame Limit (40 = the Deck's 40 Hz mode).

## How to test on a real Deck

Use the artifacts from the rolling `dev` release.

**Native Linux build**
1. Desktop Mode: download `BackroomsSurvivor-linux-dev.tar.gz`, extract (`tar xzf`) into e.g. `~/Games/BackroomsSurvivor/`.
2. Steam > Add a Non-Steam Game > Browse > `BackroomsSurvivor.x86_64`. Launch options: empty.
3. Properties > Controller: pick the Gamepad template. Return to Gaming Mode and launch from the library.
4. Expect: fullscreen 1280x800, prompts show A/B/X/Y, no cursor, Options > Display shows Quality "Medium", UI Scale 110%.
5. Logs: `~/.local/share/godot/app_userdata/Backrooms Survivor/logs/godot.log`. Saves: same folder.

**Windows build under Proton**
1. Extract `BackroomsSurvivor-windows-dev.zip` (on the Deck, Desktop Mode).
2. Add `BackroomsSurvivor.exe` as a Non-Steam Game, Properties > Compatibility > Force a Proton version (Proton Experimental or a
   current stable). First start takes a while (prefix creation).
3. Same checks as above. Saves live in the prefix: `.../compatdata/<id>/pfx/drive_c/users/steamuser/AppData/Roaming/Godot/app_userdata/Backrooms Survivor/`.

**Checklist to run on the device**
* Boot straight to the story / title without a window or dialog; the first press of any button skips the story.
* Walk through name entry with the pad only (including the accent page), start a run, die, retry, quit to menu, EXIT.
* Quick Access > Performance overlay: record fps and battery draw at Medium/60, Medium/40 and Low/30 in a busy room (chest swarm).
* Press the Steam button / open the overlay mid-run: the game must pause and mute, and resume into the pause menu.
* Suspend (power button) and wake: same.
* Rumble on damage / explosions, strength slider in Options > Controller.
* Back grips, if bound.
* Touchscreen: tap through the menus.
* Docked on a 1080p / 4K display: layout correct, UI Scale usable.

## Not tested (needs hardware)

Real Steam Deck, SteamOS, Proton, gamescope, Steam Input (grips/paddles), Steam keyboard (Steam + X), suspend/resume,
real GPU performance and battery draw, the Linux CI export itself (no Linux export templates were available locally),
rumble on a physical pad.

## What remains for the owner

1. **Steamworks**: create the app, get the App ID, add `steam_appid.txt` for local launches (never ship it in the depot),
   fill in the store page, capsule art (header, capsule, hero, logo), screenshots (the Deck ones should show controller prompts), trailer.
2. **Release builds**: export non-debug presets (Windows + Linux x86_64) so the OTA updater is compiled out of reach;
   add them to `export_presets.cfg` (copy "Windows Dev" / "Linux Dev" without debug) and CI.
3. **SteamPipe**: one depot per OS (Windows, Linux), launch options `BackroomsSurvivor.exe` / `BackroomsSurvivor.x86_64`, set the Linux
   executable bit in the depot (the tar.gz keeps it; SteamPipe needs `chmod +x` in the build script or "executable" file flag).
   Mark the Linux depot for SteamOS or rely on Proton for Windows, or ship both (native is preferred).
4. **Steam Cloud** (optional): Auto-Cloud root `WinAppDataRoaming` (Windows) / `LinuxXdgDataHome` (Linux), subdirectory
   `Godot/app_userdata/Backrooms Survivor` / `godot/app_userdata/Backrooms Survivor`, patterns `backrooms_save.json`,
   `backrooms_save.json.bak`, `options.json`. Consider a stable custom user dir (`application/config/use_custom_user_dir`) before
   release; it moves the save location, so decide it before players exist.
5. **GodotSteam** (optional): achievements, cloud, overlay, real Steam Input glyphs (`GameInput.prompt()` is the single swap point)
   and a "Steam keyboard" call for the name box (`ShowFloatingGamepadTextInput`). Not required for Deck Verified.
6. **Verification**: submit for Steam Deck Verified review once a device run of the checklist above is clean.
7. **Signing**: Windows code signing certificate (optional, helps SmartScreen outside Steam); nothing needed for Linux.
8. The OTA flow: bump `min_base_build.txt` only if `boot.gd` / `patcher.gd` change (they were not touched here).
