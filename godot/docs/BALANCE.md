# Balance audit and tuning

Method: `godot/tools/balance_sim.gd` runs the real `game.tscn` headless at 60 Hz with a scripted bot, driven by
`tools/run_balance.py`:

```
GODOT=/path/to/godot python3 godot/tools/run_balance.py out.jsonl --diffs 1,2,3,4 --seeds 1-8 --secs 1800 --days \
    [--extra weapons=best] [--extra skill=brawl]
godot --headless --path godot -s tools/balance_sim.gd -- <difficulty> <seconds> <seed> [weapons=machete|best] [skill=kite|brawl] [reaction=0.25]
```

The default bot ("kite", machete only) fights what hunts it, backs out of every enemy's reach (reacting to a
wind-up after 0.25 s, like a human), keeps spacing inside the weapon reach, heals at 70 % / 50 % HP, drinks at
hydration < 35, replaces the headlamp battery, picks perks by a fixed ranking, grabs nearby items and otherwise
wanders. "brawl" stands and trades blows. "best" uses guns/axe when found. The map, drops and RNG are seeded.
Bots are more consistent than people, so read the numbers as "a careful machete player", not an average one.
Chests, the portal and orbs are not deliberately pursued. Day length is 120 s (ui.gd `DAY_LENGTH`).

## Answer: what limits the player, where is the choke point

Baseline (before tuning, after the flee-from-light removal), machete-kiting bot, 6 seeds: Easy dies around day 5
(9 min), Normal day 3, Getting Worse day 1, Hell under a minute. It matches the owner's report (Easy, day 5, ~290 kills).

1. **Stamina is the bottleneck (the choke point), not healing.** Machete swing = 12 stamina, regen 4/s, sprint 20/s.
   One swing costs as much as 3 s of regen, so sustained melee is about one swing per 3 s. The bot had stamina below
   12 for 43-72 % of every day on Easy (96 % at times on Normal) and then simply could not hit back: swings were
   refused ("attacks don't always respond"), enemies close in and chop. All baseline deaths follow the same pattern:
   stamina empty, then the HP bar goes, then the heal stock goes. Level-ups only give +5 max stamina, so it never
   scaled. The kill rate was capped by regen (about 4 stamina/s), not by enemy count.
2. **Healing is not unlimited, but it is generous.** Items per 48x48 chunk: 8-14 x drop scale, and 39 % of items are
   bandage/almond water. Measured: about 3-7 heals found per day while exploring versus 0-3 used per day; the bot held
   8-14 spare heals on Easy for the first ten days. Healing only becomes a constraint once damage per day exceeds ~100
   (Easy day 10+). Not an issue; the stock simply gets spent when pressure arrives.
3. **Enemy cap filled with harmless wanderers.** `list.size() >= max_enemies` counted every enemy within 35 tiles
   (cap 30 + 2 x day, difficulty cap 90-130). Idle wanderers filled it and no new hunters spawned near the player, so
   once stamina was fixed kills/day collapsed from ~60 to ~20 and damage taken fell to zero for days 1-8. Spawn
   pressure was effectively capped far too low relative to the spawn rate.
4. **Enemy scaling is too slow to matter before day 8.** hp +5 %/day, dmg +3.5 %/day, speed +1 %/day, spawn interval
   -0.07 s/day. Skin stealers/crawlers (the only things that hurt a kiter) only join at wave 5 and are 40-65 % of
   all damage after that. Player scaling (level 10 by day 8: +90 max HP, +45 stamina, a perk every 2 levels) outpaces
   that until ~day 9. Pre-day-5 enemies are hound/wretch/shade, none of which can hurt a kiting player once stamina works.
5. **Kiting is safe by design.** Machete reach 2.5 vs enemy reach 0.75-1.7, hunting speed = 0.75 x speed (hound 2.4,
   wretch 3.0 vs player 3.5, sprint 5.6). Only wretch/hound wind-ups (0.16/0.22 s) were shorter than reaction time; now
   0.25/0.30 s.
6. **Hydration, sanity, noise barely matter.** Hydration 0 had no penalty except doubling sanity drain; sanity < 25 % only
   adds fumbled swings;. Hydration now hurts (see changes). Noise only affects
   when enemies notice you, not how many come.
7. **The headlamp does not trivialise light-fearing enemies.** `HEADLAMP_DPS = 1.25 x fear x closeness`: at best ~1 hp/s
   on a 15-20 hp enemy at point blank, nothing at range. Battery: 0.55/s drain (about 180 s per battery) and it
   recharges while off, so batteries are never the limit (2 start + drops). No change.
8. **Perks:** Tough Skin (-15 %), Thick Skull (2x i-frames) and Second Wind stack but the pool is only 12, picked every
   2 levels, so by level 12 a build has ~6 perks; the effect is real but not game-breaking. Bug found: Trigger Finger
   ("weapons fire 20 % faster") only changed `run_mods.rate_mod`, which nothing read. Fixed.
9. **Difficulty spread was too wide at the top.** Hell/Getting Worse had 1.8x/1.35x hp, 2x/1.4x damage, 3x/2.5x
   spawns: bot died in 0.5-2 min (day 1). The mild scaling at the bottom plus cliffs at the top gave no middle.
   `wave >= 5` (skin stealers) is the real cliff: whichever mode reaches it first dies there.

What stops being challenging: before tuning, nothing stopped it from being a stamina fight; after fixing stamina
the machete player takes ~0 damage until the first skin stealers appear (wave 5-7), then pressure grows each day.

## Results

Competent machete kiting bot ("kite"), time of death (minutes at 2 min/day), median over seeds. Cap 30 min.

| Difficulty | Before (6 seeds) | After (8 seeds) | Target |
|---|---|---|---|
| Easy | day 5 (9.0 min, range 2.8-11.5), 239 kills | day 12 (24.7 min, 16.3 to 30+; 1 of 8 survived the cap), 238 kills | 8-12 |
| Normal | day 3 (5.2 min, 1.8-8.2) | day 7 (12.9 min, 9.5-21.8) | 5-8 |
| Getting Worse | day 1 (1.4 min, 1.0-2.2) | day 5 (9.2 min, 4.8-16.8) | 3-5 |
| Hell | day 1 (0.8 min, 0.5-5.2) | day 2 (3.8 min, 1.3-9.3) | 2-3 |

Variants after tuning (4 seeds): `weapons=best` (picks up shotgun/smg/axe): Easy day 12, Normal day 6, GW day 3, Hell day 3.
`skill=brawl` (stands and trades): Easy day 6 (12.6 min), Normal day 2, GW/Hell day 1. A player who does not step
back from attacks dies far earlier, a kiter lives long. That spread is intended: skill matters.

Easy per-day (after, 8 seeds): damage taken 0 for days 1-6, ~10 on days 7-8, 76 / 120 / 73 / 141 on days 9-12; stamina below 12 for
0-18 % of days 1-8 (was 43-72 %), 32-37 % on days 9-12 (this is where the stamina pressure now bites); spare heals peak at 14
and drain to 3.5 by day 13 as damage rises. Kills/day 17-25 (was 34-61 because the bot spent most of the time starved
and surrounded). Full tables: run `run_balance.py ... --days`.

## Changes (old -> new, why)

| File / constant | Old | New | Reason |
|---|---|---|---|
| `player.gd` S.stamina_regen | 4.0 | 7.0 | stamina was the choke point; machete cost = 3 s of regen |
| `player.gd` S.sprint_cost | 20.0 | 16.0 | sprint-escape + swing shared one pool; 5 s sprint -> 6.25 s |
| `weapons.gd` stamina_cost machete / knife / pipe / axe | 12 / 8 / 15 / 20 | 7 / 5 / 9 / 12 | ~1 swing per second sustainable (7 regen vs 7 cost at 1 swing/s); guns unchanged (3-8) |
| `weapons.gd` melee below stamina cost | swing refused | allowed with stamina >= 1: 60 % damage (`TIRED_DMG`), recovery x1.35 (`TIRED_RATE`) | owner: "attacks don't always respond". Stamina is now pressure, not a lock-out. Ranged still needs the cost (it is tiny) |
| `weapons.gd` stamina subtraction | `-=` (could go negative, clamped later) | clamped at 0 | tidy |
| `player.gd` dehydration | no effect at 0 hydration | -1 hp/s at 0 hydration, never below 1 hp (`dehydration_dps`) | hydration/almond water now matters; not lethal on its own |
| `enemies.gd` hound windup | 0.22 s | 0.30 s | shorter than human reaction -> unavoidable hits (telegraphs must be dodgeable) |
| `enemies.gd` wretch windup | 0.16 s | 0.25 s | same |
| `enemies.gd` DIFF_HP (Easy/Normal/GW/Hell) | 1.0 / 1.0 / 1.35 / 1.8 | 1.0 / 1.0 / 1.15 / 1.2 | Hell/GW were day-1 deaths; spread now comes from WAVE_BONUS |
| `enemies.gd` DIFF_DMG | 0.70 / 1.20 / 1.40 / 2.00 | 0.65 / 0.90 / 1.10 / 1.15 | same; Easy slightly more forgiving, Normal no longer double-punished |
| `enemies.gd` DIFF_SPD | 1.0 / 1.0 / 1.10 / 1.20 | 0.95 / 1.0 / 1.03 / 1.08 | faster-than-player hounds on Hell removed kiting entirely |
| `enemies.gd` DIFF_SPAWN | 1.5 / 2.0 / 2.5 / 3.0 | 1.0 / 1.3 / 1.7 / 2.2 | with the near-cap fix spawn rate is real pressure |
| `enemies.gd` DIFF_CAP | 90 / 100 / 110 / 130 | 60 / 80 / 100 / 120 | cap now counts only nearby enemies |
| `enemies.gd` WAVE_BONUS (new) | - | 1 / 3 / 3 / 4 | added to the day for spawn mix, rate, cap, hp/dmg scaling: harder modes start further up the same ramp (Normal meets skin stealers on day 2, Hell on day 1) instead of just multiplying stats |
| `enemies.gd` CAP_RADIUS (new) | cap counted all enemies <35 tiles | cap counts enemies < 26 tiles | idle far wanderers blocked all spawns near the player |
| `enemy.gd` LATE_WAVE / LATE_HP / LATE_DMG (new) | hp +5 %/wave, dmg +3.5 %/wave | extra +6 % hp, +3 % dmg per wave above wave 8 | open-ended: even a strong build gets outpaced; this is what ends Easy around day 12 |
| `ui.gd` DIFF_ENEMY_HP/DMG/SPD, DIFF_SPAWN, DIFF_MAX_ENEMIES | old tables | mirrored to the values above | ui publishes them in `run_mods` (informational; keep in sync) |
| `progression.gd` Trigger Finger | only changed `run_mods.rate_mod` (unused) | also scales `weapons.rate_mod` x0.8 | bug: perk did nothing |
| `export_presets.cfg` exclude_filter | `assets/**/*.md` | `+ tools/**, docs/**` (all 3 presets) | do not ship the sim |

Unchanged on purpose: item/drop tables (heal supply is fine), XP curve (x1.5 per level stalls by itself around level 10-12),
batteries and headlamp numbers, noise, sanity (still only affects miss chance at < 25 % and visuals), bomb numbers,
perk/meta-upgrade values, enemy hp/damage/speed base table, enemy reach.

## Notes for follow-up
- Sanity still has almost no gameplay cost for a player who stays in light. Candidate: hallucination spawns or small stamina
  regen penalty below 25 %. Not done (would need FX/UI work).
- `ui.gd` tables are duplicated from `enemies.gd` (`enemies.set_difficulty` uses its own). Keep both identical.
- Sim noise is large (run-to-run spread is often 2x); use 8+ seeds when re-tuning. A full 30 min Easy run takes ~2 min of wall time.
- Meta upgrades (Constitution etc.) are not modelled in the sim (fresh profile). Players with many upgrades will outlast these numbers.
