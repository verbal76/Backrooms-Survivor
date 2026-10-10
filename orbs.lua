-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║ ORBS.LUA — Chaos Orbs: random buffs and debuffs                     ║
-- ║                                                                     ║
-- ║ ORB COLORS:                                                         ║
-- ║   GREEN orbs = 80% chance buff, 20% chance nerf                     ║
-- ║   YELLOW orbs = 80% chance nerf, 20% chance buff                    ║
-- ║   Both emit light that helps regenerate sanity nearby               ║
-- ║                                                                     ║
-- ║ HOW TO MOD:                                                         ║
-- ║   Change buff/nerf ratio: spawn() math.random() < 0.60 threshold   ║
-- ║   Change effect value ranges in rollEffect() for balance            ║
-- ║   Adjust duration (15 + random * 25 sec) for effect length          ║
-- ║   Add new effects by adding elseif blocks in rollEffect()           ║
-- ║   detectRange = 5 ... tiles before orb starts chasing               ║
-- ║   chaseSpeed ......... 0.9x player speed                           ║
-- ║                                                                     ║
-- ║ EFFECT TARGETS:                                                     ║
-- ║   target=1: Player stats (HP, stamina, speed, damage, sanity, etc)  ║
-- ║   target=2: Enemy mults (HP, speed, damage — reversed good/bad)     ║
-- ║   target=3: Weapon mods (fire rate, proj speed, count, spread, etc) ║
-- ║                                                                     ║
-- ║ ORB STATES: scan (idle) > chase (pursuing) > return (going home)    ║
-- ╚══════════════════════════════════════════════════════════════════════╝

-- orbs.lua
-- Chaos Orbs: scan/chase/return behavior
-- Timed buffs/nerfs that expire

local Orbs = {}
Orbs.__index = Orbs

function Orbs.new()
    local self = setmetatable({}, Orbs)
    self.list = {}
    self.activeEffects = {}
    return self
end

function Orbs:spawn(x, y)
    -- 60% chance buff (green), 40% chance nerf (yellow)
    local isBuff = math.random() < 0.60
    self.list[#self.list+1] = {
        x = x, y = y,
        homeX = x, homeY = y,
        state = "scan",
        detectRange = 3,
        chaseSpeed = 0,
        escapeRange = 50,
        pulseTimer = 0,
        particleAngle = 0,
        isBuff = isBuff,  -- green = buff, yellow = nerf
    }
end

function Orbs:update(dt, px, py, playerBaseSpeed)
    -- despawn orbs too far from player
    local despawnSq = 60 * 60
    local i = #self.list
    while i >= 1 do
        local orb = self.list[i]
        local dx = px - orb.x; local dy = py - orb.y
        if dx*dx + dy*dy > despawnSq then
            table.remove(self.list, i)
        end
        i = i - 1
    end

    for _, orb in ipairs(self.list) do
        orb.pulseTimer = orb.pulseTimer + dt
        orb.particleAngle = orb.particleAngle + dt * 2
        local dx = px - orb.x
        local dy = py - orb.y
        local dist = math.sqrt(dx*dx + dy*dy)
        if orb.state == "scan" then
            if dist < orb.detectRange then
                orb.state = "chase"
                orb.chaseSpeed = playerBaseSpeed * 0.9
            end
        elseif orb.state == "chase" then
            if dist > 0.3 then
                local spd = orb.chaseSpeed * dt
                orb.x = orb.x + (dx / dist) * spd
                orb.y = orb.y + (dy / dist) * spd
            end
            local hx = orb.x - orb.homeX
            local hy = orb.y - orb.homeY
            if hx*hx + hy*hy > orb.escapeRange * orb.escapeRange then
                orb.state = "return"
            end
        elseif orb.state == "return" then
            local hx = orb.homeX - orb.x
            local hy = orb.homeY - orb.y
            local hd = math.sqrt(hx*hx + hy*hy)
            if hd > 0.2 then
                orb.x = orb.x + (hx / hd) * 1.5 * dt
                orb.y = orb.y + (hy / hd) * 1.5 * dt
            else
                orb.x = orb.homeX
                orb.y = orb.homeY
                orb.state = "scan"
            end
        end
    end
end

function Orbs:updateEffects(dt, player, weapons, enemies)
    local i = 1
    while i <= #self.activeEffects do
        local eff = self.activeEffects[i]
        eff.remaining = eff.remaining - dt
        if eff.remaining <= 0 then
            self:revertEffect(eff, player, weapons, enemies)
            table.remove(self.activeEffects, i)
        else
            i = i + 1
        end
    end
end

function Orbs:revertEffect(eff, player, weapons, enemies)
    if eff.target == "player_speed" then
        player.speedMult = player.speedMult / eff.mult
    elseif eff.target == "player_dmg" then
        player.dmgMult = player.dmgMult / eff.mult
    elseif eff.target == "enemy_hp" then
        enemies.hpMult = enemies.hpMult / eff.mult
    elseif eff.target == "enemy_spd" then
        enemies.spdMult = enemies.spdMult / eff.mult
    elseif eff.target == "enemy_dmg" then
        enemies.dmgMult = enemies.dmgMult / eff.mult
    elseif eff.target == "wep_rate" then
        weapons.rateMod = weapons.rateMod - eff.delta
    elseif eff.target == "wep_speed" then
        weapons.speedMod = weapons.speedMod - eff.delta
    elseif eff.target == "wep_count" then
        weapons.countMod = weapons.countMod - eff.delta
    elseif eff.target == "wep_dmg" then
        weapons.dmgMod = weapons.dmgMod - eff.delta
    elseif eff.target == "wep_spread" then
        weapons.spreadMod = weapons.spreadMod - eff.delta
    elseif eff.target == "bomb_radius" then
        if eff.bomb then eff.bomb.radiusMult = eff.bomb.radiusMult / eff.mult end
    end
end

function Orbs:checkPickup(px, py)
    for i = #self.list, 1, -1 do
        local orb = self.list[i]
        local dx = px - orb.x
        local dy = py - orb.y
        if dx*dx + dy*dy < 0.4 then
            local isBuff = orb.isBuff
            table.remove(self.list, i)
            return true, isBuff
        end
    end
    return false, nil
end

function Orbs.rollEffect(player, weapons, enemies, activeEffects, bomb, isBuff)
    -- Green orbs (isBuff=true) = 80% buff, 20% nerf
    -- Yellow orbs (isBuff=false) = 80% nerf, 20% buff
    -- nil/missing isBuff = 50/50 (backwards compatible)
    local wantGood
    if isBuff == nil then
        wantGood = math.random() < 0.5
    else
        wantGood = (math.random() < 0.80) == isBuff
    end

    local target = math.random(1, 3)
    local text = ""
    local color = {1, 1, 1}
    local isGood = wantGood
    local duration = 15 + math.random() * 25

    -- helper: pick a positive or negative value based on wantGood
    local function pickVal(goodMin, goodMax, badMin, badMax)
        if wantGood then return math.random(goodMin, goodMax)
        else return math.random(badMin, badMax) end
    end
    if target == 1 then
        -- PLAYER STATS
        local stat = math.random(1, 7)
        if stat == 1 then
            local val = pickVal(10, 50, -30, -5)
            player.hp = math.max(1, math.min(player.hp + val, player.maxHp + 50))
            if val > 0 then player.maxHp = player.maxHp + math.floor(val * 0.2) end
            text = val >= 0 and "HP +"..val or "HP "..val
            color = val >= 0 and {0.3, 1, 0.3} or {1, 0.3, 0.3}
        elseif stat == 2 then
            local val = pickVal(10, 40, -20, -5)
            player.stamina = math.max(1, math.min(player.stamina + val, player.maxStamina + 40))
            if val > 0 then player.maxStamina = player.maxStamina + math.floor(val * 0.2) end
            text = val >= 0 and "Stamina +"..val or "Stamina "..val
            color = val >= 0 and {0.3, 0.7, 1} or {1, 0.3, 0.3}
        elseif stat == 3 then
            local val = wantGood and (1.1 + math.random() * 0.6) or (0.5 + math.random() * 0.3)
            player.speedMult = math.max(0.3, math.min(player.speedMult * val, 3.0))
            local pct = math.floor(val * 100) - 100
            text = (pct >= 0 and "Speed +"..pct.."%" or "Speed "..pct.."%").."  ("..math.floor(duration).."s)"
            color = pct >= 0 and {0.3, 1, 0.3} or {1, 0.3, 0.3}
            isGood = pct >= 0
            activeEffects[#activeEffects+1] = {target="player_speed", mult=val, remaining=duration, text="SPD", isGood=isGood}
        elseif stat == 4 then
            local val = wantGood and (1.2 + math.random() * 0.8) or (0.5 + math.random() * 0.3)
            player.dmgMult = math.max(0.2, math.min(player.dmgMult * val, 4.0))
            local pct = math.floor(val * 100) - 100
            text = (pct >= 0 and "Your Dmg +"..pct.."%" or "Your Dmg "..pct.."%").."  ("..math.floor(duration).."s)"
            color = pct >= 0 and {0.3, 1, 0.3} or {1, 0.3, 0.3}
            isGood = pct >= 0
            activeEffects[#activeEffects+1] = {target="player_dmg", mult=val, remaining=duration, text="DMG", isGood=isGood}
        elseif stat == 5 then
            local val = pickVal(10, 40, -30, -5)
            player.hp = math.max(1, math.min(player.hp + val, player.maxHp))
            text = val >= 0 and "HP +"..val or "HP "..val
            color = val >= 0 and {0.3, 1, 0.3} or {1, 0.3, 0.3}
        elseif stat == 6 then
            local val = pickVal(25, 60, -20, -5)
            player.sanity = math.max(0, math.min(player.sanity + val, player.maxSanity))
            text = val >= 0 and "Sanity +"..val or "Sanity "..val
            color = val >= 0 and {0.6, 0.3, 1} or {1, 0.3, 0.3}
        else
            local val = pickVal(10, 35, -25, -5)
            player.hydration = math.max(0, math.min(player.hydration + val, player.maxHydration))
            text = val >= 0 and "Hydration +"..val or "Hydration "..val
            color = val >= 0 and {0.3, 0.7, 1} or {1, 0.3, 0.3}
        end
    elseif target == 2 then
        -- ENEMY STATS (reversed: good for player = bad for enemies)
        local stat = math.random(1, 3)
        if stat == 1 then
            local val = wantGood and (0.4 + math.random() * 0.3) or (1.3 + math.random() * 0.9)
            enemies.hpMult = math.max(0.3, math.min(enemies.hpMult * val, 5.0))
            local pct = math.floor(val * 100) - 100
            text = (pct >= 0 and "Foe HP +"..pct.."%" or "Foe HP "..pct.."%").."  ("..math.floor(duration).."s)"
            color = pct >= 0 and {1, 0.3, 0.3} or {0.3, 1, 0.3}
            isGood = pct < 0
            activeEffects[#activeEffects+1] = {target="enemy_hp", mult=val, remaining=duration, text="FoeHP", isGood=isGood}
        elseif stat == 2 then
            local val = wantGood and (0.5 + math.random() * 0.3) or (1.2 + math.random() * 0.7)
            enemies.spdMult = math.max(0.3, math.min(enemies.spdMult * val, 3.0))
            local pct = math.floor(val * 100) - 100
            text = (pct >= 0 and "Foe Speed +"..pct.."%" or "Foe Speed "..pct.."%").."  ("..math.floor(duration).."s)"
            color = pct >= 0 and {1, 0.3, 0.3} or {0.3, 1, 0.3}
            isGood = pct < 0
            activeEffects[#activeEffects+1] = {target="enemy_spd", mult=val, remaining=duration, text="FoeSpd", isGood=isGood}
        else
            local val = wantGood and (0.4 + math.random() * 0.3) or (1.2 + math.random() * 0.8)
            enemies.dmgMult = math.max(0.2, math.min(enemies.dmgMult * val, 4.0))
            local pct = math.floor(val * 100) - 100
            text = (pct >= 0 and "Foe Dmg +"..pct.."%" or "Foe Dmg "..pct.."%").."  ("..math.floor(duration).."s)"
            color = pct >= 0 and {1, 0.3, 0.3} or {0.3, 1, 0.3}
            isGood = pct < 0
            activeEffects[#activeEffects+1] = {target="enemy_dmg", mult=val, remaining=duration, text="FoeDmg", isGood=isGood}
        end
    else
        -- WEAPON MODS
        local stat = math.random(1, 6)
        if stat == 1 then
            local val = wantGood and (math.random(-3, -1) * 0.05) or (math.random(1, 4) * 0.05)
            weapons.rateMod = math.max(0.3, math.min(weapons.rateMod + val, 2.0))
            text = (val <= 0 and "Fire Rate ++" or "Fire Rate --").."  ("..math.floor(duration).."s)"
            color = val <= 0 and {0.3, 1, 0.3} or {1, 0.3, 0.3}
            isGood = val <= 0
            activeEffects[#activeEffects+1] = {target="wep_rate", delta=val, remaining=duration, text="FRate", isGood=isGood}
        elseif stat == 2 then
            local val = wantGood and (0.1 + math.random() * 0.5) or (-0.2 - math.random() * 0.3)
            weapons.speedMod = math.max(0.5, math.min(weapons.speedMod + val, 2.0))
            text = (val >= 0 and "Proj Speed ++" or "Proj Speed --").."  ("..math.floor(duration).."s)"
            color = val >= 0 and {0.3, 1, 0.3} or {1, 0.3, 0.3}
            isGood = val >= 0
            activeEffects[#activeEffects+1] = {target="wep_speed", delta=val, remaining=duration, text="PSpd", isGood=isGood}
        elseif stat == 3 then
            local val = wantGood and math.random(1, 3) or math.random(-1, -1)
            weapons.countMod = math.max(-2, math.min(weapons.countMod + val, 6))
            text = (val >= 0 and "Projectiles +"..val or "Projectiles "..val).."  ("..math.floor(duration).."s)"
            color = val >= 0 and {0.3, 1, 0.3} or {1, 0.3, 0.3}
            isGood = val >= 0
            activeEffects[#activeEffects+1] = {target="wep_count", delta=val, remaining=duration, text="Proj#", isGood=isGood}
        elseif stat == 4 then
            local val = wantGood and math.random(1, 5) or math.random(-3, -1)
            weapons.dmgMod = math.max(-5, math.min(weapons.dmgMod + val, 15))
            text = (val >= 0 and "Wep Dmg +"..val or "Wep Dmg "..val).."  ("..math.floor(duration).."s)"
            color = val >= 0 and {0.3, 1, 0.3} or {1, 0.3, 0.3}
            isGood = val >= 0
            activeEffects[#activeEffects+1] = {target="wep_dmg", delta=val, remaining=duration, text="WDmg", isGood=isGood}
        elseif stat == 5 then
            local val = wantGood and (-0.1 - math.random() * 0.4) or (0.1 + math.random() * 0.7)
            weapons.spreadMod = math.max(0.2, math.min(weapons.spreadMod + val, 3.0))
            text = (val <= 0 and "Accuracy ++" or "Accuracy --").."  ("..math.floor(duration).."s)"
            color = val <= 0 and {0.3, 1, 0.3} or {1, 0.3, 0.3}
            isGood = val <= 0
            activeEffects[#activeEffects+1] = {target="wep_spread", delta=val, remaining=duration, text="Acc", isGood=isGood}
        else
            -- bomb radius
            if bomb then
                local val = wantGood and (1.2 + math.random() * 0.8) or (0.5 + math.random() * 0.3)
                bomb.radiusMult = math.max(0.3, math.min(bomb.radiusMult * val, 4.0))
                local pct = math.floor(val * 100) - 100
                text = (pct >= 0 and "Bomb Range +"..pct.."%" or "Bomb Range "..pct.."%").."  ("..math.floor(duration).."s)"
                color = pct >= 0 and {1, 0.6, 0.2} or {1, 0.3, 0.3}
                isGood = pct >= 0
                activeEffects[#activeEffects+1] = {target="bomb_radius", mult=val, bomb=bomb, remaining=duration, text="Bomb", isGood=isGood}
            end
        end
    end
    return {text = text, color = color, isGood = isGood}
end

return Orbs
