-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║ WEAPONS.LUA — All weapon definitions, firing, bullet management     ║
-- ║                                                                     ║
-- ║ HOW TO MOD:                                                         ║
-- ║   Edit Weapons.list below to change any weapon's stats.             ║
-- ║   Add new weapons by adding rows (auto-appear as item drops).       ║
-- ║   Weapon index 1 = starting weapon (always unlocked).               ║
-- ║                                                                     ║
-- ║ WEAPON FIELDS:                                                      ║
-- ║   name ........... display name on HUD                              ║
-- ║   type ........... "melee" or "ranged"                              ║
-- ║   dmg ............ base damage per hit/bullet                       ║
-- ║   rate ........... seconds between attacks (lower = faster)         ║
-- ║   reach .......... melee range in tiles (melee only)                ║
-- ║   speed .......... bullet travel speed (ranged only)                ║
-- ║   spread ......... aim scatter in radians (ranged only)             ║
-- ║   count .......... projectiles per shot (ranged only)               ║
-- ║   pierce ......... bullets pass through enemies (ranged only)       ║
-- ║   spawnDist ...... bullet spawn distance from player center (tiles) ║
-- ║   staminaCost .... stamina consumed per attack                      ║
-- ║   noise .......... sound level 0-100 (attracts enemies)             ║
-- ║   color .......... {r,g,b} for HUD display and bullet color         ║
-- ║   desc ........... tooltip text                                     ║
-- ╚══════════════════════════════════════════════════════════════════════╝

-- weapons.lua
-- Start with machete, find guns as pickups
-- Universal ammo, 25 rounds per pickup

local Weapons = {}
Weapons.__index = Weapons

Weapons.list = {
    {name="machete", type="melee", dmg=12, rate=0.5, reach=2.5, staminaCost=12, noise=8, color={0.8,0.8,0.9}, desc="Your trusty blade"},
    {name="knife", type="melee", dmg=6, rate=0.3, reach=1.2, staminaCost=8, noise=5, color={0.7,0.7,0.8}, desc="Fast, quiet"},
    {name="pipe", type="melee", dmg=12, rate=0.6, reach=1.8, staminaCost=15, noise=15, color={0.5,0.5,0.6}, desc="Long, loud clang"},
    {name="axe", type="melee", dmg=15, rate=0.8, reach=3, staminaCost=20, noise=12, color={0.6,0.3,0.2}, desc="Heavy damage"},
    {name="pistol", type="ranged", dmg=12, rate=0.4, speed=12, spread=0.03, count=1, pierce=false, spawnDist=0.8, staminaCost=5, noise=60, color={0.8,0.8,0.8}, desc="LOUD"},
    {name="shotgun", type="ranged", dmg=20, rate=0.9, speed=10, spread=0.1, count=5, pierce=false, spawnDist=0.95, staminaCost=8, noise=85, color={0.6,0.4,0.2}, desc="VERY LOUD"},
    {name="smg", type="ranged", dmg=14, rate=0.1, speed=14, spread=0.06, count=1, pierce=false, spawnDist=0.8, staminaCost=3, noise=70, color={0.4,0.4,0.5}, desc="Fast, constant noise"},
    {name="suppressed pistol", type="ranged", dmg=14, rate=0.2, speed=11, spread=0.04, count=1, pierce=false, spawnDist=0.95, staminaCost=5, noise=15, color={0.3,0.3,0.35}, desc="Quiet but weak"},
}

function Weapons.new()
    local self = setmetatable({}, Weapons)
    self.current = 1
    self.fireTimer = 0
    self.swingTimer = 0
    self.swinging = false
    self.bullets = {}
    self.dmgMod = 0
    self.rateMod = 1.0
    self.speedMod = 1.0
    self.countMod = 0
    self.spreadMod = 1.0
    self.unlocked = {true, false, false, false, false, false, false, false}
    self.ammo = 0
    self.ammoPerPickup = 25
    return self
end

function Weapons:getCurrent() return Weapons.list[self.current] end
function Weapons:unlockWeapon(idx) if idx >= 1 and idx <= #Weapons.list then self.unlocked[idx] = true end end
function Weapons:isUnlocked(idx) return self.unlocked[idx] == true end

function Weapons:getUnlockedList()
    local r = {}
    for i, u in ipairs(self.unlocked) do if u then r[#r+1] = i end end
    return r
end

function Weapons:cycleNext()
    local ul = self:getUnlockedList()
    if #ul <= 1 then return end
    local p = 1
    for i, idx in ipairs(ul) do if idx == self.current then p = i break end end
    p = p + 1; if p > #ul then p = 1 end
    self.current = ul[p]
end

function Weapons:cyclePrev()
    local ul = self:getUnlockedList()
    if #ul <= 1 then return end
    local p = 1
    for i, idx in ipairs(ul) do if idx == self.current then p = i break end end
    p = p - 1; if p < 1 then p = #ul end
    self.current = ul[p]
end

function Weapons:update(dt)
    if self.fireTimer > 0 then self.fireTimer = self.fireTimer - dt end
    if self.swingTimer > 0 then
        self.swingTimer = self.swingTimer - dt
        if self.swingTimer <= 0 then self.swinging = false end
    end
end

function Weapons:fire(px, py, angle, playerDmgMult, playerStamina)
    local wep = self:getCurrent()
    local rate = wep.rate * self.rateMod
    if self.fireTimer > 0 then return nil, 0, 0 end
    if playerStamina < wep.staminaCost then return nil, 0, 0 end
    if wep.type == "melee" then
        self.fireTimer = rate
        self.swinging = true
        self.swingTimer = wep.rate * 0.6
        return "melee", wep.staminaCost, wep.noise
    else
        if self.ammo <= 0 then return "no_ammo", 0, 0 end
        self.fireTimer = rate
        local count = wep.count + self.countMod
        if count < 1 then count = 1 end
        self.ammo = self.ammo - 1
        local speed = wep.speed * self.speedMod
        local spawnDist = wep.spawnDist or 0.4  -- distance from player center to barrel tip in tiles
        for i = 1, count do
            local spread = (wep.spread * self.spreadMod)
            local ba = angle + (math.random() * spread * 2 - spread)
            self.bullets[#self.bullets+1] = {
                x = px + math.cos(angle) * spawnDist,
                y = py + math.sin(angle) * spawnDist,
                dx = math.cos(ba) * speed,
                dy = math.sin(ba) * speed,
                dmg = math.floor((wep.dmg + self.dmgMod) * playerDmgMult),
                pierce = wep.pierce, life = 2.0, color = wep.color
            }
        end
        return "ranged", wep.staminaCost, wep.noise
    end
end

function Weapons:addAmmo(n) self.ammo = self.ammo + (n or self.ammoPerPickup) end
function Weapons:getMeleeDamage(mult) return math.floor((self:getCurrent().dmg + self.dmgMod) * mult) end
function Weapons:getMeleeReach() return self:getCurrent().reach or 1.0 end

function Weapons:updateBullets(dt, map, enemies)
    local hits = {}
    local i = 1
    while i <= #self.bullets do
        local b = self.bullets[i]
        b.x = b.x + b.dx * dt
        b.y = b.y + b.dy * dt
        b.life = b.life - dt
        local remove = false
        if map:isWall(b.x, b.y) then remove = true
        elseif b.life <= 0 then remove = true
        else
            for j, e in ipairs(enemies) do
                local dx = b.x - e.x; local dy = b.y - e.y
                local hitR = math.max(e.radius, 0.3) + 0.15  -- enemy hitbox + bullet size, min 0.3 radius
                if dx*dx + dy*dy < hitR * hitR then
                    hits[#hits+1] = {enemy = j, dmg = b.dmg}
                    e.hitFlash = 0.15
                    if not b.pierce then remove = true end
                    break
                end
            end
        end
        if remove then table.remove(self.bullets, i) else i = i + 1 end
    end
    return hits
end

-- ═══ V3: CHEST LOOT HELPERS ═══
-- Returns a random weapon index the player hasn't unlocked yet, or nil if all unlocked.
function Weapons:getRandomLockedWeapon()
    local locked = {}
    for i = 2, #Weapons.list do
        if not self.unlocked[i] then locked[#locked + 1] = i end
    end
    if #locked == 0 then return nil end
    return locked[math.random(1, #locked)]
end

return Weapons
