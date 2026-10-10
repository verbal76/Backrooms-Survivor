-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║ BOMB.LUA — Area-of-effect explosion centered on player             ║
-- ║                                                                     ║
-- ║ HOW TO MOD:                                                         ║
-- ║   baseRadius = 3.0 ... explosion range in tiles                     ║
-- ║   damage = 50 ........ base damage at center (falls off w/ distance)║
-- ║   knockback = 8.0 .... push force on surviving enemies              ║
-- ║   cooldownTime = 1.0 . seconds between uses                        ║
-- ║   Bomb count caps set in items.lua based on difficulty              ║
-- ║                                                                     ║
-- ║ VISUAL: expanding shockwave ring + bright core + sparks             ║
-- ╚══════════════════════════════════════════════════════════════════════╝

-- bomb.lua
-- AOE bomb: centered on player, 10x player radius
-- Cannot penetrate walls, kills lesser enemies, knocks back larger ones

local Bomb = {}
Bomb.__index = Bomb

function Bomb.new()
    local self = setmetatable({}, Bomb)
    self.count = 1          -- start with 1
    self.baseRadius = 3.0   -- tiles (10x player 0.3 radius)
    self.radiusMult = 1.0   -- modifiable by chaos orbs
    self.damage = 50
    self.knockback = 8.0    -- tiles/sec impulse
    self.cooldown = 0
    self.cooldownTime = 1.0 -- seconds between uses
    -- visual
    self.blastTimer = 0
    self.blastX = 0
    self.blastY = 0
    self.blastRadius = 0
    self.blasting = false
    return self
end

function Bomb:getRadius()
    return self.baseRadius * self.radiusMult
end

function Bomb:canUse()
    return self.count > 0 and self.cooldown <= 0
end

function Bomb:use(px, py, map, enemies)
    if not self:canUse() then return {} end

    self.count = self.count - 1
    self.cooldown = self.cooldownTime
    self.blasting = true
    self.blastTimer = 0.6
    self.blastX = px
    self.blastY = py
    self.blastRadius = self:getRadius()

    local radius = self:getRadius()
    local kills = {}
    local knockbacks = {}

    for i = #enemies.list, 1, -1 do
        local e = enemies.list[i]
        local dx = e.x - px
        local dy = e.y - py
        local dist = math.sqrt(dx*dx + dy*dy)

        if dist < radius then
            -- check wall obstruction (simple raycast)
            if not self:isBlockedByWall(px, py, e.x, e.y, map) then
                local falloff = 1.0 - (dist / radius)
                local actualDmg = math.floor(self.damage * falloff)

                e.hp = e.hp - actualDmg
                e.hitFlash = 0.3

                if e.hp <= 0 then
                    -- kill
                    local kd = {
                        x = e.x, y = e.y,
                        xp = e.xp,
                        dropChance = e.dropChance,
                        name = e.name
                    }
                    table.remove(enemies.list, i)
                    kills[#kills+1] = kd
                else
                    -- knockback (push away from center)
                    if dist > 0.1 then
                        local kbStrength = self.knockback * falloff
                        local nx = dx / dist
                        local ny = dy / dist
                        -- apply immediate position offset
                        local newX = e.x + nx * kbStrength * 0.3
                        local newY = e.y + ny * kbStrength * 0.3
                        -- wall check for knockback destination
                        if not map:isWall(newX, e.y) then e.x = newX end
                        if not map:isWall(e.x, newY) then e.y = newY end
                    end
                end
            end
        end
    end

    return kills
end

function Bomb:isBlockedByWall(x1, y1, x2, y2, map)
    -- simple step raycast
    local dx = x2 - x1
    local dy = y2 - y1
    local dist = math.sqrt(dx*dx + dy*dy)
    local steps = math.ceil(dist * 3)
    if steps < 1 then return false end

    for i = 1, steps do
        local t = i / steps
        local cx = x1 + dx * t
        local cy = y1 + dy * t
        if map:isWall(cx, cy) then
            return true
        end
    end
    return false
end

function Bomb:update(dt)
    if self.cooldown > 0 then
        self.cooldown = self.cooldown - dt
    end
    if self.blasting then
        self.blastTimer = self.blastTimer - dt
        if self.blastTimer <= 0 then
            self.blasting = false
        end
    end
end

function Bomb:draw(tileSize, camX, camY)
    if not self.blasting then return end

    local sx = (self.blastX - camX) * tileSize
    local sy = (self.blastY - camY) * tileSize
    local maxR = self.blastRadius * tileSize
    local progress = 1.0 - (self.blastTimer / 0.6)

    -- expanding shockwave
    local waveR = maxR * math.min(1, progress * 1.5)
    local alpha = math.max(0, 1.0 - progress)

    -- outer ring
    love.graphics.setColor(1, 0.6, 0.2, alpha * 0.3)
    love.graphics.circle("fill", sx, sy, waveR)

    -- bright core
    local coreR = waveR * 0.3 * (1 - progress)
    love.graphics.setColor(1, 0.95, 0.8, alpha * 0.8)
    love.graphics.circle("fill", sx, sy, coreR)

    -- shockwave ring
    love.graphics.setColor(1, 0.5, 0.1, alpha * 0.7)
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", sx, sy, waveR)
    love.graphics.setLineWidth(1)

    -- sparks
    if progress < 0.5 then
        for i = 1, 12 do
            local sa = i * math.pi * 2 / 12 + progress * 3
            local sr = waveR * (0.5 + math.random() * 0.5)
            local spx = sx + math.cos(sa) * sr
            local spy = sy + math.sin(sa) * sr
            love.graphics.setColor(1, 0.8, 0.3, alpha)
            love.graphics.circle("fill", spx, spy, 2)
        end
    end
end

return Bomb
