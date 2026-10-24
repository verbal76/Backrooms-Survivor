# Godot port architecture (contract for every system)

The game is a faithful port of the LÖVE game in the repo root (`*.lua`, reference only), with bug fixes,
graphical improvements and a "juice" pass. Match the Lua's numbers/behaviour first, then improve.

## Layout
- `scripts/game.gd` (root, owned by the integrator): world, player, run state, API below, loads systems.
- `scripts/player.gd`: ported `player.lua` (stats, movement, XP, streaks, inventory).
- `scripts/world_map.gd`, `scripts/chunk_view.gd`: map generation + drawing (tile units, `TILE = 52` px).
- `scripts/systems/<name>.gd`: pluggable systems, one fixed path each (below). Put helper files in
  `scripts/<name>/` or `assets/...`. **Do not edit files you don't own**; if you need a change elsewhere,
  say so in your final report.

## Systems and their fixed paths (each `extends Node`)
| path | owner | game field |
|---|---|---|
| `systems/input.gd` (`class_name GameInput`) | input/UI agent | `game.input` |
| `systems/audio.gd` | audio agent | `game.audio` (replaces `NullAudio`) |
| `systems/fx.gd` | presentation agent | `game.fx` (replaces `NullFx`) |
| `systems/lighting.gd` | presentation agent | `game.lighting` |
| `systems/weapons.gd` | combat agent | `game.weapons` |
| `systems/enemies.gd` | enemy agent | `game.enemies` |
| `systems/objects.gd` | world-objects agent | `game.objects` |
| `systems/ui.gd` | input/UI agent | `game.ui` |

Each system may implement: `setup(game)` (called once, all systems exist), `tick(dt)` (every physics frame
while `game.state == "playing"`), `reset_run()` (new run: clear all entities/state). `ui` may also implement
`tick_menu(dt)` (called while state is not "playing"). Always null-guard other systems that might not exist yet
(`if game.enemies:`), and never assume load order beyond `SYSTEM_ORDER` in game.gd.

## Units and conventions
- Positions of gameplay entities are in **tile units** (`Vector2`, `tile_pos`), like the Lua. Nodes are placed at
  `tile_pos * game.TILE` px. Angles in radians, 0 = +x, y down (same as Lua/LÖVE).
- Lit world entities are children of `game.world`. Screen-space UI goes on a `CanvasLayer` (layer >= 10).
- Tunable numbers keep the Lua values; put them in a `const` block at the top with the Lua name in a comment.
- Original assets are in the repo root (`*.png` sheets, `weapons/`, `sounds/`, `music/`, `world_assets/`, `enemies/`);
  Godot can only load `res://` (= the `godot/` folder), so **copy** what you use into `godot/assets/<area>/`.
  CC0 packs in `assets/third_party/` fill gaps. Prefer original assets; use CC0 where clearly better.
- No scenes needed; build node trees in code. Keep code GDScript 4.3, typed where cheap.
- Headless test: `godot --headless --path godot --import` then run a small `-s test.gd` (see how the
  integrator tests). Don't commit test scripts. Commit only under `godot/`.

## API on `game` (game.gd)
- `game.TILE`, `game.map` (WorldMap: `get_tile`, `is_solid(x,y)`, `find_spawn`, `chest_rooms`, `drain_new_chunks`
  - systems that spawn per chunk should read `map.new_chunks`' history via their own tracking; see `chunk_spawned` below),
  `game.player` (Player), `game.camera`, `game.world`, `game.input`, `game.state`, `game.run_time`, `game.day`, `game.kills`.
- `game.set_state(s)`: "title" | "playing" | "paused" | "perk" | "dead" | "portal". `game.start_run()` starts/restarts.
- `game.damage_player(amount, from_px := Vector2.ZERO) -> bool` (true = died).
- `game.report_kill(tile_pos, kind, xp)`: enemy system calls when an enemy dies; grants XP/streak, emits `enemy_killed`.
- `game.hitstop(seconds)`.
- Signals: `state_changed(s)`, `enemy_killed(tile_pos, kind, xp)`, `player_died`. `Player` signals: `leveled_up`, `damaged`, `died`, `footstep(sprinting)`.
- `game.chunk_spawned(cx, cy)` signal: emitted when a new map chunk is generated (item/prop/enemy spawning hook).

### Input (`game.input`)
`move: Vector2`, `aim_world: Vector2` (world px; touch and gamepad: always the automatic-targeting facing), `fire`, `alt_fire`, `sprint`, `just("action")` edge presses:
`use_water use_bandage use_food bomb weapon_next weapon_prev headlamp battery pause interact ui_left ui_right ui_up ui_down ui_accept ui_back status_hud`.

### Juice (`game.fx`, never null)
`shake(amount_px, duration)`, `hitstop(seconds)`, `flash(color, seconds)`, `float_text(world_px, text, color)`,
`burst(world_px, kind, dir)` (kinds: "hit", "spark", "smoke", "gib", "muzzle", "pickup", "levelup", "explosion"),
`blood(world_px, size)`.

### Audio (`game.audio`, never null)
`play(sound_name, world_px_or_null, volume, pitch)`, `play_music(track_name)`, `stop_music()`.
Sound names = the file basename without extension as in the Lua (e.g. "gunshot", "Demonic Breath 001").

### Weapons (`game.weapons`)
`current: int`, `list`, `ammo`, `unlocked`, `unlock(index)`, `add_ammo(n)`, `get_current() -> Dictionary`,
`cycle(dir)`. Bullets/melee query `game.enemies.get_enemies()`.

### Enemies (`game.enemies`)
`get_enemies() -> Array` of nodes with `tile_pos: Vector2`, `radius: float`, `hp: float`, `kind: String`,
`take_damage(amount: float, knockback_dir: Vector2 = Vector2.ZERO) -> void`.
`spawn(kind, tile_pos)`; difficulty scales with `game.day`.

### Objects (`game.objects`)
Items, orbs, props, chest rooms, portal, bombs' pickups. `spawn_drop(tile_pos, kind)`; listens to `enemy_killed`.

### Lighting (`game.lighting`)
`light_level_at_player() -> float` (0..1, used for sanity), headlamp + battery, `CanvasModulate`, post-FX.

## Platform, Steam Deck and quality (see docs/STEAM_HARDWARE_CHECKLIST.md)
- `scripts/platform/platform.gd` (`const Platform = preload(...)`, no class_name so OTA patches keep working): `is_steam_deck()`,
  `is_steamos()`, `is_proton()`, `is_big_picture()`, `is_deck_like()` from env vars (`SteamDeck`, `SteamOS`, `SteamGameId`,
  `SteamTenfoot`, `STEAM_COMPAT_*`) and /etc/os-release. `GameOptions.apply_platform_defaults()` uses it (fullscreen, Medium quality,
  UI 110%, 60 fps cap) before options.json is read, so a saved file always wins.
- `scripts/platform/quality.gd`: Low / Medium / High presets. `Quality.apply(game, level)` calls `set_quality(preset)` on `game.fx` and
  `game.lighting` (particle caps, motes, decals, ceiling lights, shadow filter, post-FX level) and sets `game.stream_radius`.
- Options added: UI scale, high contrast, quality, frame limit (30/40/45/60/uncapped), vsync, auto-pause, rumble (+strength),
  stick dead zone, system keyboard. `game.ui.apply_options()` re-applies everything with a runtime effect.
- UI scale: menu pages scale themselves (`UIScreen.apply_layout`: the page lays out in a canvas of size / scale and is drawn
  magnified); HUD, overlays and tip cards use `draw_set_transform` with `ui.hud_scale()`. `UITheme.MIN_FS` (12) is the smallest text.
- Prompts: never hard-code key names in UI text. Use `game.input.hint(kb, pad, touch)`, `prompt(action)` or `fill("{action}")`;
  with a controller only Xbox-style wording (A/B/X/Y, LB/RB, LT/RT, L3/R3, View, Menu, D-Pad, L4/L5/R4/R5) is ever returned.
- Menu (Start) always pauses/resumes; View dismisses tips (hold = tips off); back grips are rebindable quick actions
  (`quick_heal`, `quick_drink`, `quick_bomb`, `quick_lamp`). Rumble: `game.input.rumble(kind, scale)`.
- Focus loss / Deck suspend: `ui.gd` pauses the run and mutes the Master bus; it resumes into the pause menu.
