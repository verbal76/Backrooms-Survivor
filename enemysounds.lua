-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║ ENEMYSOUNDS.LUA — Per-enemy ambient sounds + hurt + attack sounds   ║
-- ║                                                                     ║
-- ║ HOW TO MOD:                                                         ║
-- ║   Add .wav/.ogg/.mp3 files to sounds/ folder                        ║
-- ║   File naming conventions (case insensitive):                       ║
-- ║     "breath xxx.wav" ........... LOOPED ambient per enemy           ║
-- ║     "phrase xxx.wav" ........... one-shot voice line (random timer) ║
-- ║     "hell beast attack xxx.wav"  one-shot on enemy contact damage   ║
-- ║     "hell beast dies xxx.wav" .. one-shot when player hits enemy    ║
-- ║     "death_xxx.wav" ........... (same as hell beast dies)           ║
-- ║     "UI_xxx.wav" .............. title screen/menu music             ║
-- ║     anything else .............. IGNORED by this system             ║
-- ║                                                                     ║
-- ║   maxDist = 15 .... tiles before sound fades to zero                ║
-- ║   masterVolume ..... overall enemy sound level (set by options)      ║
-- ╚══════════════════════════════════════════════════════════════════════╝

local EnemySounds = {}
EnemySounds.__index = EnemySounds

function EnemySounds.new()
    local self = setmetatable({}, EnemySounds)
    self.breathSounds = {}    -- "breath" files → looped ambient, one per enemy
    self.phraseSounds = {}    -- "phrase" files → one-shot, random timer
    self.attackSounds = {}    -- "hell beast attack" files → one-shot on contact damage
    self.hurtSounds = {}      -- "hell beast dies" / "death_" files → one-shot on player hit
    self.uiSounds = {}        -- "UI_" files → menu music
    self.assignments = {}     -- enemyUID -> {source, playing, phraseTimer, phraseCooldown}
    self.fadingOut = {}       -- sources fading to 0 then stopping
    self.maxDist = 15
    self.masterVolume = 0.7
    self.loaded = false
    self.nextUID = 1
    return self
end

function EnemySounds:load(folder)
    local ok, items = pcall(love.filesystem.getDirectoryItems, folder)
    if not ok or not items then return end

    for _, file in ipairs(items) do
        local ext = file:match("%.(%w+)$")
        if ext and (ext == "wav" or ext == "ogg" or ext == "mp3") then
            local path = folder .. "/" .. file
            local okLoad, src = pcall(love.audio.newSource, path, "static")
            if okLoad and src then
                local lower = file:lower()

                if lower:find("^ui_") or lower:find("^ui ") then
                    -- ═══ UI / MENU MUSIC ═══
                    src:setLooping(true)
                    self.uiSounds[#self.uiSounds+1] = {source = src, filename = file}

                elseif lower:find("^hell beast attack") or lower:find("^hellbeastattack") then
                    -- ═══ ATTACK SOUNDS (enemy damages player) — one-shot ═══
                    src:setLooping(false)
                    self.attackSounds[#self.attackSounds+1] = {source = src, filename = file}

                elseif lower:find("hell beast dies") or lower:find("hellbeastdies")
                    or lower:find("^death_") or lower:find("^death ") then
                    -- ═══ HURT SOUNDS (player damages enemy) — one-shot, fades on kill ═══
                    src:setLooping(false)
                    self.hurtSounds[#self.hurtSounds+1] = {source = src, filename = file}

                elseif lower:find("breath") then
                    -- ═══ BREATH SOUNDS — LOOPED ambient, one assigned per enemy ═══
                    src:setLooping(true)
                    self.breathSounds[#self.breathSounds+1] = {source = src, filename = file}

                elseif lower:find("phrase") then
                    -- ═══ PHRASE SOUNDS — one-shot, random timer, shared pool ═══
                    src:setLooping(false)
                    self.phraseSounds[#self.phraseSounds+1] = {source = src, filename = file}

                -- else: IGNORED (gunshot_sound, swing_sound, whispers, etc.
                --        are handled by main.lua weapon sound system, not here)
                end
            end
        end
    end
    self.loaded = #self.breathSounds > 0 or #self.phraseSounds > 0
    print("[ENEMYSOUNDS] Loaded: " .. #self.breathSounds .. " breath, "
        .. #self.phraseSounds .. " phrase, " .. #self.attackSounds .. " attack, "
        .. #self.hurtSounds .. " hurt, " .. #self.uiSounds .. " UI")
end

function EnemySounds:assignUID()
    local uid = self.nextUID
    self.nextUID = self.nextUID + 1
    return uid
end

-- Assign a BREATH sound (looped) to an enemy. Phrases use a shared pool.
function EnemySounds:assignToEnemy(uid)
    if self.assignments[uid] then return end

    local src = nil
    if #self.breathSounds > 0 then
        local idx = math.random(1, #self.breathSounds)
        local template = self.breathSounds[idx]
        src = template.source:clone()
        src:setLooping(true)
    end

    self.assignments[uid] = {
        source = src,          -- nil if no breath sounds exist
        playing = false,
        phraseTimer = math.random() * 10,
        phraseCooldown = 5 + math.random() * 15,
    }
end

-- Called when enemy dies: fade out breath loop + play a fading hurt sound
function EnemySounds:onEnemyDeath(uid, x, y, playerX, playerY)
    -- fade out the breath loop
    local a = self.assignments[uid]
    if a then
        if a.playing and a.source then
            self.fadingOut[#self.fadingOut+1] = {source = a.source, volume = a.source:getVolume(), rate = 2.0}
        elseif a.source then
            a.source:stop()
        end
    end
    self.assignments[uid] = nil

    -- play a hurt sound that fades out (the killing blow sound)
    self:playHurt(x, y, playerX, playerY, true)
end

-- Play a random "hell beast dies" sound when player hits an enemy with a weapon.
-- isKill=true: sound fades out as they die. isKill=false: plays to completion.
function EnemySounds:playHurt(x, y, playerX, playerY, isKill)
    if #self.hurtSounds == 0 then return end
    local dx = x - playerX
    local dy = y - playerY
    local dist = math.sqrt(dx*dx + dy*dy)
    if dist >= self.maxDist then return end

    local vol = (1.0 - dist / self.maxDist) * self.masterVolume
    vol = vol * vol
    vol = math.max(0.05, math.min(1.0, vol))

    local hs = self.hurtSounds[math.random(1, #self.hurtSounds)]
    local src = hs.source:clone()
    src:setLooping(false)
    src:setVolume(vol)
    src:play()

    if isKill then
        -- fade out over ~0.8 seconds so it trails off as they die
        self.fadingOut[#self.fadingOut+1] = {source = src, volume = vol, rate = vol / 0.8}
    end
    -- non-kill: one-shot plays to completion on its own
end

-- Play a random "hell beast attack" sound when enemy damages the player (one-shot)
function EnemySounds:playAttack(x, y, playerX, playerY)
    if #self.attackSounds == 0 then return end
    local dx = x - playerX
    local dy = y - playerY
    local dist = math.sqrt(dx*dx + dy*dy)
    if dist >= self.maxDist then return end

    local vol = (1.0 - dist / self.maxDist) * self.masterVolume * 0.8
    vol = vol * vol
    local as = self.attackSounds[math.random(1, #self.attackSounds)]
    local src = as.source:clone()
    src:setLooping(false)
    src:setVolume(math.max(0.1, math.min(1.0, vol)))
    src:play()
end

function EnemySounds:update(dt, enemies, playerX, playerY)
    -- update fade-outs
    local i = 1
    while i <= #self.fadingOut do
        local f = self.fadingOut[i]
        f.volume = f.volume - f.rate * dt
        if f.volume <= 0 then
            f.source:stop()
            table.remove(self.fadingOut, i)
        else
            f.source:setVolume(f.volume)
            i = i + 1
        end
    end

    local hasBreath = #self.breathSounds > 0
    local hasPhrase = #self.phraseSounds > 0
    if not hasBreath and not hasPhrase then return end

    -- update active enemy sounds
    for _, e in ipairs(enemies) do
        if not e.soundUID then goto continue end
        self:assignToEnemy(e.soundUID)
        local a = self.assignments[e.soundUID]
        if not a then goto continue end

        local dx = e.x - playerX
        local dy = e.y - playerY
        local dist = math.sqrt(dx*dx + dy*dy)

        if dist < self.maxDist then
            local vol = (1.0 - dist / self.maxDist) * self.masterVolume
            vol = vol * vol

            -- BREATH LOOP: play/stop based on distance
            if a.source then
                a.source:setVolume(vol)
                if not a.playing then
                    a.source:play()
                    a.playing = true
                end
            end

            -- PHRASE: random one-shot from shared pool on a timer (never looped)
            if hasPhrase then
                a.phraseTimer = a.phraseTimer + dt
                if a.phraseTimer >= a.phraseCooldown
                   and (e.state == "hunt" or e.state == "search")
                   and dist < 8 then
                    local ps = self.phraseSounds[math.random(1, #self.phraseSounds)]
                    local phraseSrc = ps.source:clone()
                    phraseSrc:setLooping(false)
                    phraseSrc:setVolume(vol)
                    phraseSrc:play()
                    a.phraseTimer = 0
                    a.phraseCooldown = 8 + math.random() * 20
                end
            end
        else
            -- out of range: stop breath loop
            if a.playing and a.source then
                a.source:stop()
                a.playing = false
            end
        end
        ::continue::
    end
end

function EnemySounds:setVolume(vol)
    self.masterVolume = math.max(0, math.min(1, vol))
end

function EnemySounds:stopAll()
    for _, a in pairs(self.assignments) do
        if a.source then a.source:stop() end
    end
    self.assignments = {}
    for _, f in ipairs(self.fadingOut) do f.source:stop() end
    self.fadingOut = {}
end

function EnemySounds:getUISound()
    if #self.uiSounds > 0 then
        return self.uiSounds[math.random(1, #self.uiSounds)].source
    end
    return nil
end

return EnemySounds
