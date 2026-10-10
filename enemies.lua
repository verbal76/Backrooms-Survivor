-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║ ENEMIES.LUA — Entity definitions, AI behavior, spawning            ║
-- ║                                                                     ║
-- ║ HOW TO MOD:                                                         ║
-- ║   Edit Enemies.types table below to change enemy stats.             ║
-- ║   Add new enemy types by copying a row and changing values.         ║
-- ║   Adjust spawn weights in Enemies:spawn() for frequency.            ║
-- ║   Change alert thresholds in Enemies:update() for aggression.       ║
-- ║                                                                     ║
-- ║ SECTIONS:                                                           ║
-- ║   ENEMY TYPE TABLE ....... all 5 enemy stat blocks                  ║
-- ║   CONSTRUCTOR ............ creates enemy manager                    ║
-- ║   LINE OF SIGHT .......... wall raycast for visibility              ║
-- ║   WALL MOVEMENT .......... collision + wall sliding                 ║
-- ║   SPAWNING ............... where/when enemies appear                ║
-- ║   AI UPDATE .............. hunt/search/wander/flee state machine    ║
-- ║   COLLISION .............. contact damage + bounce-back             ║
-- ║   MELEE CHECK ............ player swing hit detection               ║
-- ╚══════════════════════════════════════════════════════════════════════╝

-- enemies.lua
-- Backrooms entities with sound tracking and wall sliding

local Enemies = {}
Enemies.__index = Enemies

-- ═══ SPRITE SPACING TEST (DEV MODE) ═══
-- When enabled, the normal enemy spawner is disabled and a single follower
-- enemy ("spacing test character") is spawned for animation/cutter testing.
Enemies.SPACING_TEST_ENABLED = true
Enemies.SPACING_TEST_FILE = "enemies/spacing test character.png"
Enemies.SPACING_TEST_COLS = 8
Enemies.SPACING_TEST_ROWS = 3
Enemies.SPACING_TEST_FPS  = 10

local function _cardinalRowFromVec(vx, vy)
    -- rows: 1=down, 2=side (left/right share row; flip horizontally for left), 3=up
    if math.abs(vy) > math.abs(vx) then
        return (vy < 0) and 3 or 1
    else
        return 2  -- left and right share row 2; caller flips sprite for left
    end
end

local function _isFacingLeft(vx, vy)
    return math.abs(vx) > math.abs(vy) and vx < 0
end

local function _clamp(v, a, b)
    if v < a then return a end
    if v > b then return b end
    return v
end


-- ═══ ENEMY TYPE TABLE ═══
-- Fields: name, hp, speed, dmg, radius (body size for collision + drawing scale),
-- color {r,g,b}, xp (kill reward), dropChance (0-1), noiseAttract (hearing range multiplier),
-- lightFear (0=ignores light, 1=flees bright areas), scale (visual size multiplier, 1.0 = normal)
-- To ADD a new enemy: copy any row, change values, give unique name
-- Drawing is auto-handled by radius (bigger radius = bigger on screen)
Enemies.types = {
    {name="hound",        hp=15,  speed=3.2, dmg=12, radius=0.35, scale=.4, color={0.85,0.15,0.1},  xp=2, dropChance=0.12, noiseAttract=2.5, lightFear=0.6},  -- RED: fast, weak
    {name="crawler",      hp=50,  speed=0.9, dmg=20, radius=0.5,  scale=.4, color={0.2,0.7,0.15},   xp=4, dropChance=0.2,  noiseAttract=1.5, lightFear=0.2},  -- GREEN: slow tank
    {name="wretch",       hp=10,   speed=4.0, dmg=5,  radius=0.25, scale=.65, color={0.95,0.85,0.2},  xp=1, dropChance=0.08, noiseAttract=2.0, lightFear=0.6},  -- YELLOW: very fast, fragile
    {name="shade",        hp=20,  speed=2.0, dmg=18, radius=0.3,  scale=0.7, color={0.35,0.15,0.55}, xp=3, dropChance=0.15, noiseAttract=1.0, lightFear=1.0},  -- PURPLE: medium, fears light
    {name="skin stealer", hp=80,  speed=1.5, dmg=35, radius=0.55, scale=1.25, color={0.9,0.4,0.15},   xp=8, dropChance=0.3,  noiseAttract=1.5, lightFear=0.0},  -- ORANGE: slow boss, heavy hits
}

function Enemies.new()
    local self = setmetatable({}, Enemies)
    self.list = {}
    self.spawnTimer = 0
    self.spawnRate = 3.0
    self.maxEnemies = 32  -- <<<< starting cap, main.lua ramps via min(80, 30 + day*2)
    self.wave = 1
    self.hpMult = 1.0
    self.spdMult = 1.0
    self.dmgMult = 1.0
    self._map = nil
    self._nextUID = 1

    -- spacing test state
    self.testMode = false
    self._spacingSheet = nil
    self._spacingBuddyUID = nil
    return self
end

function Enemies:assignUID()
    local uid = self._nextUID
    self._nextUID = self._nextUID + 1
    return uid
end

function Enemies:hasLOS(x1, y1, x2, y2, map)
    local dx = x2 - x1
    local dy = y2 - y1
    local dist = math.sqrt(dx*dx + dy*dy)
    local steps = math.ceil(dist * 2.5)
    if steps < 1 then return true end
    for i = 1, steps do
        local t = i / steps
        if map:isWall(x1 + dx * t, y1 + dy * t) then return false end
    end
    return true
end

-- wall-aware movement: try full move, then each axis, with body radius
function Enemies:tryMoveEnemy(e, mx, my, map)
    local r = e.radius
    e.slidePref = e.slidePref or 1

    local function canMove(dx, dy)
        if dx ~= 0 then
            local nx = e.x + dx
            local edgeX = dx > 0 and (nx + r) or (nx - r)
            if map:isWall(edgeX, e.y - r) or map:isWall(edgeX, e.y) or map:isWall(edgeX, e.y + r) then
                return false
            end
        end
        if dy ~= 0 then
            local ny = e.y + dy
            local edgeY = dy > 0 and (ny + r) or (ny - r)
            if map:isWall(e.x - r, edgeY) or map:isWall(e.x, edgeY) or map:isWall(e.x + r, edgeY) then
                return false
            end
        end
        return true
    end

    local function applyMove(dx, dy)
        if dx ~= 0 then e.x = e.x + dx end
        if dy ~= 0 then e.y = e.y + dy end
    end

    -- Fast path: intended move is clear
    if mx ~= 0 or my ~= 0 then
        if canMove(mx, my) then
            applyMove(mx, my)
            return
        end
    end

    -- Axis attempts (helps with shallow collisions)
    local moved = false
    if mx ~= 0 and canMove(mx, 0) then applyMove(mx, 0); moved = true end
    if my ~= 0 and canMove(0, my) then applyMove(0, my); moved = true end
    if moved then return end

    -- Deterministic wall-slide: try perpendicular to the blocked direction (no randomness)
    local sp = math.sqrt(mx*mx + my*my)
    if sp < 0.0001 then return end

    local ax, ay = mx / sp, my / sp
    local perp1x, perp1y = -ay, ax
    local perp2x, perp2y = ay, -ax
    local slideStep = sp * 0.65

    local sx, sy = (e.slidePref == 1 and perp1x or perp2x) * slideStep, (e.slidePref == 1 and perp1y or perp2y) * slideStep
    if canMove(sx, sy) then applyMove(sx, sy); return end
    sx, sy = (e.slidePref == 1 and perp2x or perp1x) * slideStep, (e.slidePref == 1 and perp2y or perp1y) * slideStep
    if canMove(sx, sy) then applyMove(sx, sy); return end

    -- Local steering (cheap "micro-pathfinding"):
    -- rotate the desired vector in small steps until we find a clear direction.
    local ang = math.atan2(ay, ax)
    local offsets = {0, 0.35, -0.35, 0.8, -0.8, 1.25, -1.25, math.pi/2, -math.pi/2, math.pi}
    for _, off in ipairs(offsets) do
        local a = ang + off * e.slidePref
        local dx = math.cos(a) * sp
        local dy = math.sin(a) * sp
        if canMove(dx, dy) then
            applyMove(dx, dy)
            return
        end
    end
end

-- ═══ GRID SPRITESHEET HELPERS (used by spacing test) ═══
function Enemies:_loadGridSheet(path, cols, rows, fps)
    if self._spacingSheet and self._spacingSheet.path == path then
        return self._spacingSheet
    end
    if not love or not love.filesystem or not love.graphics then
        return nil
    end
    if not love.filesystem.getInfo(path) then
        return nil
    end

    local img = love.graphics.newImage(path)
    img:setFilter('nearest', 'nearest')
    local iw, ih = img:getWidth(), img:getHeight()
    cols = cols or 8
    rows = rows or 4
    local fw = math.floor(iw / cols)
    local fh = math.floor(ih / rows)

    local quads = {}
    for r = 0, rows - 1 do
        quads[r + 1] = {}
        for c = 0, cols - 1 do
            quads[r + 1][c + 1] = love.graphics.newQuad(c * fw, r * fh, fw, fh, iw, ih)
        end
    end

    self._spacingSheet = {
        path = path,
        img = img,
        quads = quads,
        cols = cols,
        rows = rows,
        frameW = fw,
        frameH = fh,
        fps = fps or 10,
    }
    return self._spacingSheet
end

function Enemies:enableSpacingTest(map, player)
    -- call from main.lua after player is created
    self.testMode = true
    self.list = {}
    self.spawnTimer = 0
    self._map = map
    -- load sheet and spawn buddy
    local sheet = self:_loadGridSheet(Enemies.SPACING_TEST_FILE, Enemies.SPACING_TEST_COLS, Enemies.SPACING_TEST_ROWS, Enemies.SPACING_TEST_FPS)
    if sheet and player then
        self:spawnSpacingTestBuddy(player.x, player.y, player.fx or math.cos(player.angle or 0), player.fy or math.sin(player.angle or 0), map)
    end
end

function Enemies:spawnSpacingTestBuddy(px, py, fx, fy, map)
    local sheet = self:_loadGridSheet(Enemies.SPACING_TEST_FILE, Enemies.SPACING_TEST_COLS, Enemies.SPACING_TEST_ROWS, Enemies.SPACING_TEST_FPS)
    if not sheet then return nil end

    fx, fy = fx or 1, fy or 0
    local bx = px - fx * 2
    local by = py - fy * 2
    if map and map.isWall and map:isWall(bx, by) then
        bx, by = px, py
    end

    local uid = self:assignUID()
    self._spacingBuddyUID = uid

    local e = {
        x = bx, y = by,
        hp = 999999, maxHp = 999999,
        speed = 4.5,
        dmg = 0,
        radius = 0.35,
        color = {1, 1, 1},
        xp = 0, dropChance = 0,
        noiseAttract = 0, lightFear = 0,
        hitFlash = 0, typeIdx = 0,
        name = 'spacing test character',
        scale = 1.0,
        state = 'buddy',
        targetX = bx, targetY = by,
        soundUID = uid,
        invulnerable = true,
        noCollide = true,
        sheet = sheet,
        animRow = 1,
        animCol = 1,
        animTimer = 0,
    }
    self.list[#self.list + 1] = e
    return e
end

-- ═══ SPAWNING ═══
-- Creates enemies around player. Type weights change by wave (day):
--   Wave 1-4:  mostly hounds + wretches (learning phase)
--   Wave 5-10: adds crawlers + shades, rare skin stealers
--   Wave 11-20: balanced mix, skin stealers more common
--   Wave 21+:  all types equally likely
-- Enemy HP/speed/dmg scale up each wave via multipliers (baby-stepped for 30-day runs)
function Enemies:spawn(px, py, map, wave, soundSystem)
    if self.testMode then return  end
    if #self.list >= self.maxEnemies then return end
    for tries = 1, 30 do
        local a = math.random() * math.pi * 2
        local dist = 10 + math.random() * 8
        local ex = px + math.cos(a) * dist
        local ey = py + math.sin(a) * dist
        -- pick enemy type by wave
        local typeIdx
        local roll = math.random()
        if wave < 5 then
            -- early game: hounds + wretches, rare shade
            if roll < 0.40 then typeIdx = 1
            elseif roll < 0.80 then typeIdx = 3
            else typeIdx = 4 end
        elseif wave < 11 then
            -- mid-early: crawlers + shades join, rare skin stealer
            if roll < 0.25 then typeIdx = 1
            elseif roll < 0.40 then typeIdx = 2
            elseif roll < 0.65 then typeIdx = 3
            elseif roll < 0.85 then typeIdx = 4
            else typeIdx = 5 end
        elseif wave < 21 then
            -- mid-late: balanced, skin stealers more common
            if roll < 0.20 then typeIdx = 1
            elseif roll < 0.35 then typeIdx = 2
            elseif roll < 0.50 then typeIdx = 3
            elseif roll < 0.70 then typeIdx = 4
            else typeIdx = 5 end
        else
            -- late game: all equal
            typeIdx = math.random(1, #Enemies.types)
        end

        local t = Enemies.types[typeIdx]
        local r = (t.radius or 0.4) + 0.12

        local function clearAt(x, y, rr)
            return not (
                map:isWall(x, y) or
                map:isWall(x + rr, y) or map:isWall(x - rr, y) or
                map:isWall(x, y + rr) or map:isWall(x, y - rr) or
                map:isWall(x + rr, y + rr) or map:isWall(x - rr, y + rr) or
                map:isWall(x + rr, y - rr) or map:isWall(x - rr, y - rr)
            )
        end

        if clearAt(ex, ey, r) then
            local scaledHp = math.floor(t.hp * (1 + wave * 0.05) * self.hpMult)    -- <<<< HP scale per day (was 0.15)
            local uid = self:assignUID()
            local e = {
                x = ex, y = ey, hp = scaledHp, maxHp = scaledHp,
                speed = t.speed * (1 + wave * 0.01) * self.spdMult,                -- <<<< speed scale per day (was 0.03)
                dmg = math.floor(t.dmg * (1 + wave * 0.035) * self.dmgMult),       -- <<<< dmg scale per day (was 0.10)
                radius = t.radius,
                color = {t.color[1], t.color[2], t.color[3]},
                xp = t.xp, dropChance = t.dropChance,
                noiseAttract = t.noiseAttract, lightFear = t.lightFear,
                hitFlash = 0, typeIdx = typeIdx, name = t.name,
                scale = t.scale or 1.0,
                state = "wander",
                targetX = ex, targetY = ey,
                lastSeenX = nil, lastSeenY = nil, lastSeenTimer = 0,
                lastHeardX = nil, lastHeardY = nil, lastHeardTimer = 999,
                wanderTimer = 0, alertLevel = 0,
                soundUID = uid,
                stuckTimer = 0, prevX = ex, prevY = ey,
                slidePref = (math.random() > 0.5) and 1 or -1,
                losTimer = math.random() * 0.2, cachedLOS = false,
            }
            self.list[#self.list+1] = e
            -- assign sound immediately
            if soundSystem then soundSystem:assignToEnemy(uid) end
            return
        end
    end
end

-- ═══ AI UPDATE (runs every frame for every enemy) ═══
-- Alert levels: 0=calm, 10+=curious, 35+=hunting
-- Once alert passes 35, it NEVER drops below 40 (permanent tracking)
-- States: wander (random patrol), search (moving to last heard/seen position),
--   hunt (direct chase), flee (running from light, shade only)
-- Anti-stuck: if enemy hasn't moved in 1.5 sec while hunting, random juke
function Enemies:update(dt, px, py, playerNoise, map, playerMoving, pfx, pfy, pmovX, pmovY)
    self._map = map
    -- despawn enemies too far from player (frees cap for nearby spawns)
    local despawnDist = 35  -- tiles — well outside view range
    local i = #self.list
    while i >= 1 do
        local e = self.list[i]
        local dx = px - e.x; local dy = py - e.y
        if dx*dx + dy*dy > despawnDist * despawnDist then
            table.remove(self.list, i)
        end
        i = i - 1
    end

    for _, e in ipairs(self.list) do
        -- spacing test buddy: follow 3 tiles behind player's MOVEMENT direction, never closer than 2 tiles
        if self.testMode and e.state == 'buddy' then
            local mdx = pmovX or 0
            local mdy = pmovY or 0
            local mlen = math.sqrt(mdx*mdx + mdy*mdy)

            -- only update the stored follow direction when the player is actually moving
            if mlen > 0.1 then
                e._lastMoveDirX = mdx / mlen
                e._lastMoveDirY = mdy / mlen
            end

            -- use stored direction (so buddy holds position when player stops)
            local dirX = e._lastMoveDirX or 0
            local dirY = e._lastMoveDirY or 1

            -- target = 3 tiles behind player in their movement direction
            local tx = px - dirX * 3
            local ty = py - dirY * 3
            if map and map.isWall and map:isWall(tx, ty) then
                tx, ty = px, py
            end

            -- hard minimum: never approach closer than 2 tiles to player
            local distToPlayer = math.sqrt((e.x - px)^2 + (e.y - py)^2)
            if distToPlayer < 2.0 then
                -- push buddy away from player
                local awayX = e.x - px
                local awayY = e.y - py
                local awayLen = math.sqrt(awayX*awayX + awayY*awayY)
                if awayLen > 0.001 then
                    e.x = px + (awayX / awayLen) * 2.1
                    e.y = py + (awayY / awayLen) * 2.1
                else
                    e.x = px + dirX * -2.1
                    e.y = py + dirY * -2.1
                end
                goto continue_enemy
            end

            local bdx = tx - e.x
            local bdy = ty - e.y
            local bd2 = bdx*bdx + bdy*bdy
            -- only move if more than 0.5 tiles from target
            local moving = bd2 > 0.25

            -- animate using buddy's own movement direction
            if moving then
                local bd = math.sqrt(bd2)
                local mvx = bdx / bd
                local mvy = bdy / bd
                local row = _cardinalRowFromVec(mvx, mvy)
                e.animRow = _clamp(row, 1, (e.sheet and e.sheet.rows) or 3)
                e.facingLeft = _isFacingLeft(mvx, mvy)
                e.animTimer = (e.animTimer or 0) + dt
                local fps = (e.sheet and e.sheet.fps) or Enemies.SPACING_TEST_FPS
                local step = 1 / math.max(1, fps)
                while e.animTimer >= step do
                    e.animTimer = e.animTimer - step
                    e.animCol = ((e.animCol or 1) % ((e.sheet and e.sheet.cols) or 8)) + 1
                end
                -- move toward target
                local spd = (e.speed or 4.5) * dt
                local mx = (bdx / bd) * spd
                local my = (bdy / bd) * spd
                self:tryMoveEnemy(e, mx, my, map)
            else
                e.animCol = 1
                e.animTimer = 0
                e.animRow = _clamp(e.animRow or 1, 1, (e.sheet and e.sheet.rows) or 3)
            end

            -- buddy doesn't run normal AI
            goto continue_enemy
        end
        local dx = px - e.x
        local dy = py - e.y
        local dist = math.sqrt(dx*dx + dy*dy)
        local light = map:getLightLevel(e.x, e.y)

        -- throttle LOS checks (every 0.08s per enemy)
        e.losTimer = (e.losTimer or 0) + dt
        if e.losTimer >= 0.08 or e.cachedLOS == nil then
            e.cachedLOS = dist < 14 and self:hasLOS(e.x, e.y, px, py, map)
            e.losTimer = 0
        end
        local canSeePlayer = e.cachedLOS

        -- noise tracking (hearing)
        local noiseReach = playerNoise * e.noiseAttract * 0.7
        if dist < noiseReach and playerMoving then
            e.alertLevel = math.min(100, e.alertLevel + (noiseReach - dist) * dt * 15)
            e.lastHeardX = px
            e.lastHeardY = py
            e.lastHeardTimer = 0
        else
            e.lastHeardTimer = (e.lastHeardTimer or 0) + dt
        end

        -- visual tracking (wider range)
        if canSeePlayer then
            if dist < 10 then
                e.alertLevel = math.min(100, e.alertLevel + (10 - dist) * dt * 25)
            end
            e.lastSeenX = px; e.lastSeenY = py; e.lastSeenTimer = 0
        else
            e.lastSeenTimer = (e.lastSeenTimer or 0) + dt
        end

        -- alert decay / forgetting
        -- Enemies can lose you if they haven't seen or heard you recently.
        local seenAgo = (e.lastSeenTimer or 999)
        local heardAgo = (e.lastHeardTimer or 999)

        if e.alertLevel > 35 then
            -- committed: decays slowly while contact is recent, faster if stale
            local decayRate = (seenAgo < 1.25 or heardAgo < 1.25) and 3 or 9
            e.alertLevel = math.max(0, e.alertLevel - decayRate * dt)
            -- if no contact for a while, drop out of hunt naturally
            if seenAgo > 6 and heardAgo > 6 then
                e.alertLevel = math.min(e.alertLevel, 34.5)
            end
        elseif e.alertLevel > 10 then
            -- searching: decay to calm if contact goes cold
            local decayRate = (seenAgo < 2 or heardAgo < 2) and 5 or 12
            e.alertLevel = math.max(0, e.alertLevel - decayRate * dt)
        else
            -- calm: gentle decay to zero
            e.alertLevel = math.max(0, e.alertLevel - 4 * dt)
        end
-- state (lower thresholds = more aggressive)
        if e.lightFear > 0 and light > 0.7 then e.state = "flee"
        elseif e.alertLevel > 35 then e.state = "hunt"
        elseif e.alertLevel > 10 then e.state = "search"
        else e.state = "wander" end

        local mx, my = 0, 0
        local spd = e.speed * dt
        -- AI tuning: lower effective chase speed so improved navigation doesn't feel like "warp"
        local huntMul, searchMul, wanderMul = 0.75, 0.5, 0.45

        if e.state == "hunt" then
            if dist > 0.1 then
                if canSeePlayer then
                    mx = (dx / dist) * spd * huntMul; my = (dy / dist) * spd * huntMul
                    e.lastSeenX = px; e.lastSeenY = py
                elseif playerMoving and e.lastHeardX then
                    local hdx = e.lastHeardX - e.x; local hdy = e.lastHeardY - e.y
                    local hd = math.sqrt(hdx*hdx + hdy*hdy)
                    if hd > 0.3 then mx = (hdx/hd)*spd*0.85*huntMul; my = (hdy/hd)*spd*0.85*huntMul end
                elseif e.lastSeenX and (e.lastSeenTimer or 0) < 6 then
                    local sdx = e.lastSeenX - e.x; local sdy = e.lastSeenY - e.y
                    local sd = math.sqrt(sdx*sdx + sdy*sdy)
                    if sd > 0.3 then mx = (sdx/sd)*spd*0.7*huntMul; my = (sdy/sd)*spd*0.7*huntMul
                    else e.alertLevel = e.alertLevel - 6 * dt end
                else
                    e.alertLevel = e.alertLevel - 8 * dt
                end
            end
        elseif e.state == "search" then
            local tx = e.lastHeardX or e.lastSeenX or e.targetX
            local ty = e.lastHeardY or e.lastSeenY or e.targetY
            local tdx = tx - e.x; local tdy = ty - e.y
            local td = math.sqrt(tdx*tdx + tdy*tdy)
            if td > 0.5 then mx = (tdx/td)*spd*0.5*searchMul; my = (tdy/td)*spd*0.5*searchMul end
        elseif e.state == "flee" then
            if dist > 0.1 then mx = -(dx/dist)*spd*1.0; my = -(dy/dist)*spd*1.0 end
        else
            e.wanderTimer = e.wanderTimer - dt
            if e.wanderTimer <= 0 then
                local wa = math.random() * math.pi * 2
                e.targetX = e.x + math.cos(wa) * 3
                e.targetY = e.y + math.sin(wa) * 3
                e.wanderTimer = 2 + math.random() * 3
            end
            local tdx = e.targetX - e.x; local tdy = e.targetY - e.y
            local td = math.sqrt(tdx*tdx + tdy*tdy)
            if td > 0.2 then mx = (tdx/td)*spd*0.4*wanderMul; my = (tdy/td)*spd*0.4*wanderMul end
        end

        -- anti-stuck: if barely moved for 1.2s while hunting/searching, do a deterministic escape
        if e.state == "hunt" or e.state == "search" then
            local movedDist = math.sqrt((e.x - e.prevX)^2 + (e.y - e.prevY)^2)
            if movedDist < 0.02 then
                e.stuckTimer = (e.stuckTimer or 0) + dt
                if e.stuckTimer > 1.2 then
                    -- flip preferred slide side and try a perpendicular step
                    e.slidePref = (e.slidePref or 1) * -1
                    local step = spd * 1.0
                    local perpX, perpY = -my, mx
                    local pd = math.sqrt(perpX*perpX + perpY*perpY)
                    if pd > 0.0001 then
                        perpX, perpY = (perpX/pd)*step*e.slidePref, (perpY/pd)*step*e.slidePref
                        mx, my = perpX, perpY
                    end
                    e.stuckTimer = 0
                end
            else
                e.stuckTimer = 0
            end
        end
        e.prevX = e.x; e.prevY = e.y

        self:tryMoveEnemy(e, mx, my, map)
        if e.hitFlash > 0 then e.hitFlash = e.hitFlash - dt end
        ::continue_enemy::
    end
end

-- ═══ COLLISION ═══
-- Contact damage when enemy overlaps player hitbox
-- Also bounces enemy backward to prevent stuck-in-melee instant deaths
function Enemies:checkPlayerCollision(px, py, playerRadius)
    local hits = {}
    for i, e in ipairs(self.list) do
        if e.noCollide then goto continue_coll end
        local dx = px - e.x; local dy = py - e.y
        local dist = math.sqrt(dx*dx + dy*dy)
        if dist < e.radius + playerRadius then
            if not self._map or self:hasLOS(e.x, e.y, px, py, self._map) then
                hits[#hits+1] = {idx = i, dmg = e.dmg, ex = e.x, ey = e.y}
                -- touching enemy also alerts it
                e.alertLevel = 100
                e.lastSeenX = px; e.lastSeenY = py; e.lastSeenTimer = 0
                -- bounce enemy back away from player
                if dist > 0.01 then
                    local pushDist = 1.2 + e.radius  -- push just outside melee range
                    local ndx = -dx / dist  -- direction away from player
                    local ndy = -dy / dist
                    local newX = e.x + ndx * pushDist
                    local newY = e.y + ndy * pushDist
                    -- only move if destination is not a wall
                    if self._map and not self._map:isWall(newX, newY) then
                        e.x = newX
                        e.y = newY
                    else
                        -- try smaller push
                        newX = e.x + ndx * 0.5
                        newY = e.y + ndy * 0.5
                        if self._map and not self._map:isWall(newX, newY) then
                            e.x = newX; e.y = newY
                        end
                    end
                end
            end
        end
        ::continue_coll::
    end
    return hits
end

function Enemies:kill(idx)
    local e = self.list[idx]
    if not e then return nil end
    local data = {x=e.x, y=e.y, xp=e.xp, dropChance=e.dropChance, name=e.name, soundUID=e.soundUID}
    table.remove(self.list, idx)
    return data
end

-- ═══ MELEE HIT CHECK ═══
-- Checks if player's swing arc hits any enemy
-- Uses pi/4 cone angle + LOS check + reach distance
-- Returns kills, hits (hits = non-lethal with {x, y, soundUID} for hurt sounds)
function Enemies:meleeCheck(px, py, angle, reach, dmg)
    -- Hitbox fixes:
    --   • Arc widened from ±45° to ±60° (120° total cone) — small enemies at the
    --     edge of a swing no longer slip past due to angle precision.
    --   • Reach check now adds e.radius so large enemies register hits on their
    --     body edge, not just their center point.
    --   • LOS check retained — walls still block melee, no hitting through corners.
    local kills = {}
    local hits = {}
    local i = 1
    while i <= #self.list do
        local e = self.list[i]
        if e.invulnerable then i = i + 1; goto continue_melee end
        local dx = e.x - px; local dy = e.y - py
        local dist = math.sqrt(dx*dx + dy*dy)
        local effectiveReach = reach + (e.radius or 0.3)  -- add body radius
        if dist < effectiveReach then
            local ea = math.atan2(dy, dx)
            local da = ea - angle
            while da > math.pi do da = da - math.pi*2 end
            while da < -math.pi do da = da + math.pi*2 end
            if math.abs(da) < math.pi/3 then  -- ±60° (was ±45°)
                if self:hasLOS(px, py, e.x, e.y, self._map) then
                    e.hp = e.hp - dmg; e.hitFlash = 0.15
                    if e.hp <= 0 then
                        kills[#kills+1] = self:kill(i)
                    else
                        hits[#hits+1] = {x = e.x, y = e.y, soundUID = e.soundUID}
                        i = i + 1
                    end
                else i = i + 1 end
            else i = i + 1 end
        else i = i + 1 end
        ::continue_melee::
    end
    return kills, hits
end

-- ═══ V3: CHEST SWARM — burst-spawn enemies around a military chest room ═══
-- Called by main.lua when player enters chest detection range.
-- Spawns count enemies near the chest, all immediately hostile.
-- Mix of hounds (60%) and wretches (40%) for a fast, aggressive fight.
function Enemies:spawnChestSwarm(cx, cy, count, map, wave, soundSystem)
    if self.testMode then return 0 end
    count = count or 8
    local spawned = 0
    for i = 1, count do
        if #self.list >= self.maxEnemies + 10 then break end  -- allow slight overcap for swarm
        for tries = 1, 20 do
            local a = math.random() * math.pi * 2
            local dist = 3 + math.random() * 5
            local ex = cx + math.cos(a) * dist
            local ey = cy + math.sin(a) * dist
            if not map:isWall(ex, ey) then
                local typeIdx = math.random() < 0.6 and 1 or 3
                local t = Enemies.types[typeIdx]
                local scaledHp = math.floor(t.hp * (1 + (wave or 1) * 0.05) * self.hpMult)
                local uid = self:assignUID()
                local e = {
                    x = ex, y = ey, hp = scaledHp, maxHp = scaledHp,
                    speed = t.speed * (1 + (wave or 1) * 0.01) * self.spdMult,
                    dmg = math.floor(t.dmg * (1 + (wave or 1) * 0.035) * self.dmgMult),
                    radius = t.radius,
                    color = {t.color[1], t.color[2], t.color[3]},
                    xp = t.xp, dropChance = t.dropChance,
                    noiseAttract = t.noiseAttract, lightFear = t.lightFear,
                    hitFlash = 0, typeIdx = typeIdx, name = t.name,
                    scale = t.scale or 1.0,
                    state = "hunt", alertLevel = 100,  -- immediately aggressive
                    targetX = cx, targetY = cy,
                    lastSeenX = cx, lastSeenY = cy, lastSeenTimer = 0,
                    lastHeardX = nil, lastHeardY = nil, lastHeardTimer = 999,
                    wanderTimer = 0,
                    soundUID = uid,
                    stuckTimer = 0, prevX = ex, prevY = ey,
                slidePref = (math.random() > 0.5) and 1 or -1,
                    losTimer = math.random() * 0.2, cachedLOS = false,
                }
                self.list[#self.list + 1] = e
                if soundSystem then soundSystem:assignToEnemy(uid) end
                spawned = spawned + 1
                break
            end
        end
    end
    return spawned
end

-- ═══ V4: PORTAL HORDE — enemies guarding the exit portal ═══
-- Spawns a large mixed-type horde around the portal position.
-- All types included, weighted toward tougher enemies for a late-game fight.
function Enemies:spawnPortalHorde(px, py, count, map, wave, soundSystem)
    if self.testMode then return 0 end
    count = count or 15
    local spawned = 0
    for i = 1, count do
        if #self.list >= self.maxEnemies + 20 then break end  -- generous overcap for portal fight
        for tries = 1, 25 do
            local a = math.random() * math.pi * 2
            local dist = 2 + math.random() * 6
            local ex = px + math.cos(a) * dist
            local ey = py + math.sin(a) * dist
            if not map:isWall(ex, ey) then
                -- late-game mix: all 5 types
                local roll = math.random()
                local typeIdx
                if roll < 0.20 then typeIdx = 1       -- hound
                elseif roll < 0.35 then typeIdx = 2   -- crawler
                elseif roll < 0.55 then typeIdx = 3   -- wretch
                elseif roll < 0.75 then typeIdx = 4   -- shade
                else typeIdx = 5 end                   -- skin stealer
                local t = Enemies.types[typeIdx]
                local scaledHp = math.floor(t.hp * (1 + (wave or 30) * 0.05) * self.hpMult)
                local uid = self:assignUID()
                local e = {
                    x = ex, y = ey, hp = scaledHp, maxHp = scaledHp,
                    speed = t.speed * (1 + (wave or 30) * 0.01) * self.spdMult,
                    dmg = math.floor(t.dmg * (1 + (wave or 30) * 0.035) * self.dmgMult),
                    radius = t.radius,
                    color = {t.color[1], t.color[2], t.color[3]},
                    xp = t.xp, dropChance = t.dropChance * 0.5,  -- reduced drops (portal has its own loot)
                    noiseAttract = t.noiseAttract, lightFear = t.lightFear,
                    hitFlash = 0, typeIdx = typeIdx, name = t.name,
                    scale = t.scale or 1.0,
                    state = "hunt", alertLevel = 100,
                    targetX = px, targetY = py,
                    lastSeenX = px, lastSeenY = py, lastSeenTimer = 0,
                    lastHeardX = nil, lastHeardY = nil, lastHeardTimer = 999,
                    wanderTimer = 0,
                    soundUID = uid,
                    stuckTimer = 0, prevX = ex, prevY = ey,
                slidePref = (math.random() > 0.5) and 1 or -1,
                    losTimer = math.random() * 0.2, cachedLOS = false,
                    portalGuard = true,  -- tag for counting remaining guards
                }
                self.list[#self.list + 1] = e
                if soundSystem then soundSystem:assignToEnemy(uid) end
                spawned = spawned + 1
                break
            end
        end
    end
    return spawned
end

-- Count how many portal guard enemies are still alive
function Enemies:countPortalGuards()
    local count = 0
    for _, e in ipairs(self.list) do
        if e.portalGuard then count = count + 1 end
    end
    return count
end

return Enemies