# Porting map: LÖVE game (repo root `*.lua`) → Godot

This is a port of the existing, working game, not a rewrite. The Lua stays in the repo root as the
reference until each part is matched, then it gets retired. Keep tuning numbers identical first,
improve second.

| Lua | Role | Godot | Status |
|---|---|---|---|
| `map.lua` | infinite chunk generator, chest rooms, portal | `scripts/world_map.gd` | ported (chest rooms done; portal spawn todo) |
| `player.lua` | movement, stamina, collision, aim | `scripts/player.gd` | movement/stamina/aim done; sanity, hydration, noise, XP, streaks, inventory todo |
| `main.lua` SEC 12/15/18 | lighting, tile + player drawing | `scripts/chunk_view.gd`, `game.gd` | floor/walls/void, shadows, headlamp, 16-frame player sprite done; cone beam, haze todo |
| `weapons.lua`, `bomb.lua` | guns, melee, bullets, bombs | – | todo |
| `enemies.lua`, `enemysounds.lua` | 5 enemy types, AI, sounds | – | todo (sprite sheets already in repo root) |
| `items.lua`, `orbs.lua`, `props.lua` | pickups, orbs, clutter | – | todo |
| `progression.lua` | meta upgrades, save slots | – | todo |
| `input.lua` | keyboard, gamepad, touch | `game.gd` (keyboard + mouse only) | gamepad + touch todo |
| `music.lua`, `options.lua` | audio, settings | – | todo |
| `shaders.lua`, `render.lua` | grain, vignette, haze post FX | – | todo |
| `main.lua` SEC 3-4, 9-10, 14, 19-21 | story, title, pause, HUD, minimap | – | todo |

Tuning values are copied from the Lua (tile size 52, player speed 3.5 tiles/s, sprint 1.6x, accel 18,
decel 14, body radius 0.25, sprite angle offset -90°).

## Asset choices
Original art and audio is used wherever the game already has it (player/enemy sheets, weapons,
`world_assets`, sounds, music). CC0 packs (`assets/third_party/`) fill gaps: SBS textures for floor
and wall now. KayKit 3D models are excluded from import (`.gdignore`) because they don't fit a top-down 2D game.
