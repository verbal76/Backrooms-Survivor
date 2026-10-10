-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║ MUSIC.LUA — Background music with random track selection + crossfade║
-- ║                                                                     ║
-- ║ HOW TO MOD:                                                         ║
-- ║   Add .wav files to music/ folder and list them in trackFiles       ║
-- ║   fadeDuration = 4.0 ... seconds for crossfade transition           ║
-- ║   switchInterval ....... 40-90 sec random between track changes     ║
-- ║   targetVolume ......... master music level (controlled by slider)  ║
-- ╚══════════════════════════════════════════════════════════════════════╝

-- music.lua
-- Music manager: randomize tracks, crossfade transitions

local Music = {}
Music.__index = Music

Music.trackFiles = {
    "music/Broken_Circuit.wav",
    "music/Dark_House.wav",
    "music/Darker_House.wav",
    "music/Deafness.wav",
    "music/Filthy_Lab.wav",
    "music/Hypertension.wav",
    "music/Operating_Room.wav",
    "music/Vertigo.wav",
}

function Music.new()
    local self = setmetatable({}, Music)
    self.tracks = {}
    self.currentSource = nil
    self.nextSource = nil
    self.currentVolume = 0
    self.nextVolume = 0
    self.targetVolume = 1.0  -- master music volume (full, controlled by options slider)
    self.fadeDuration = 4.0  -- seconds to crossfade
    self.fadeTimer = 0
    self.fading = false
    self.playedIndices = {}
    self.switchTimer = 0
    self.switchInterval = 0  -- set when track starts (based on track length)
    self.loaded = false
    return self
end

function Music:load()
    for i, file in ipairs(Music.trackFiles) do
        local ok, src = pcall(love.audio.newSource, file, "stream")
        if ok then
            src:setLooping(false)
            self.tracks[i] = src
        end
    end
    self.loaded = true
    self:playRandom()
end

function Music:pickRandom()
    -- avoid repeating recent tracks
    local available = {}
    for i = 1, #self.tracks do
        if self.tracks[i] then
            local recent = false
            for _, pi in ipairs(self.playedIndices) do
                if pi == i then recent = true break end
            end
            if not recent then available[#available+1] = i end
        end
    end
    -- if all played, reset history
    if #available == 0 then
        self.playedIndices = {}
        for i = 1, #self.tracks do
            if self.tracks[i] then available[#available+1] = i end
        end
    end
    if #available == 0 then return nil end
    local idx = available[math.random(#available)]
    -- track history (keep last 4)
    self.playedIndices[#self.playedIndices+1] = idx
    if #self.playedIndices > 4 then
        table.remove(self.playedIndices, 1)
    end
    return idx
end

function Music:playRandom()
    local idx = self:pickRandom()
    if not idx then return end

    local src = self.tracks[idx]:clone()
    src:setVolume(0)
    src:play()

    if self.currentSource then
        -- crossfade
        self.nextSource = src
        self.nextVolume = 0
        self.fading = true
        self.fadeTimer = 0
    else
        self.currentSource = src
        self.currentVolume = self.targetVolume
        src:setVolume(self.targetVolume)
    end

    -- schedule next switch: random 40-90 seconds
    self.switchTimer = 0
    self.switchInterval = 40 + math.random() * 50
end

function Music:update(dt)
    if not self.loaded then return end

    -- crossfade
    if self.fading then
        self.fadeTimer = self.fadeTimer + dt
        local progress = math.min(1, self.fadeTimer / self.fadeDuration)

        -- fade out current
        self.currentVolume = self.targetVolume * (1 - progress)
        if self.currentSource then
            self.currentSource:setVolume(self.currentVolume)
        end

        -- fade in next
        self.nextVolume = self.targetVolume * progress
        if self.nextSource then
            self.nextSource:setVolume(self.nextVolume)
        end

        if progress >= 1 then
            -- swap
            if self.currentSource then
                self.currentSource:stop()
            end
            self.currentSource = self.nextSource
            self.currentVolume = self.targetVolume
            self.nextSource = nil
            self.nextVolume = 0
            self.fading = false
        end
    end

    -- check if current track ended
    if self.currentSource and not self.currentSource:isPlaying() and not self.fading then
        self:playRandom()
    end

    -- periodic switch for variety
    self.switchTimer = self.switchTimer + dt
    if self.switchTimer >= self.switchInterval and not self.fading then
        self:playRandom()
    end

    -- apply volume to current
    if self.currentSource and not self.fading then
        self.currentSource:setVolume(self.targetVolume)
    end
end

function Music:setVolume(vol)
    self.targetVolume = math.max(0, math.min(1, vol))
    if self.currentSource and not self.fading then
        self.currentSource:setVolume(self.targetVolume)
    end
end

function Music:stop()
    if self.currentSource then self.currentSource:stop() end
    if self.nextSource then self.nextSource:stop() end
end

return Music
