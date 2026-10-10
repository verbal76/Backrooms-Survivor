-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║ PLAYER.LUA — Player state, movement, survival stats                  ║
-- ║                                                                      ║ 
-- ║ ALL TUNABLE PLAYER STATS ARE IN THE STAT BLOCK BELOW.                ║ 
-- ║ Change any value there and it flows through the whole game.          ║
-- ║                                                                      ║
-- ║ V2 ADDITIONS:                                                        ║
-- ║   Kill streak tracking (currentStreak, bestRunStreak)                ║
-- ║   Streak XP multiplier (scales with consecutive kills)               ║
-- ║   Streak milestone flash for HUD                                     ║
-- ║ V3 ADDITIONS:                                                        ║
-- ║   pendingPerkChoice flag for level-up perk selection                 ║
-- ║   activeRunPerks[] tracks temporary buffs chosen during run          ║
-- ╚══════════════════════════════════════════════════════════════════════╝
-- player.lua
-- Player state, movement, stats, sanity, noise

local Player = {}
Player.__index = Player
-- This is the level selector for how many levels need to pass to get a perk selection
Player.PERK_EVERY_N_LEVELS = 2
-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║ PLAYER STAT BLOCK — edit these to balance the game                   ║
-- ║                                                                      ║
-- ║ All player tuning in one place. Change a number here and it          ║
-- ║ affects everything: combat, survival, movement, progression.         ║
-- ╚══════════════════════════════════════════════════════════════════════╝
Player.STATS = {
    -- HEALTH & DEFENSE
    hp              = 100,      -- starting and max health
    lives           = 1,        -- extra lives (1 = no respawn)
    invulnTime      = 1.0,      -- seconds of invulnerability after being hit

    -- STAMINA
    stamina         = 100,      -- starting and max stamina
    staminaRegen    = 4,        -- stamina recovered per second
    sprintCost      = 20,       -- stamina spent per second while sprinting

    -- SANITY
    sanity          = 100,      -- starting and max sanity
    sanityDrain     = 0.25,     -- base drain per second (increases in darkness)
    sanityLightMin  = 0.2,      -- light level below this = no regen (was 0.4)
    sanityRegenMult = 4.0,      -- regen multiplier (higher = faster recovery in light)

    -- HYDRATION
    hydration       = 100,      -- starting and max hydration
    hydrationDrain  = 0.5,      -- base drain per second
    hydrationSprint = 1.5,      -- drain multiplier while sprinting

    -- MOVEMENT
    baseSpeed       = 3.5,      -- tiles per second (walking)
    sprintMult      = 1.6,      -- speed multiplier while sprinting
    accel           = 18,       -- acceleration (higher = snappier)
    decel           = 14,       -- deceleration (higher = stops faster)

    -- COMBAT
    dmgMult         = 1.0,      -- damage multiplier (1.0 = normal)

    -- NOISE (affects enemy detection)
    baseNoise       = 2,        -- idle noise per second
    moveNoise       = 12,       -- walking noise per second
    sprintNoise     = 25,       -- sprinting noise per second
    noiseDecay      = 30,       -- noise decay per second

    -- STARTING INVENTORY
    almondWater     = 3,        -- starting almond water count
    bandages        = 2,        -- starting bandage count
    food            = 0,        -- food is now instant pickup (not inventory)
    batteries       = 2,        -- starting battery count

    -- XP & LEVELING
    startXpNeed     = 10,       -- xp needed for level 2
    xpScaling       = 1.5,      -- xp requirement multiplier per level

    -- LEVEL-UP REWARDS
    lvlHpBonus      = 10,       -- max HP increase per level
    lvlHpHeal       = 20,       -- HP restored on level up
    lvlStaminaBonus = 5,        -- max stamina increase per level
    lvlSanityRestore= 20,       -- sanity restored on level up

    -- CONSUMABLE EFFECTS
    almondWaterHydra = 40,      -- hydration restored by almond water
    almondWaterSanity= 15,      -- sanity restored by almond water
    almondWaterHp    = 10,      -- hp restored by almond water
    bandageHp        = 30,      -- hp restored by bandage
    foodStamina      = 40,      -- stamina restored by food
    foodSanity       = 10,      -- sanity restored by food
}

-- ═══ V2: KILL STREAK THRESHOLDS ═══
-- At each streak count, the XP multiplier interpolates to the given value.
-- Between thresholds it lerps linearly. Below 5 kills = 1.0x (no bonus).
Player.STREAK_THRESHOLDS = {
    { kills =  5, mult = 1.2 },
    { kills = 10, mult = 1.5 },
    { kills = 20, mult = 2.0 },
    { kills = 50, mult = 3.0 },
}

-- Milestones that trigger a flash on the HUD
Player.STREAK_MILESTONES = {
    [5]=true, [10]=true, [15]=true, [20]=true, [25]=true,
    [30]=true, [40]=true, [50]=true, [75]=true, [100]=true,
}

function Player.new(x, y)
    local self = setmetatable({}, Player)
    local S = Player.STATS
    self.x = x or 2.5
    self.y = y or 2.5
    self.angle = 0
    self.targetAngle = 0
    self.fx = 1
    self.fy = 0

    -- core stats
    self.hp = S.hp
    self.maxHp = S.hp
    self.stamina = S.stamina
    self.maxStamina = S.stamina
    self.staminaRegen = S.staminaRegen
    self.lives = S.lives

    -- survival stats
    self.sanity = S.sanity
    self.maxSanity = S.sanity
    self.sanityDrain = S.sanityDrain
    self.hydration = S.hydration
    self.maxHydration = S.hydration
    self.hydrationDrain = S.hydrationDrain

    -- movement
    self.baseSpeed = S.baseSpeed
    self.speedMult = 1.0
    self.sprintMult = S.sprintMult
    self.sprinting = false
    self.sprintCost = S.sprintCost
    self.moving = false
    self.vx = 0
    self.vy = 0
    self.accel = S.accel
    self.decel = S.decel

    -- combat
    self.dmgMult = S.dmgMult
    self.invulnTime = 0
    self.dmgFlash = 0

    -- noise system
    self.noise = 0
    self.noiseDecay = S.noiseDecay
    self.baseNoise = S.baseNoise
    self.moveNoise = S.moveNoise
    self.sprintNoise = S.sprintNoise

    -- xp/level
    self.xp = 0
    self.level = 1
    self.xpNeed = S.startXpNeed

    -- inventory
    self.almondWater = S.almondWater
    self.bandages = S.bandages
    self.food = S.food
    self.batteries = S.batteries

    -- footstep timer
    self.footstepTimer = 0
    self.footstepInterval = 0.35

    -- ═══ V2: KILL STREAK STATE ═══
    self.currentStreak = 0       -- kills without taking damage
    self.bestRunStreak = 0       -- highest streak this run
    self.streakDisplayTimer = 0  -- >0 means milestone just hit (for HUD flash)

    -- ═══ V3: PERK CHOICE STATE ═══
    self.pendingPerkChoice = false  -- true = game should pause for perk pick
    self.activeRunPerks = {}       -- list of {id, name} chosen this run

    return self
end

function Player:update(dt, map, inputDx, inputDy, isSprinting, isFiring, lightLevel)
    -- sprint
    self.sprinting = isSprinting and self.stamina > 0
    self.moving = false

    -- target speed
    local maxSpeed = self.baseSpeed * self.speedMult
    if self.sprinting then maxSpeed = maxSpeed * self.sprintMult end

    local dx, dy = inputDx, inputDy
    -- normalize diagonal
    local len = math.sqrt(dx*dx + dy*dy)
    if len > 1 then dx, dy = dx / len, dy / len end
    if len > 0.1 then len = math.min(1, len) end

    -- target velocity
    local tvx = dx * maxSpeed * len
    local tvy = dy * maxSpeed * len

    -- smooth acceleration / deceleration
    local hasInput = math.abs(dx) > 0.05 or math.abs(dy) > 0.05
    local smoothRate = hasInput and self.accel or self.decel

    self.vx = self.vx + (tvx - self.vx) * math.min(1, smoothRate * dt)
    self.vy = self.vy + (tvy - self.vy) * math.min(1, smoothRate * dt)

    -- kill tiny drift
    if math.abs(self.vx) < 0.01 then self.vx = 0 end
    if math.abs(self.vy) < 0.01 then self.vy = 0 end

    if math.abs(self.vx) > 0.01 or math.abs(self.vy) > 0.01 then
        self.moving = true
        self:tryMove(self.vx * dt, self.vy * dt, map)
    end

    -- smooth facing angle
    self.fx = math.cos(self.angle)
    self.fy = math.sin(self.angle)

    -- stamina
    if self.sprinting and self.moving then
        self.stamina = self.stamina - self.sprintCost * dt
    else
        self.stamina = math.min(self.maxStamina, self.stamina + self.staminaRegen * dt)
    end
    self.stamina = math.max(0, self.stamina)

    -- ═══ SANITY: drains in dark, recovers in light ═══
    local S = Player.STATS
    local light = lightLevel or 0.05
    local sanityDrainRate = self.sanityDrain * (1.0 + (1.0 - light) * 2.0)
    if self.hydration <= 0 then sanityDrainRate = sanityDrainRate * 2.0 end
    self.sanity = self.sanity - sanityDrainRate * dt

    -- ═══ SANITY REGEN: recovers when in well-lit areas ═══
    local sanityRegenRate = 0
    if light > S.sanityLightMin then
        sanityRegenRate = (light - S.sanityLightMin) * S.sanityRegenMult
    end
    self.sanity = self.sanity + sanityRegenRate * dt
    self.sanity = math.max(0, math.min(self.maxSanity, self.sanity))

    -- hydration drain
    local hydraMod = 1.0
    if self.sprinting then hydraMod = S.hydrationSprint end
    self.hydration = math.max(0, self.hydration - self.hydrationDrain * hydraMod * dt)

    -- noise: movement generates constant sound that enemies track
    local noiseAdd = self.baseNoise * dt
    if self.moving then
        if self.sprinting then
            noiseAdd = noiseAdd + self.sprintNoise * dt
        else
            noiseAdd = noiseAdd + self.moveNoise * dt
        end
    end
    if isFiring then noiseAdd = noiseAdd + 40 * dt end
    self.noise = math.min(100, self.noise + noiseAdd)
    self.noise = math.max(0, self.noise - self.noiseDecay * dt)

    -- footstep timer
    if self.moving then
        self.footstepTimer = self.footstepTimer + dt
        if self.footstepTimer >= self.footstepInterval then
            self.footstepTimer = self.footstepTimer - self.footstepInterval
            -- placeholder: will trigger footstep sound here
        end
    else
        self.footstepTimer = 0
    end

    -- invuln timer
    if self.invulnTime > 0 then self.invulnTime = self.invulnTime - dt end
    if self.dmgFlash > 0 then self.dmgFlash = self.dmgFlash - dt end

    -- ═══ V2: tick down streak display timer ═══
    if self.streakDisplayTimer > 0 then self.streakDisplayTimer = self.streakDisplayTimer - dt end
end

function Player:tryMove(dx, dy, map)
    local r = 0.25 -- body radius

    -- x axis: check leading edge + both corners
    if dx ~= 0 then
        local nx = self.x + dx
        local edgeX = dx > 0 and (nx + r) or (nx - r)
        if not map:isWall(edgeX, self.y - r) and
           not map:isWall(edgeX, self.y) and
           not map:isWall(edgeX, self.y + r) then
            self.x = nx
        else
            self.vx = 0 -- stop velocity on wall hit
        end
    end

    -- y axis: check leading edge + both corners
    if dy ~= 0 then
        local ny = self.y + dy
        local edgeY = dy > 0 and (ny + r) or (ny - r)
        if not map:isWall(self.x - r, edgeY) and
           not map:isWall(self.x, edgeY) and
           not map:isWall(self.x + r, edgeY) then
            self.y = ny
        else
            self.vy = 0 -- stop velocity on wall hit
        end
    end
end

function Player:aimAt(worldX, worldY)
    local dx = worldX - self.x
    local dy = worldY - self.y
    if dx ~= 0 or dy ~= 0 then
        self.targetAngle = math.atan2(dy, dx)
        -- smooth angle interpolation
        local diff = self.targetAngle - self.angle
        while diff > math.pi do diff = diff - math.pi * 2 end
        while diff < -math.pi do diff = diff + math.pi * 2 end
        -- fast but smooth tracking (20 = very responsive, not jerky)
        self.angle = self.angle + diff * math.min(1, 20 * (love.timer.getDelta() or 0.016))
        self.fx = math.cos(self.angle)
        self.fy = math.sin(self.angle)
    end
end

function Player:takeDamage(amount)
    if self.invulnTime > 0 then return false end

    -- V3: apply damage reduction perk (Tough Skin)
    local dmgMult = self.dmgTakenMult or 1.0
    local finalDmg = math.floor(amount * dmgMult)
    self.hp = self.hp - finalDmg

    self.dmgFlash = 0.3
    -- V3: apply invuln duration perk (Thick Skull)
    self.invulnTime = 0.5 * (self.invulnTimeMult or 1.0)

    -- ═══ V2: damage breaks the kill streak ═══
    self.currentStreak = 0

    if self.hp <= 0 then
        self.hp = 0
        return true -- dead
    end
    return false
end

-- ═══ V2: STREAK XP MULTIPLIER ═══
-- Returns XP bonus multiplier based on current streak.
-- Interpolates between thresholds for smooth scaling.
function Player:getStreakMultiplier()
    local streak = self.currentStreak
    if streak < 5 then return 1.0 end

    local thresholds = Player.STREAK_THRESHOLDS
    -- below first threshold
    if streak <= thresholds[1].kills then
        local t = (streak - 0) / thresholds[1].kills
        return 1.0 + (thresholds[1].mult - 1.0) * t
    end
    -- between thresholds
    for i = 2, #thresholds do
        if streak <= thresholds[i].kills then
            local prev = thresholds[i-1]
            local cur = thresholds[i]
            local t = (streak - prev.kills) / (cur.kills - prev.kills)
            return prev.mult + (cur.mult - prev.mult) * t
        end
    end
    -- above max threshold
    return thresholds[#thresholds].mult
end

-- ═══ V2: RECORD A KILL ═══
-- Call this every time an enemy dies. Increments streak,
-- updates best, and triggers milestone display timer.
function Player:recordKill()
    self.currentStreak = self.currentStreak + 1
    if self.currentStreak > self.bestRunStreak then
        self.bestRunStreak = self.currentStreak
    end
    -- check for milestone flash
    if Player.STREAK_MILESTONES[self.currentStreak] then
        self.streakDisplayTimer = 2.0
    end
end

function Player:addXp(amount)
    local S = Player.STATS

    -- ═══ V2: apply streak multiplier to XP ═══
    local mult = self:getStreakMultiplier()
    local boosted = math.floor(amount * mult)
    self.xp = self.xp + boosted

    if self.xp >= self.xpNeed then
        self.xp = self.xp - self.xpNeed
        self.level = self.level + 1
        self.xpNeed = math.floor(self.xpNeed * S.xpScaling)
        self.maxHp = self.maxHp + S.lvlHpBonus
        self.hp = math.min(self.hp + S.lvlHpHeal, self.maxHp)
        self.maxStamina = self.maxStamina + S.lvlStaminaBonus
        self.sanity = math.min(self.maxSanity, self.sanity + S.lvlSanityRestore)
        -- V3: flag perk choice (main.lua will pause and show pick screen)
        self.pendingPerkChoice = (self.level % Player.PERK_EVERY_N_LEVELS == 0)
        return true
    end
    return false
end

function Player:useAlmondWater()
    local S = Player.STATS
    if self.almondWater > 0 then
        self.almondWater = self.almondWater - 1
        self.hydration = math.min(self.maxHydration, self.hydration + S.almondWaterHydra)
        self.sanity = math.min(self.maxSanity, self.sanity + S.almondWaterSanity)
        self.hp = math.min(self.maxHp, self.hp + S.almondWaterHp)
        return true
    end
    return false
end

function Player:useBandage()
    local S = Player.STATS
    if self.bandages > 0 then
        self.bandages = self.bandages - 1
        self.hp = math.min(self.maxHp, self.hp + S.bandageHp)
        return true
    end
    return false
end

function Player:useFood()
    local S = Player.STATS
    if self.food > 0 then
        self.food = self.food - 1
        self.stamina = math.min(self.maxStamina, self.stamina + S.foodStamina)
        self.sanity = math.min(self.maxSanity, self.sanity + S.foodSanity)
        return true
    end
    return false
end

return Player
