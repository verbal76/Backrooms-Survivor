-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║ PROPS.LUA — Environmental objects: bodies, furniture, clutter        ║
-- ║                                                                     ║
-- ║ SPRITES: Individual PNGs in world_assets/ folder                     ║
-- ║ Example: world_assets/body_facedown.png, world_assets/desk_standard.png ║
-- ║ Each sprite can be ANY size (32x32, 256x256, 640x640, etc.)          ║
-- ║ This module will scale to your tileSize at draw time (nearest filter)║
-- ║ Falls back to props_placeholder.png spritesheet if no individual     ║
-- ╚══════════════════════════════════════════════════════════════════════╝

local Props = {}
Props.__index = Props

-- ═══ SPAWN RATES (per chunk) ═══
Props.SPAWN_RATES = {
    bodiesMin   = 0,
    bodiesMax   = 2,
    furnitureMin = 2,
    furnitureMax = 6,
    clutterMin   = 1,
    clutterMax   = 4,
}

-- ════════════════════════════════════════════════════════════════════════
-- ═══ HIGH-RES PROP TWEAK SECTION (KEEP THIS) ═══
--
-- If you keep props at 640x640 (or any hi-res), set how many *tiles*
-- they should occupy visually. This improves readability a ton.
--
-- tilesW / tilesH:
--   - 1,1 means “fit inside 1 tile”
--   - 2,1 means “desk is wider: fit inside 2 tiles wide, 1 tall”
--   - 1,2 means “tall object: fit inside 1 tile wide, 2 tall”
--
-- scale:
--   - extra multiplier AFTER fitting; use this for fine tuning
--
-- pivotX / pivotY:
--   - 0.5,0.5 is center (default)
--   - 0.5,0.8 makes it “sit” lower visually, etc.
--
-- If a prop is missing here, it will fall back to def.scale and 1x1 fit.
-- ════════════════════════════════════════════════════════════════════════
Props.RENDER_TWEAKS = {
    -- Bodies usually 1 tile
    body_facedown   = { tilesW = 1, tilesH = 1, scale = 1.00 },
    body_slumped    = { tilesW = 1, tilesH = 1, scale = 1.00 },
    body_fetal      = { tilesW = 1, tilesH = 1, scale = 1.00 },
    body_crawling   = { tilesW = 1, tilesH = 1, scale = 1.00 },

    -- Desks read better as 2x1
    desk_standard   = { tilesW = 2, tilesH = 1, scale = 1.00 },
    desk_monitor    = { tilesW = 2, tilesH = 1, scale = 1.00 },
    desk_papers     = { tilesW = 2, tilesH = 1, scale = 1.00 },
    desk_overturned = { tilesW = 2, tilesH = 1, scale = 1.00 },

    -- Chairs often 1x1, but you can bump scale slightly
    chair_office    = { tilesW = 1, tilesH = 1, scale = 1.05 },
    chair_knocked   = { tilesW = 1, tilesH = 1, scale = 1.05 },
    chair_simple    = { tilesW = 1, tilesH = 1, scale = 1.05 },
    chair_broken    = { tilesW = 1, tilesH = 1, scale = 1.05 },

    -- Break room / machines
    coffee_machine  = { tilesW = 1, tilesH = 1, scale = 1.10 },
    water_cooler    = { tilesW = 1, tilesH = 2, scale = 1.00 }, -- tall
    coffee_mugs     = { tilesW = 1, tilesH = 1, scale = 1.00 },
    vending_machine = { tilesW = 1, tilesH = 2, scale = 1.00 }, -- tall

    -- Clutter
    papers_scattered= { tilesW = 1, tilesH = 1, scale = 1.00 },
    papers_folder   = { tilesW = 1, tilesH = 1, scale = 1.00 },
    cardboard_box   = { tilesW = 1, tilesH = 1, scale = 1.05 },
    debris_pile     = { tilesW = 1, tilesH = 1, scale = 1.10 },

    -- Shelving / cabinets
    filing_cabinet  = { tilesW = 1, tilesH = 2, scale = 1.00 }, -- tall
    bookshelf       = { tilesW = 1, tilesH = 2, scale = 1.00 }, -- tall
    cabinet_open    = { tilesW = 1, tilesH = 2, scale = 1.00 }, -- tall-ish
    shelf_toppled   = { tilesW = 2, tilesH = 1, scale = 1.00 }, -- wide
}

-- ═══ PROP DEFINITIONS ═══
-- row/col = position in sprite sheet (0-indexed)
-- solid = blocks movement
-- scale = legacy multiplier (still used as fallback)
-- category = used for spawn groups
Props.DEFS = {
    -- DEAD BODIES
    { name = "body_facedown",  row = 0, col = 0, solid = false, scale = 1.0, category = "body" },
    { name = "body_slumped",   row = 0, col = 1, solid = false, scale = 1.0, category = "body" },
    { name = "body_fetal",     row = 0, col = 2, solid = false, scale = 1.0, category = "body" },
    { name = "body_crawling",  row = 0, col = 3, solid = false, scale = 1.0, category = "body" },

    -- DESKS
    { name = "desk_standard",  row = 1, col = 0, solid = true,  scale = 1.2, category = "furniture" },
    { name = "desk_monitor",   row = 1, col = 1, solid = true,  scale = 1.2, category = "furniture" },
    { name = "desk_papers",    row = 1, col = 2, solid = true,  scale = 1.2, category = "furniture" },
    { name = "desk_overturned",row = 1, col = 3, solid = true,  scale = 1.2, category = "furniture" },

    -- CHAIRS
    { name = "chair_office",   row = 2, col = 0, solid = true,  scale = 0.9, category = "furniture" },
    { name = "chair_knocked",  row = 2, col = 1, solid = false, scale = 0.9, category = "furniture" },
    { name = "chair_simple",   row = 2, col = 2, solid = true,  scale = 0.9, category = "furniture" },
    { name = "chair_broken",   row = 2, col = 3, solid = false, scale = 0.9, category = "furniture" },

    -- COFFEE STATIONS
    { name = "coffee_machine", row = 3, col = 0, solid = true,  scale = 1.0, category = "furniture" },
    { name = "water_cooler",   row = 3, col = 1, solid = true,  scale = 1.0, category = "furniture" },
    { name = "coffee_mugs",    row = 3, col = 2, solid = true,  scale = 1.0, category = "furniture" },
    { name = "vending_machine",row = 3, col = 3, solid = true,  scale = 1.3, category = "furniture" },

    -- CLUTTER
    { name = "papers_scattered",row = 4, col = 0, solid = false, scale = 1.0, category = "clutter" },
    { name = "papers_folder",  row = 4, col = 1, solid = false, scale = 0.8, category = "clutter" },
    { name = "cardboard_box",  row = 4, col = 2, solid = true,  scale = 1.0, category = "clutter" },
    { name = "debris_pile",    row = 4, col = 3, solid = false, scale = 1.1, category = "clutter" },

    -- SHELVING
    { name = "filing_cabinet", row = 5, col = 0, solid = true,  scale = 1.0, category = "furniture" },
    { name = "bookshelf",      row = 5, col = 1, solid = true,  scale = 1.2, category = "furniture" },
    { name = "cabinet_open",   row = 5, col = 2, solid = true,  scale = 1.0, category = "furniture" },
    { name = "shelf_toppled",  row = 5, col = 3, solid = true,  scale = 1.2, category = "furniture" },
}

-- Build lookup tables by category for spawning
Props.BODIES = {}
Props.FURNITURE = {}
Props.CLUTTER = {}
for _, def in ipairs(Props.DEFS) do
    if def.category == "body" then Props.BODIES[#Props.BODIES+1] = def
    elseif def.category == "furniture" then Props.FURNITURE[#Props.FURNITURE+1] = def
    elseif def.category == "clutter" then Props.CLUTTER[#Props.CLUTTER+1] = def
    end
end

function Props.new()
    local self = setmetatable({}, Props)
    self.list = {}
    self.spriteSheet = nil
    self.quads = {}
    return self
end

function Props:loadSprites()
    self.sprites = {}
    for _, def in ipairs(Props.DEFS) do
        local path = "world_assets/" .. def.name .. ".png"
        local ok, img = pcall(love.graphics.newImage, path)
        if ok then
            img:setFilter("nearest", "nearest")
            self.sprites[def.name] = img
        end
    end

    local ok2, sheet = pcall(love.graphics.newImage, "props_placeholder.png")
    if ok2 then
        self.spriteSheet = sheet
        sheet:setFilter("nearest", "nearest")
        local sw, sh = sheet:getDimensions()
        for _, def in ipairs(Props.DEFS) do
            self.quads[def.name] = love.graphics.newQuad(
                def.col * 32, def.row * 32, 32, 32, sw, sh
            )
        end
    end
end

function Props:spawnInChunk(cx, cy, map)
    local S = Props.SPAWN_RATES

    -- Spawn SOLID furniture first so it can claim tiles (markSolid) before bodies/clutter pick open spots.
    local furnCount = math.random(S.furnitureMin, S.furnitureMax)
    for i = 1, furnCount do
        local def = Props.FURNITURE[math.random(#Props.FURNITURE)]
        local x, y = map:randomOpenInChunk(cx, cy)
        if x then
            self.list[#self.list+1] = {
                x = x, y = y, def = def,
                rotation = math.random(0, 3) * math.pi / 2,
            }
            if def.solid then map:markSolid(math.floor(x), math.floor(y)) end
        end
    end

    -- Then spawn bodies (non-solid), so they won't land on newly-marked wall tiles.
    local bodyCount = math.random(S.bodiesMin, S.bodiesMax)
    for i = 1, bodyCount do
        local def = Props.BODIES[math.random(#Props.BODIES)]
        local x, y = map:randomOpenInChunk(cx, cy)
        if x then
            self.list[#self.list+1] = {
                x = x, y = y, def = def,
                rotation = math.random() * 0.4 - 0.2,
                bloodTrail = math.random() < 0.6,
                bloodAngle = math.random() * math.pi * 2,
                bloodLen = 0.5 + math.random() * 1.5,
            }
            if def.solid then map:markSolid(math.floor(x), math.floor(y)) end
        end
    end

    -- And finally clutter.
    local clutterCount = math.random(S.clutterMin, S.clutterMax)
    for i = 1, clutterCount do
        local def = Props.CLUTTER[math.random(#Props.CLUTTER)]
        local x, y = map:randomOpenInChunk(cx, cy)
        if x then
            self.list[#self.list+1] = {
                x = x, y = y, def = def,
                rotation = math.random() * math.pi * 2,
            }
            if def.solid then map:markSolid(math.floor(x), math.floor(y)) end
        end
    end
end


-- Compute a consistent draw scale for ANY source image size (including 640x640)
local function computeScale(tileSize, def, imgW, imgH)
    local tweak = Props.RENDER_TWEAKS[def.name]

    -- Defaults if not specified
    local tilesW = (tweak and tweak.tilesW) or 1
    local tilesH = (tweak and tweak.tilesH) or 1
    local extra  = (tweak and tweak.scale)  or 1.0

    -- Legacy def.scale stays in play as a global per-def multiplier
    local legacy = def.scale or 1.0

    -- Fit image into the tile footprint (preserve aspect)
    local targetW = tileSize * tilesW
    local targetH = tileSize * tilesH
    local sx = targetW / imgW
    local sy = targetH / imgH
    local fit = math.min(sx, sy)

    return fit * legacy * extra
end

local function computePivot(def, imgW, imgH)
    local tweak = Props.RENDER_TWEAKS[def.name]
    local px = (tweak and tweak.pivotX) or 0.5
    local py = (tweak and tweak.pivotY) or 0.5
    return imgW * px, imgH * py
end

function Props:draw(tileSize, camX, camY, screenW, screenH)
    local vx0 = camX - 2
    local vy0 = camY - 2
    local vx1 = camX + screenW / tileSize + 2
    local vy1 = camY + screenH / tileSize + 2

    for _, prop in ipairs(self.list) do
        if prop.x >= vx0 and prop.x <= vx1 and prop.y >= vy0 and prop.y <= vy1 then
            -- Snap to whole pixels to reduce shimmer if camera math introduces subpixels
            local sx = math.floor(prop.x * tileSize + 0.5)
            local sy = math.floor(prop.y * tileSize + 0.5)
            local defName = prop.def.name

            if prop.bloodTrail then
                love.graphics.setColor(0.35, 0.08, 0.05, 0.6)
                local bx = sx + math.cos(prop.bloodAngle) * prop.bloodLen * tileSize * 0.3
                local by = sy + math.sin(prop.bloodAngle) * prop.bloodLen * tileSize * 0.3
                love.graphics.setLineWidth(3)
                love.graphics.line(sx, sy, bx, by)
                love.graphics.setLineWidth(1)
                love.graphics.circle("fill", bx, by, 4)
            end

            love.graphics.setColor(1, 1, 1, 1)

            local indivSprite = self.sprites and self.sprites[defName]
            if indivSprite then
                local iw, ih = indivSprite:getDimensions()
                local sc = computeScale(tileSize, prop.def, iw, ih)
                local ox, oy = computePivot(prop.def, iw, ih)
                love.graphics.draw(indivSprite, sx, sy, prop.rotation, sc, sc, ox, oy)

            elseif self.spriteSheet and self.quads[defName] then
                -- fallback to spritesheet
                local sc = (prop.def.scale or 1.0) * (tileSize / 32)
                love.graphics.draw(self.spriteSheet, self.quads[defName], sx, sy, prop.rotation, sc, sc, 16, 16)
            end
        end
    end
end

function Props:cleanup(px, py)
    local despawnSq = 80 * 80
    local i = #self.list
    while i >= 1 do
        local p = self.list[i]
        local dx = px - p.x; local dy = py - p.y
        if dx*dx + dy*dy > despawnSq then
            table.remove(self.list, i)
        end
        i = i - 1
    end
end

return Props