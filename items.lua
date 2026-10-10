-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║ ITEMS.LUA — Pickups: health, ammo, weapons, bombs, batteries       ║
-- ║                                                                     ║
-- ║ ALL LOOT TUNING IS IN Items.LOOT BELOW.                            ║
-- ║ Change any number there and it flows through the whole game.        ║
-- ╚══════════════════════════════════════════════════════════════════════╝

-- items.lua
-- Pickups: health, stamina, weapons, ammo, bombs
-- Difficulty scales drop rates

local Items = {}
Items.__index = Items

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║ LOOT TABLE — every drop rate and spawn count in one place           ║
-- ║                                                                     ║
-- ║ CHUNK SPAWNS happen when a new map chunk is generated as you        ║
-- ║ explore. Items and orbs appear automatically in fresh areas.        ║
-- ║                                                                     ║
-- ║ KILL DROPS happen when you kill an enemy. The roll decides          ║
-- ║ whether you get an orb or an item.                                  ║
-- ║                                                                     ║
-- ║ INITIAL SPAWNS are placed around the starting area at game start.   ║
-- ║                                                                     ║
-- ║ DROP TYPE WEIGHTS control what kind of item spawns.                 ║
-- ║ Each threshold is cumulative: the item spawns if the roll is        ║
-- ║ between the previous threshold and this one.                        ║
-- ║   Example: bandage = 0.12, almondWater = 0.24                      ║
-- ║   means bandage spawns on rolls 0.00-0.12, almond water 0.12-0.24  ║
-- ║ The last category catches everything above the last threshold.      ║
-- ║                                                                     ║
-- ║ DIFFICULTY reduces drops by 20% per level above 1.                  ║
-- ║   Level 1 = 100%, Level 2 = 80%, Level 3 = 60%, Level 4 = 40%     ║
-- ╚══════════════════════════════════════════════════════════════════════╝
Items.LOOT = {
    -- ═══ CHUNK SPAWNS (new areas as you explore) ═══
    chunkItemsMin    = 8,     -- minimum items per new chunk
    chunkItemsMax    = 14,    -- maximum items per new chunk
    chunkOrbsMin     = 3,     -- minimum chaos orbs per new chunk
    chunkOrbsMax     = 6,     -- maximum chaos orbs per new chunk

    -- ═══ INITIAL SPAWNS (start of game, near spawn point) ═══
    initialItems     = 45,    -- items placed around starting area
    initialOrbs      = 10,    -- orbs placed around starting area

    -- ═══ KILL DROPS (when an enemy dies) ═══
    killDropChance   = 0.35,  -- chance an enemy drops anything at all (0-1)
    killOrbChance    = 0.40,  -- of that drop, chance it's an orb vs item (0-1)

    -- ═══ ITEM DESPAWN (cleanup for far-away items) ═══
    itemDespawnDist  = 60,    -- tiles — items beyond this get removed

    -- ═══ DROP TYPE WEIGHTS (cumulative thresholds, must end at 1.0) ═══
    -- Change these to shift what types of items appear.
    -- Each value is the upper roll boundary for that type.
    -- The gap between values = that item's spawn probability.
    typeBandage      = 0.12,  -- 12% bandage
    typeAlmondWater  = 0.24,  -- 12% almond water
    typeFood         = 0.35,  -- 11% food
    typeStamina      = 0.44,  -- 9% stamina drink
    typeAmmo         = 0.56,  -- 12% ammo
    typeWeapon       = 0.65,  -- 9% weapon (random type)
    typeBomb         = 0.74,  -- 9% bomb
    typeBattery      = 0.85,  -- 11% battery
    -- remaining 15% = extra almond water (fallback)

    -- ═══ DIFFICULTY SCALING ═══
    difficultyDropReduction = 0.20,  -- drop rate reduction per difficulty level above 1
    difficultyMinScale = 0.20,       -- floor — drops never go below this multiplier

    -- ═══ V5: BAD LUCK PROTECTION ═══
    badLuckChunkThreshold = 4,       -- chunks without a weapon drop before forced spawn
}

function Items.new(difficulty)
    local self = setmetatable({}, Items)
    self.list = {}
    self.difficulty = difficulty or 2
    self.difficultyIdx = difficulty or 2
    local L = Items.LOOT
    self.dropScale = math.max(L.difficultyMinScale, 1.0 - (self.difficulty - 1) * L.difficultyDropReduction)
    -- V5: bad luck protection state
    self.chunksSinceWeapon = 0  -- how many chunks spawned without a weapon drop
    return self
end

function Items:spawnOnMap(map, px, py, count)
    local scaled = math.floor((count or 40) * self.dropScale)
    for i = 1, scaled do
        local x, y = map:randomOpenTile(px, py, 5)
        local item = {x = x, y = y, pulseTimer = math.random() * 3}
        self:assignType(item, false)
        self.list[#self.list+1] = item
    end
end

function Items:spawnDrop(x, y, fromEnemy)
    -- difficulty reduces enemy drop spawns
    if fromEnemy and math.random() > self.dropScale then return end
    local item = {x = x, y = y, pulseTimer = 0}
    self:assignType(item, fromEnemy)
    self.list[#self.list+1] = item
end

function Items:assignType(item, fromEnemy)
    local L = Items.LOOT
    local roll = math.random()
    if roll < L.typeBandage then
        item.type = "bandage"
        item.color = {0.3, 1, 0.3}
    elseif roll < L.typeAlmondWater then
        item.type = "almond water"
        item.color = {0.3, 0.8, 1}
    elseif roll < L.typeFood then
        item.type = "food"
        item.color = {0.8, 0.6, 0.2}
    elseif roll < L.typeStamina then
        item.type = "stamina drink"
        item.color = {0.3, 0.5, 1}
    elseif roll < L.typeAmmo then
        item.type = "ammo"
        item.color = {0.9, 0.7, 0.1}
    elseif roll < L.typeWeapon then
        item.type = "weapon"
        item.weaponId = math.random(2, 8)
        local Weapons = require("weapons")
        local wepDef = Weapons.list[item.weaponId]
        item.color = wepDef.color
        item.weaponType = wepDef.type
        item.weaponName = wepDef.name
        -- V5: natural weapon drop resets bad luck counter
        self.chunksSinceWeapon = 0
    elseif roll < L.typeBomb then
        item.type = "bomb"
        item.color = {1, 0.5, 0.1}
    elseif roll < L.typeBattery then
        item.type = "battery"
        item.color = {0.2, 1, 0.6}
    else
        item.type = "almond water"
        item.color = {0.3, 0.8, 1}
    end
end

-- ═══ V5: BAD LUCK PROTECTION HELPERS ═══
-- Call after spawning a chunk's worth of items. Increments the drought counter.
-- Returns true if a forced weapon should be spawned.
function Items:trackChunkForBadLuck()
    self.chunksSinceWeapon = self.chunksSinceWeapon + 1
    return self.chunksSinceWeapon >= (Items.LOOT.badLuckChunkThreshold or 4)
end

-- Spawn a forced weapon drop at the given position. Resets the drought counter.
function Items:spawnForcedWeapon(x, y)
    local Weapons = require("weapons")
    local wepId = math.random(2, 8)
    local wepDef = Weapons.list[wepId]
    self.list[#self.list + 1] = {
        x = x, y = y,
        type = "weapon", weaponId = wepId,
        color = wepDef.color, weaponType = wepDef.type, weaponName = wepDef.name,
        pulseTimer = 0,
    }
    self.chunksSinceWeapon = 0
end

function Items:update(dt, px, py)
    -- despawn items too far from player (keeps list manageable)
    if px and py then
        local despawnDist = Items.LOOT.itemDespawnDist
        local despawnSq = despawnDist * despawnDist
        local i = #self.list
        while i >= 1 do
            local item = self.list[i]
            local dx = px - item.x; local dy = py - item.y
            if dx*dx + dy*dy > despawnSq then
                table.remove(self.list, i)
            end
            i = i - 1
        end
    end
    for _, item in ipairs(self.list) do
        item.pulseTimer = item.pulseTimer + dt
    end
end

function Items:checkPickup(px, py, player, weapons, bomb)
    local pickupRadius = 0.5
    local msgs = {}
    local i = 1
    while i <= #self.list do
        local item = self.list[i]
        local dx = px - item.x; local dy = py - item.y
        if dx*dx + dy*dy < pickupRadius then
            local msg = self:applyItem(item, player, weapons, bomb)
            if msg then msgs[#msgs+1] = msg end
            table.remove(self.list, i)
        else i = i + 1 end
    end
    return msgs
end

function Items:applyItem(item, player, weapons, bomb)
    if item.type == "bandage" then
        player.bandages = player.bandages + 1
        return {text = "+1 Bandage", color = {0.3, 1, 0.3}}
    elseif item.type == "almond water" then
        player.almondWater = player.almondWater + 1
        return {text = "+1 Almond Water", color = {0.3, 0.8, 1}}
    elseif item.type == "food" then
        local S = require("player").STATS
        player.stamina = math.min(player.maxStamina, player.stamina + S.foodStamina)
        player.sanity = math.min(player.maxSanity, player.sanity + S.foodSanity)
        return {text = "+"..S.foodStamina.." Stamina +"..S.foodSanity.." Sanity", color = {0.8, 0.6, 0.2}}
    elseif item.type == "stamina drink" then
        player.stamina = math.min(player.maxStamina, player.stamina + 30)
        return {text = "+30 Stamina", color = {0.3, 0.5, 1}}
    elseif item.type == "ammo" then
        weapons:addAmmo()
        return {text = "+25 Ammo ("..weapons.ammo..")", color = {0.9, 0.7, 0.1}}
    elseif item.type == "weapon" then
        if item.weaponId and item.weaponId <= #weapons.list then
            local wasUnlocked = weapons:isUnlocked(item.weaponId)
            weapons:unlockWeapon(item.weaponId)
            -- don't auto-switch: player keeps current weapon
            local wep = weapons.list[item.weaponId]
            local ammoMsg = ""
            if wep.type == "ranged" then
                weapons:addAmmo(25)
                ammoMsg = " +25 Ammo"
            end
            if not wasUnlocked then
                return {text = "NEW: "..wep.name:upper().."!"..ammoMsg, color = wep.color}
            else
                return {text = "Got "..wep.name..ammoMsg, color = wep.color}
            end
        end
    elseif item.type == "bomb" then
        if bomb then
            -- cap based on difficulty: 5/4/3/2
            local maxBombs = math.max(2, 6 - (self.difficultyIdx or 2))
            if bomb.count < maxBombs then
                bomb.count = bomb.count + 1
                return {text = "+1 Bomb! ("..bomb.count.."/"..maxBombs..")", color = {1, 0.5, 0.1}}
            else
                return {text = "BOMBS FULL ("..maxBombs.."/"..maxBombs..")", color = {0.6, 0.4, 0.2}}
            end
        end
    elseif item.type == "battery" then
        -- cap based on difficulty: 3/2/1/0
        local maxBat = math.max(0, 4 - (self.difficultyIdx or 2))
        local cur = player.batteries or 0
        if cur < maxBat then
            player.batteries = cur + 1
            return {text = "+1 Battery ("..player.batteries.."/"..maxBat..")", color = {0.2, 1, 0.6}}
        else
            return {text = "BATTERIES FULL ("..maxBat.."/"..maxBat..")", color = {0.2, 0.6, 0.4}}
        end
    end
    return nil
end

-- ═══ V3: MILITARY CHEST LOOT ═══
-- Spawns a cluster of guaranteed high-value items around the chest center.
-- Includes a weapon the player doesn't have yet (or ammo+bombs if all unlocked).
function Items:spawnChestLoot(cx, cy, weapons)
    local Weapons = require("weapons")
    local spread = 2.5  -- items scatter within this radius

    local function jitter()
        return (math.random() - 0.5) * spread * 2
    end

    -- guaranteed weapon drop: pick one the player hasn't unlocked
    local lockedId = weapons:getRandomLockedWeapon()
    if lockedId then
        local wep = Weapons.list[lockedId]
        self.list[#self.list + 1] = {
            x = cx + jitter(), y = cy + jitter(),
            type = "weapon", weaponId = lockedId,
            color = wep.color, weaponType = wep.type, weaponName = wep.name,
            pulseTimer = 0,
        }
    else
        -- all weapons unlocked: give bonus ammo + bomb instead
        self.list[#self.list + 1] = {x = cx + jitter(), y = cy + jitter(), type = "ammo", color = {0.9, 0.7, 0.1}, pulseTimer = 0}
        self.list[#self.list + 1] = {x = cx + jitter(), y = cy + jitter(), type = "ammo", color = {0.9, 0.7, 0.1}, pulseTimer = 0}
        self.list[#self.list + 1] = {x = cx + jitter(), y = cy + jitter(), type = "bomb", color = {1, 0.5, 0.1}, pulseTimer = 0}
    end

    -- guaranteed support items
    local loot = {
        {type = "ammo",         color = {0.9, 0.7, 0.1}},
        {type = "ammo",         color = {0.9, 0.7, 0.1}},
        {type = "bandage",      color = {0.3, 1, 0.3}},
        {type = "bandage",      color = {0.3, 1, 0.3}},
        {type = "almond water", color = {0.3, 0.8, 1}},
        {type = "almond water", color = {0.3, 0.8, 1}},
        {type = "battery",      color = {0.2, 1, 0.6}},
        {type = "bomb",         color = {1, 0.5, 0.1}},
    }
    for _, item in ipairs(loot) do
        self.list[#self.list + 1] = {
            x = cx + jitter(), y = cy + jitter(),
            type = item.type, color = item.color, pulseTimer = 0,
        }
    end
end

return Items
