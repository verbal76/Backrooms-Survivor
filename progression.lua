-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║ PROGRESSION.LUA — Persistent meta-upgrades between runs              ║
-- ║                                                                     ║
-- ║ WHAT THIS DOES:                                                     ║
-- ║   Each death earns Tokens (1 per day survived + kill bonus).        ║
-- ║   Tokens buy permanent stat boosts from the upgrade shop.           ║
-- ║   Each difficulty has its OWN separate profile per character,       ║
-- ║   so Easy progress doesn't carry to Normal.                         ║
-- ║                                                                     ║
-- ║ CHARACTER SYSTEM:                                                   ║
-- ║   Up to 10 named characters, each fully independent.               ║
-- ║   Nothing carries over between characters.                          ║
-- ║   Each character has 4 difficulty profiles (Easy/Normal/Worse/Hell) ║
-- ║   Data persists between game sessions via love.filesystem.          ║
-- ║                                                                     ║
-- ║ V2 CHANGES:                                                         ║
-- ║   Save format v3: adds bestStreak, bestTime per profile             ║
-- ║   1 token minimum per run (you always earn something)               ║
-- ║   Time survival bonus (1 token per 2 min survived)                  ║
-- ║   Upgrade costs rebalanced for ~40-60 run progression               ║
-- ║                                                                     ║
-- ║ HOW TO MOD:                                                         ║
-- ║   Add new upgrades to UPGRADES table below                          ║
-- ║   Change token earning formula in calcTokens()                      ║
-- ║   Adjust max levels and cost curves per upgrade                     ║
-- ║   The applyToPlayer() function applies all upgrades at game start   ║
-- ║                                                                     ║
-- ║ SAVE FILE: backrooms_save.dat (Lua table in love2d appdata folder)  ║
-- ╚══════════════════════════════════════════════════════════════════════╝

local Progression = {}
Progression.__index = Progression

Progression.MAX_CHARACTERS = 10

-- ═══ UPGRADE DEFINITIONS ═══
-- V2: Rebalanced costs. baseCost and costGrowth increased so a full
-- upgrade path takes roughly 40-60 runs instead of 10-20.
Progression.UPGRADES = {
    {
        id = "max_hp",
        name = "Constitution",
        desc = "+10 Max HP per level",
        maxLevel = 10,
        baseCost = 4,
        costGrowth = 3,
        apply = function(player, level)
            player.maxHp = player.maxHp + level * 10
            player.hp = player.maxHp
        end,
    },
    {
        id = "max_stamina",
        name = "Endurance",
        desc = "+8 Max Stamina per level",
        maxLevel = 10,
        baseCost = 4,
        costGrowth = 3,
        apply = function(player, level)
            player.maxStamina = player.maxStamina + level * 8
            player.stamina = player.maxStamina
        end,
    },
    {
        id = "move_speed",
        name = "Agility",
        desc = "+3% Move Speed per level",
        maxLevel = 8,
        baseCost = 5,
        costGrowth = 4,
        apply = function(player, level)
            player.speedMult = player.speedMult + level * 0.03
        end,
    },
    {
        id = "sanity_resist",
        name = "Iron Mind",
        desc = "-5% Sanity Drain per level",
        maxLevel = 10,
        baseCost = 5,
        costGrowth = 3,
        apply = function(player, level)
            player.sanityDrain = player.sanityDrain * (1.0 - level * 0.05)
        end,
    },
    {
        id = "hydration_resist",
        name = "Camel Blood",
        desc = "-5% Hydration Drain per level",
        maxLevel = 8,
        baseCost = 4,
        costGrowth = 3,
        apply = function(player, level)
            player.hydrationDrain = player.hydrationDrain * (1.0 - level * 0.05)
        end,
    },
    {
        id = "start_ammo",
        name = "Ammunition Cache",
        desc = "+5 Starting Ammo per level",
        maxLevel = 6,
        baseCost = 3,
        costGrowth = 2,
        applyWeapons = function(weapons, level)
            weapons.ammo = weapons.ammo + level * 5
        end,
    },
    {
        id = "start_bombs",
        name = "Demolitions Training",
        desc = "+1 Starting Bomb per level",
        maxLevel = 4,
        baseCost = 6,
        costGrowth = 5,
        applyBomb = function(bomb, level)
            bomb.count = bomb.count + level
        end,
    },
    {
        id = "start_batteries",
        name = "Power Hoarder",
        desc = "+1 Starting Battery per level",
        maxLevel = 4,
        baseCost = 5,
        costGrowth = 3,
        apply = function(player, level)
            player.batteries = player.batteries + level
        end,
    },
    {
        id = "lamp_capacity",
        name = "Extended Battery",
        desc = "+15% Headlamp Battery Life per level",
        maxLevel = 6,
        baseCost = 5,
        costGrowth = 4,
        getLampBonus = function(level)
            return level * 0.15
        end,
    },
    {
        id = "damage_boost",
        name = "Combat Training",
        desc = "+5% Base Damage per level",
        maxLevel = 8,
        baseCost = 6,
        costGrowth = 4,
        apply = function(player, level)
            player.dmgMult = player.dmgMult + level * 0.05
        end,
    },
}

-- ═══ TOKEN EARNING ═══
-- V2: Added time bonus (1 token per 2 min survived) and math.max(1, ...)
-- so every run earns at least 1 token. runTime in seconds.
function Progression.calcTokens(daysSurvived, kills, difficulty, runTime)
    local diffMult = ({0.5, 1.0, 1.5, 2.0})[difficulty] or 1.0
    local base = daysSurvived
    local killBonus = math.floor(kills / 10)
    local timeBonus = math.floor((runTime or 0) / 120)  -- 1 token per 2 minutes
    return math.max(1, math.floor((base + killBonus + timeBonus) * diffMult))
end

-- ═══ V3: RUN PERKS — temporary buffs chosen on level-up ═══
-- Each perk has an apply(player, weapons, bomb) function that modifies
-- stats for the current run only. Player picks 1 of 2 random perks.
Progression.RUN_PERKS = {
    {
        id = "tough_skin", name = "Tough Skin",
        desc = "Take 15% less damage from all sources.",
        apply = function(player, weapons, bomb)
            -- Reduce incoming damage by storing a multiplier
            -- (applied via player.dmgTakenMult in takeDamage)
            player.dmgTakenMult = (player.dmgTakenMult or 1.0) * 0.85
        end,
    },
    {
        id = "second_wind", name = "Second Wind",
        desc = "+30 Max HP and heal to full.",
        apply = function(player, weapons, bomb)
            player.maxHp = player.maxHp + 30
            player.hp = player.maxHp
        end,
    },
    {
        id = "quick_feet", name = "Quick Feet",
        desc = "+10% movement speed.",
        apply = function(player, weapons, bomb)
            player.speedMult = player.speedMult + 0.10
        end,
    },
    {
        id = "heavy_hitter", name = "Heavy Hitter",
        desc = "+15% weapon damage.",
        apply = function(player, weapons, bomb)
            player.dmgMult = player.dmgMult + 0.15
        end,
    },
    {
        id = "clear_mind", name = "Clear Mind",
        desc = "Sanity drains 30% slower.",
        apply = function(player, weapons, bomb)
            player.sanityDrain = player.sanityDrain * 0.70
        end,
    },
    {
        id = "deep_reservoir", name = "Deep Reservoir",
        desc = "Hydration drains 30% slower.",
        apply = function(player, weapons, bomb)
            player.hydrationDrain = player.hydrationDrain * 0.70
        end,
    },
    {
        id = "ammo_cache", name = "Ammo Cache",
        desc = "+40 ammo right now.",
        apply = function(player, weapons, bomb)
            if weapons then weapons.ammo = weapons.ammo + 40 end
        end,
    },
    {
        id = "trigger_finger", name = "Trigger Finger",
        desc = "Weapons fire 20% faster.",
        apply = function(player, weapons, bomb)
            if weapons then weapons.rateMod = weapons.rateMod * 0.80 end
        end,
    },
    {
        id = "boom_boom", name = "Boom Boom",
        desc = "+2 bombs right now.",
        apply = function(player, weapons, bomb)
            if bomb then bomb.count = bomb.count + 2 end
        end,
    },
    {
        id = "field_medic", name = "Field Medic",
        desc = "+2 bandages and +2 almond water.",
        apply = function(player, weapons, bomb)
            player.bandages = player.bandages + 2
            player.almondWater = player.almondWater + 2
        end,
    },
    {
        id = "thick_skull", name = "Thick Skull",
        desc = "Invulnerability after hit lasts 2x longer.",
        apply = function(player, weapons, bomb)
            player.invulnTimeMult = (player.invulnTimeMult or 1.0) * 2.0
        end,
    },
    {
        id = "marathon", name = "Marathon Runner",
        desc = "+30 max stamina and sprint costs 25% less.",
        apply = function(player, weapons, bomb)
            player.maxStamina = player.maxStamina + 30
            player.stamina = player.maxStamina
            player.sprintCost = player.sprintCost * 0.75
        end,
    },
}

-- Roll 2 random perks for the player to choose from.
-- excludeIds is a table of perk IDs already chosen this run.
function Progression.rollPerkChoice(excludeIds)
    local pool = {}
    local excluded = {}
    if excludeIds then
        for _, id in ipairs(excludeIds) do excluded[id] = true end
    end
    for _, perk in ipairs(Progression.RUN_PERKS) do
        if not excluded[perk.id] then
            pool[#pool + 1] = perk
        end
    end
    if #pool < 2 then return nil end  -- not enough perks left
    -- shuffle and pick first 2
    for i = #pool, 2, -1 do
        local j = math.random(1, i)
        pool[i], pool[j] = pool[j], pool[i]
    end
    return { pool[1], pool[2] }
end

-- ═══ SAVE FILE FORMAT ═══
-- {
--   version = 3,
--   characters = {
--     [1] = {
--       name = "Kevin",
--       profiles = {
--         [1] = { tokens=15, upgrades={max_hp=2,...}, bestDay=5, bestKills=20,
--                 bestStreak=12, bestTime=360.5, totalRuns=3 },
--         [2] = { ... }, [3] = { ... }, [4] = { ... },
--       }
--     },
--   }
-- }

local SAVE_FILE = "backrooms_save.dat"

function Progression.new()
    local self = setmetatable({}, Progression)
    self.characters = {}
    self.activeCharIdx = nil
    self:load()
    return self
end

function Progression._newProfiles()
    local profiles = {}
    for i = 1, 4 do
        profiles[i] = {
            tokens = 0,
            upgrades = {},
            bestDay = 0,
            bestKills = 0,
            bestStreak = 0,    -- V2: best kill streak
            bestTime = 0,      -- V2: longest run in seconds
            totalRuns = 0,
        }
    end
    return profiles
end

-- ═══ CHARACTER MANAGEMENT ═══

function Progression:getCharacterCount()
    return #self.characters
end


function Progression:getCharacterSummary(idx)
    local ch = self.characters[idx]
    if not ch then return nil end
    local totalRuns = 0
    local bestDay = 0
    local bestDayByDiff = {0,0,0,0}
    local bestKills = 0
    local bestStreak = 0
    local totalTokens = 0
    for d = 1, 4 do
        local p = ch.profiles[d]
        bestDayByDiff[d] = (p and p.bestDay) or 0
        if p then
            totalRuns = totalRuns + (p.totalRuns or 0)
            if (p.bestDay or 0) > bestDay then bestDay = p.bestDay end
            if (p.bestKills or 0) > bestKills then bestKills = p.bestKills end
            if (p.bestStreak or 0) > bestStreak then bestStreak = p.bestStreak end
            totalTokens = totalTokens + (p.tokens or 0)
        end
    end
    return {
        name = ch.name,
        totalRuns = totalRuns,
        bestDay = bestDay,
        bestDayByDiff = bestDayByDiff,
        bestKills = bestKills,
        bestStreak = bestStreak,
        totalTokens = totalTokens,
    }
end

function Progression:addCharacter(name)
    if #self.characters >= Progression.MAX_CHARACTERS then return false end
    self.characters[#self.characters + 1] = {
        name = name,
        profiles = Progression._newProfiles(),
    }
    self:save()
    return true
end

function Progression:deleteCharacter(idx)
    if idx < 1 or idx > #self.characters then return false end
    table.remove(self.characters, idx)
    if self.activeCharIdx then
        if self.activeCharIdx == idx then
            self.activeCharIdx = nil
        elseif self.activeCharIdx > idx then
            self.activeCharIdx = self.activeCharIdx - 1
        end
    end
    self:save()
    return true
end

function Progression:setActiveCharacter(idx)
    if idx >= 1 and idx <= #self.characters then
        self.activeCharIdx = idx
        return true
    end
    return false
end

function Progression:getActiveCharacterName()
    if self.activeCharIdx and self.characters[self.activeCharIdx] then
        return self.characters[self.activeCharIdx].name
    end
    return "Subject"
end

-- ═══ PROFILE ACCESS (scoped to active character) ═══

function Progression:getProfile(difficulty)
    local empty = { tokens = 0, upgrades = {}, bestDay = 0, bestKills = 0, bestStreak = 0, bestTime = 0, totalRuns = 0 }
    if not self.activeCharIdx then return empty end
    local ch = self.characters[self.activeCharIdx]
    if not ch then return empty end
    return ch.profiles[difficulty] or ch.profiles[1]
end

function Progression:getUpgradeLevel(difficulty, upgradeId)
    local profile = self:getProfile(difficulty)
    return profile.upgrades[upgradeId] or 0
end

function Progression:getUpgradeCost(upgradeId, currentLevel)
    for _, def in ipairs(Progression.UPGRADES) do
        if def.id == upgradeId then
            return def.baseCost + currentLevel * def.costGrowth
        end
    end
    return 999
end

function Progression:canAfford(difficulty, upgradeId)
    local profile = self:getProfile(difficulty)
    local level = profile.upgrades[upgradeId] or 0
    local cost = self:getUpgradeCost(upgradeId, level)
    for _, def in ipairs(Progression.UPGRADES) do
        if def.id == upgradeId then
            if level >= def.maxLevel then return false end
            break
        end
    end
    return profile.tokens >= cost
end

function Progression:buyUpgrade(difficulty, upgradeId)
    if not self:canAfford(difficulty, upgradeId) then return false end
    local profile = self:getProfile(difficulty)
    local level = profile.upgrades[upgradeId] or 0
    local cost = self:getUpgradeCost(upgradeId, level)
    profile.tokens = profile.tokens - cost
    profile.upgrades[upgradeId] = level + 1
    self:save()
    return true
end

-- V2: Now accepts bestStreak and runTime params
function Progression:addRunResults(difficulty, daysSurvived, kills, bestStreak, runTime)
    local profile = self:getProfile(difficulty)
    local earned = Progression.calcTokens(daysSurvived, kills, difficulty, runTime)
    profile.tokens = profile.tokens + earned
    profile.totalRuns = profile.totalRuns + 1
    if daysSurvived > profile.bestDay then profile.bestDay = daysSurvived end
    if kills > profile.bestKills then profile.bestKills = kills end
    if (bestStreak or 0) > (profile.bestStreak or 0) then profile.bestStreak = bestStreak end
    if (runTime or 0) > (profile.bestTime or 0) then profile.bestTime = runTime end
    self:save()
    return earned
end

-- ═══ V4: PER-DIFFICULTY STATS for title screen display ═══
-- Returns the active character's stats for a specific difficulty.
function Progression:getProfileStats(difficulty)
    local p = self:getProfile(difficulty)
    return {
        bestDay = p.bestDay or 0,
        bestKills = p.bestKills or 0,
        bestStreak = p.bestStreak or 0,
        bestTime = p.bestTime or 0,
        totalRuns = p.totalRuns or 0,
        tokens = p.tokens or 0,
    }
end

-- ═══ V4: RANKED CHARACTER LIST for character select leaderboard ═══
-- Returns all characters with their stats for a given difficulty,
-- sorted by sortField ("bestDay", "bestKills", "bestStreak", "bestTime", "totalRuns").

function Progression:applyToPlayer(difficulty, player)
    for _, def in ipairs(Progression.UPGRADES) do
        local level = self:getUpgradeLevel(difficulty, def.id)
        if level > 0 and def.apply then
            def.apply(player, level)
        end
    end
end

function Progression:applyToWeapons(difficulty, weapons)
    for _, def in ipairs(Progression.UPGRADES) do
        local level = self:getUpgradeLevel(difficulty, def.id)
        if level > 0 and def.applyWeapons then
            def.applyWeapons(weapons, level)
        end
    end
end

function Progression:applyToBomb(difficulty, bomb)
    for _, def in ipairs(Progression.UPGRADES) do
        local level = self:getUpgradeLevel(difficulty, def.id)
        if level > 0 and def.applyBomb then
            def.applyBomb(bomb, level)
        end
    end
end

function Progression:getLampBonus(difficulty)
    for _, def in ipairs(Progression.UPGRADES) do
        if def.id == "lamp_capacity" then
            local level = self:getUpgradeLevel(difficulty, def.id)
            if level > 0 and def.getLampBonus then
                return def.getLampBonus(level)
            end
        end
    end
    return 0
end

-- ═══ SAVE / LOAD ═══

function Progression:save()
    -- Safer save routine:
    -- 1) write to .tmp
    -- 2) keep a .bak of the last good save
    -- 3) rename .tmp into place
    local payload = {
        version = 3,
        characters = self.characters,
    }
    local data = "return " .. Progression._serialize(payload)

    local tmp = SAVE_FILE .. ".tmp"
    local bak = SAVE_FILE .. ".bak"

    local ok, err = love.filesystem.write(tmp, data)
    if not ok then
        print("Save failed (tmp write): " .. tostring(err))
        return false
    end

    -- Backup current save (best effort)
    if love.filesystem.getInfo(SAVE_FILE) then
        local cur = love.filesystem.read(SAVE_FILE)
        if cur then
            love.filesystem.remove(bak)
            love.filesystem.write(bak, cur)
        end
    end

    -- Replace main save
    -- NOTE: love.filesystem.rename does not exist in some LÖVE versions.
    -- We prefer an atomic rename when possible, otherwise we fall back to OS rename.
    local function safeRename(from, to)
        if love.filesystem.rename then
            return love.filesystem.rename(from, to)
        end
        -- Fallback: use OS rename on the save directory path
        local dir = love.filesystem.getSaveDirectory()
        local src = dir .. "/" .. from
        local dst = dir .. "/" .. to
        -- Windows rename fails if destination exists
        os.remove(dst)
        return os.rename(src, dst) ~= nil
    end

    love.filesystem.remove(SAVE_FILE)
    local renamed = safeRename(tmp, SAVE_FILE)
    if not renamed then
        -- If rename fails, try direct write as last resort
        local ok2, err2 = love.filesystem.write(SAVE_FILE, data)
        if not ok2 then
            print("Save failed (final write): " .. tostring(err2))
            return false
        end
        love.filesystem.remove(tmp)
    end
    return true
end


function Progression:load()
    local function tryRead(path)
        if not love.filesystem.getInfo(path) then return nil end
        local content = love.filesystem.read(path)
        if not content then return nil end
        local fn = loadstring(content)
        if not fn then return nil end
        local ok, result = pcall(fn)
        if not ok or type(result) ~= "table" then return nil end
        return result
    end

    local result = tryRead(SAVE_FILE)

    -- If the main save is missing or corrupt, fall back to the backup
    if not result then
        result = tryRead(SAVE_FILE .. ".bak")
        if not result then return end
    end

    local ver = result.version or 1

    if (ver == 2 or ver == 3) and result.characters then
        -- version 2 or 3: per-character save
        self.characters = {}
        for i, ch in ipairs(result.characters) do
            if ch.name then
                local character = { name = ch.name, profiles = Progression._newProfiles() }
                if ch.profiles then
                    for d = 1, 4 do
                        if ch.profiles[d] then
                            local src = ch.profiles[d]
                            local dst = character.profiles[d]
                            dst.tokens = src.tokens or 0
                            dst.upgrades = src.upgrades or {}
                            dst.bestDay = src.bestDay or 0
                            dst.bestKills = src.bestKills or 0
                            dst.bestStreak = src.bestStreak or 0
                            dst.bestTime = src.bestTime or 0
                            dst.totalRuns = src.totalRuns or 0
                        end
                    end
                end
                self.characters[#self.characters + 1] = character
            end
        end
        -- if loaded from v2, re-save as v3
        if ver < 3 then self:save() end
    else
        -- version 1 (legacy): migrate bare profiles to character "Subject"
        local legacy = result
        local character = { name = "Subject", profiles = Progression._newProfiles() }
        local hasData = false
        for i = 1, 4 do
            if legacy[i] then
                character.profiles[i].tokens = legacy[i].tokens or 0
                character.profiles[i].upgrades = legacy[i].upgrades or {}
                character.profiles[i].bestDay = legacy[i].bestDay or 0
                character.profiles[i].bestKills = legacy[i].bestKills or 0
                character.profiles[i].totalRuns = legacy[i].totalRuns or 0
                if character.profiles[i].totalRuns > 0 or character.profiles[i].tokens > 0 then
                    hasData = true
                end
            end
        end
        if hasData then
            self.characters[1] = character
        end
        self:save()  -- write new format
    end
end

-- ═══ SERIALIZATION ═══
function Progression._serialize(tbl)
    local parts = {"{"}
    for k, v in pairs(tbl) do
        local key
        if type(k) == "number" then key = "[" .. k .. "]"
        elseif type(k) == "string" then key = '["' .. k .. '"]'
        else key = tostring(k) end

        if type(v) == "table" then
            parts[#parts+1] = key .. "=" .. Progression._serialize(v) .. ","
        elseif type(v) == "string" then
            parts[#parts+1] = key .. '="' .. v .. '",'
        elseif type(v) == "number" then
            parts[#parts+1] = key .. "=" .. v .. ","
        elseif type(v) == "boolean" then
            parts[#parts+1] = key .. "=" .. tostring(v) .. ","
        end
    end
    parts[#parts+1] = "}"
    return table.concat(parts)
end

return Progression
