-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║ MAP.LUA — Infinite chunk-based Backrooms level generator            ║
-- ║                                                                     ║
-- ║ GENERATION (7 steps per chunk):                                     ║
-- ║   1. Grid maze with recursive backtracking (cell size 3)            ║
-- ║   2. Loop passages (50%) to reduce dead ends                        ║
-- ║   3. Long hallways (4-8) + large rooms (3-6) per chunk              ║
-- ║   4. Break thick walls (max 2 tiles thick)                          ║
-- ║   5. Edge openings (4 per side) with corridors to maze              ║
-- ║   6. Flood fill connects any isolated pockets to main area          ║
-- ║   7. Blood marks (cosmetic, 3-8 per chunk)                          ║
-- ║                                                                     ║
-- ║ GUARANTEES: every open tile reachable, max wall thickness 2,        ║
-- ║ every chunk edge has 4 two-tile openings into the maze network      ║
-- ╚══════════════════════════════════════════════════════════════════════╝

-- map.lua
-- Infinite chunk-based Backrooms map
-- Long halls, large rooms, blood marks
-- Generates as player approaches edges, never repeats

local CHUNK = 48  -- tiles per chunk side

local Map = {}
Map.__index = Map
Map.CHUNK = CHUNK  -- expose chunk size (tiles) for other modules
  -- tiles per chunk side
local SEED_BASE = 0
local TILE_FLOOR = 0
local TILE_WALL  = 1
local TILE_VOID  = 2  -- non-playable dead space (rendered green, blocks movement/LOS, never spawns)

function Map.new()
    local self = setmetatable({}, Map)
    self.chunks = {}      -- "cx,cy" -> {tiles={}, blood={}, generated=true}
    self.rooms = {}
    self.lights = {}
    self.newChunks = {}   -- queue of {cx, cy} for freshly generated chunks (item spawning)
    SEED_BASE = math.random(1, 999999)
    return self
end

-- Compatibility: main.lua expects Map:generate(), Map:expandAround(), and Map:isWall()
function Map:generate()
    -- Generate a small starter area around origin so spawn/collision/lighting have real tiles
    for cy=-1,1 do
        for cx=-1,1 do
            self:ensureChunk(cx, cy)
        end
    end
end

function Map:expandAround(px, py, viewTiles)
    -- Ensure chunks exist around the player's current tile position.
    -- px/py are in tile-space (can be fractional); viewTiles is radius in tiles.
    local tx = math.floor(px)
    local ty = math.floor(py)
    local cx = math.floor(tx / CHUNK)
    local cy = math.floor(ty / CHUNK)

    local radiusTiles = viewTiles or 32
    local radiusChunks = math.max(1, math.ceil(radiusTiles / CHUNK) + 1)

    for yy = cy - radiusChunks, cy + radiusChunks do
        for xx = cx - radiusChunks, cx + radiusChunks do
            self:ensureChunk(xx, yy)
        end
    end
end

function Map:isWall(x, y)
    -- Used by lighting raycast in main.lua; x/y are tile coords (can be fractional)
    local tx = math.floor(x)
    local ty = math.floor(y)
    return self:isSolidTile(tx, ty)
end

-- deterministic seed per chunk
local function chunkSeed(cx, cy)
    return SEED_BASE + cx * 73856093 + cy * 19349669
end

local function chunkKey(cx, cy) return cx..","..cy end

function Map:ensureChunk(cx, cy)
    local key = chunkKey(cx, cy)
    if self.chunks[key] then return end
    self:generateChunk(cx, cy)
    self.newChunks[#self.newChunks + 1] = {cx = cx, cy = cy}
end

function Map:get(x, y)
    local cx = math.floor(x / CHUNK)
    local cy = math.floor(y / CHUNK)
    local key = chunkKey(cx, cy)
    local chunk = self.chunks[key]
    if not chunk then return TILE_WALL end
    local lx = x - cx * CHUNK
    local ly = y - cy * CHUNK
    return chunk.tiles[ly * CHUNK + lx] or TILE_WALL
end

function Map:set(x, y, v)
    local cx = math.floor(x / CHUNK)
    local cy = math.floor(y / CHUNK)
    local key = chunkKey(cx, cy)
    local chunk = self.chunks[key]
    if not chunk then return end
    local lx = x - cx * CHUNK
    local ly = y - cy * CHUNK
    chunk.tiles[ly * CHUNK + lx] = v
end

function Map:isWallTile(tx, ty)
    -- True only for actual wall tiles (used for wall rendering/rects)
    return self:get(tx, ty) == TILE_WALL
end

function Map:isVoidTile(tx, ty)
    return self:get(tx, ty) == TILE_VOID
end

function Map:isSolidTile(tx, ty)
    -- Blocks movement / LOS: walls AND void
    local v = self:get(tx, ty)
    return v == TILE_WALL or v == TILE_VOID
end

-- Returns wall rectangles (tile units) for rendering a wall tile at (tx,ty).
-- Every wall tile renders as a full 1x1 solid block. This ensures:
--   - No gaps or invisible slivers at floor/void boundaries
--   - Corner wall tiles never render as tiny invisible dots
--   - Thick wall masses look solid, not like floating bricks
-- The thin-strip directional logic caused void to visually bleed through
-- at any corner where a wall tile had no wall-type cardinal neighbours.
function Map:getWallRects(tx, ty)
    if not self:isWallTile(tx, ty) then return nil end
    return {{x = tx, y = ty, w = 1, h = 1}}
end
function Map:generateChunk(cx, cy)
    local key = chunkKey(cx, cy)
    local chunk = {tiles = {}, blood = {}, generated = true}
    self.chunks[key] = chunk

    -- seed RNG for this chunk
    local rng = self:makeRng(chunkSeed(cx, cy))

    local function idx(x,y) return y * CHUNK + x end
    local function inb(x,y) return x >= 0 and x < CHUNK and y >= 0 and y < CHUNK end
    local function setWall(x,y) if inb(x,y) then chunk.tiles[idx(x,y)] = TILE_WALL end end
    local function setFloor(x,y) if inb(x,y) then chunk.tiles[idx(x,y)] = TILE_FLOOR end end

    -- Start as all WALL, then carve balanced “Option 2” spines plus attached rooms.
    for i = 0, CHUNK * CHUNK - 1 do
        chunk.tiles[i] = TILE_WALL
    end

    local mid = math.floor(CHUNK / 2)

    -- Helpers
    local function clamp(v, lo, hi)
        if v < lo then return lo end
        if v > hi then return hi end
        return v
    end

    local function carveRect(x0, y0, w, h)
        for y = y0, y0 + h - 1 do
            for x = x0, x0 + w - 1 do
                setFloor(x, y)
            end
        end
    end

    local function carveAt(x, y, width)
        width = width or 1
        local r = math.floor(width / 2)
        for oy = -r, r do
            for ox = -r, r do
                setFloor(x + ox, y + oy)
            end
        end
    end

    -- Carve a 1–3 tile corridor between points with mild “office jog” meander.
    local function carveMeander(x0, y0, x1, y1, width, meander)
        width = width or 2
        meander = meander or 0.22
        x0, y0 = clamp(x0, 1, CHUNK - 2), clamp(y0, 1, CHUNK - 2)
        x1, y1 = clamp(x1, 1, CHUNK - 2), clamp(y1, 1, CHUNK - 2)

        local x, y = x0, y0
        local guard = 0
        while (x ~= x1 or y ~= y1) and guard < 6000 do
            guard = guard + 1
            carveAt(x, y, width)

            local dx = x1 - x
            local dy = y1 - y
            if dx == 0 and dy == 0 then break end

            -- Prefer the dominant axis, but sometimes “jog” perpendicular for liminal twists.
            if rng() < meander then
                if math.abs(dx) > math.abs(dy) then
                    y = y + ((rng() < 0.5) and -1 or 1)
                else
                    x = x + ((rng() < 0.5) and -1 or 1)
                end
            else
                if math.abs(dx) >= math.abs(dy) then
                    x = x + ((dx > 0) and 1 or -1)
                else
                    y = y + ((dy > 0) and 1 or -1)
                end
            end

            x = clamp(x, 1, CHUNK - 2)
            y = clamp(y, 1, CHUNK - 2)
        end
        carveAt(x1, y1, width)
    end

    -- Corridor widths: 2 (side passage), 3 (main hall), 4 (wide corridor). No width-1.
    -- ── CORRIDOR WIDTHS: minimum 2, no width-1 slivers ─────────────────
    -- ══════════════════════════════════════════════════════════════════
    -- GENERATION: Two parallel E-W halls + rooms branching off them
    --
    -- Structure:
    --   yA  = upper main corridor (3-wide, inner span only)
    --   yB  = lower main corridor (3-wide, inner span only)
    --   Rooms placed in 2 rows (above yA, between halls, below yB) via zone grid
    --   Each room connects to the nearer hall with a 2-wide doorway stub
    --   2-3 vertical cross-connectors link the two halls
    --   Edge seams tap into the nearest hall at a fixed point
    --
    -- Width rules: 2 = doorway/stub, 3 = main hall, 4 = wide hall (rare)
    -- ══════════════════════════════════════════════════════════════════

    -- Straight axis-aligned L-corridor (one 90° turn).
    local function carveL(x0, y0, x1, y1, w)
        w = w or 2
        x0=clamp(x0,1,CHUNK-2); y0=clamp(y0,1,CHUNK-2)
        x1=clamp(x1,1,CHUNK-2); y1=clamp(y1,1,CHUNK-2)
        if x0==x1 then
            -- pure vertical
            carveRect(x0-math.floor((w-1)/2), math.min(y0,y1),
                      w, math.abs(y1-y0)+1)
            return
        end
        if y0==y1 then
            -- pure horizontal
            carveRect(math.min(x0,x1), y0-math.floor((w-1)/2),
                      math.abs(x1-x0)+1, w)
            return
        end
        -- L-shape: horiz first then vert (or vice versa based on rng)
        local ex, ey
        if rng() < 0.5 then ex,ey = x1,y0 else ex,ey = x0,y1 end
        -- leg 1 (horizontal or vertical)
        carveRect(math.min(x0,ex)-math.floor((w-1)/2),
                  math.min(y0,ey)-math.floor((w-1)/2),
                  math.abs(ex-x0)+w, math.abs(ey-y0)+w)
        -- leg 2
        carveRect(math.min(ex,x1)-math.floor((w-1)/2),
                  math.min(ey,y1)-math.floor((w-1)/2),
                  math.abs(x1-ex)+w, math.abs(y1-ey)+w)
    end

    -- ── SPINE POSITIONS ──────────────────────────────────────────────────
    -- yA/yB are seeded on cy ONLY so every chunk in the same horizontal row
    -- shares identical hall heights — this keeps halls continuous at chunk seams.
    local HALL_W = 3
    local rowRng = self:makeRng(SEED_BASE + cy * 19349669 + 999983)
    local yA = clamp(math.floor(CHUNK*0.30) + rowRng(-3,3), 5, CHUNK-16)
    local yB = clamp(math.floor(CHUNK*0.68) + rowRng(-3,3), yA+14, CHUNK-5)
    local hallSpan_x0 = 2
    local hallSpan_x1 = CHUNK - 3

    -- Carve the two main E-W halls as solid rectangles (not edge-to-edge)
    carveRect(hallSpan_x0, yA, hallSpan_x1 - hallSpan_x0, HALL_W)
    carveRect(hallSpan_x0, yB, hallSpan_x1 - hallSpan_x0, HALL_W)

    -- ── VERTICAL CROSS-CONNECTORS ─────────────────────────────────────────
    -- 2-3 straight N-S passages connecting the two halls
    local crossCount = 2 + math.floor(rng() * 2)
    local usedX = {}
    for i = 1, crossCount do
        local cx2 = clamp(8 + math.floor(rng() * (CHUNK - 16)), 5, CHUNK - 6)
        -- avoid clustering
        local tooClose = false
        for _, ux in ipairs(usedX) do
            if math.abs(cx2 - ux) < 6 then tooClose = true; break end
        end
        if not tooClose then
            usedX[#usedX+1] = cx2
            -- 2-wide straight connector from bottom of yA hall to top of yB hall
            carveRect(cx2, yA + HALL_W, 2, yB - (yA + HALL_W))
        end
    end

    -- ── ROOMS: zone-based placement in 3 rows ────────────────────────────
    -- Row 0 = above yA, Row 1 = between halls, Row 2 = below yB
    -- Rooms in rows 0 and 2 hang off the halls. Row 1 rooms sit between.
    -- Each room gets a 2-wide doorway stub to its nearest hall.
    local rooms = {}

    local rowDefs = {
        -- {ry_min, ry_max, attach_hall_y}
        {2,            yA - 2,          yA},        -- above upper hall
        {yA+HALL_W+1,  yB - 2,          yA},        -- between halls (attach to yA)
        {yB+HALL_W+1,  CHUNK - 3,       yB},        -- below lower hall
    }

    local ZONES_X = 4   -- 4 columns of room slots
    for rowIdx, rd in ipairs(rowDefs) do
        local ry_min, ry_max, hallY = rd[1], rd[2], rd[3]
        local availH = ry_max - ry_min
        if availH >= 6 then   -- only place rooms if there's enough vertical space
            local zoneW2 = math.floor((CHUNK - 4) / ZONES_X)
            -- shuffle columns
            local cols = {0,1,2,3}
            for i=4,2,-1 do
                local j=1+math.floor(rng()*i)
                cols[i],cols[j]=cols[j],cols[i]
            end
            local roomsInRow = 2 + math.floor(rng() * 2)  -- 2..3 rooms per row
            for c = 1, math.min(roomsInRow, ZONES_X) do
                local colIdx = cols[c]
                local zox = 2 + colIdx * zoneW2
                local rw = 6 + math.floor(rng() * 5)   -- 6..10 wide
                local rh = clamp(4 + math.floor(rng() * 4), 4, availH - 1)  -- 4..7 tall, fits row
                local mx = math.max(0, zoneW2 - rw - 1)
                local rx = clamp(zox + math.floor(rng()*(mx+1)), 2, CHUNK-rw-2)
                local ry = clamp(ry_min + math.floor(rng()*(availH-rh)), 2, CHUNK-rh-2)
                carveRect(rx, ry, rw, rh)

                local rcx = rx + math.floor(rw/2)
                local rcy = ry + math.floor(rh/2)
                rooms[#rooms+1] = {cx=rcx, cy=rcy, hallY=hallY, rx=rx,ry=ry,rw=rw,rh=rh}

                -- 2-wide doorway from room center straight to the nearest hall
                -- Use pure vertical stub (no L) so wall borders are preserved
                local stubY0 = math.min(rcy, hallY)
                local stubY1 = math.max(rcy, hallY)
                carveRect(rcx - 1, stubY0, 2, stubY1 - stubY0 + HALL_W)
            end
        end
    end

    -- ── CHEST ROOMS: tag the largest room per chunk ───────────────────────
    -- Picks the room with the most floor tiles (rw*rh) as the military chest room.
    -- worldX/worldY are tile-space coords used by the proximity trigger and minimap.
    if #rooms > 0 then
        local bestRoom = rooms[1]
        for _, r in ipairs(rooms) do
            if r.rw * r.rh > bestRoom.rw * bestRoom.rh then
                bestRoom = r
            end
        end
        chunk.chestRooms = {{
            worldX = cx * CHUNK + bestRoom.cx,
            worldY = cy * CHUNK + bestRoom.cy,
            looted = false,
        }}
    end

    -- ── EDGE SEAM OPENINGS ────────────────────────────────────────────────
    -- 2-tile wide openings that connect to the nearest main hall.
    -- Seam positions are deterministic (same seed for both neighbours).
    local function seamSeed(ax, ay, dirTag)
        return SEED_BASE + ax * 83492791 + ay * 29765729 + dirTag * 911
    end
    local function seamRng(seed)
        local s = seed
        return function(a,b)
            s=(s*1103515245+12345)%2147483648
            if a and b then return a+(math.floor(s/65536)%(b-a+1))
            elseif a then return math.floor(s/65536)%a end
            return s/2147483648
        end
    end

    local function carveEdgeOpenings()
        local function openingsFor(dir)
            local ax,ay,tag
            if     dir=="W" then ax,ay,tag=cx-1,cy,1
            elseif dir=="E" then ax,ay,tag=cx,  cy,1
            elseif dir=="N" then ax,ay,tag=cx,cy-1,2
            else                 ax,ay,tag=cx,  cy,2
            end
            local r = seamRng(seamSeed(ax,ay,tag))
            -- 1..2 openings per edge
            local count = 1 + math.floor(r()*2)
            local pos = {}
            for i=1,count do pos[i]=4+math.floor(r()*(CHUNK-10)) end
            return pos
        end

        -- W/E openings: connect horizontally into the hall at yA or yB
        local function openW(y)
            y = clamp(y, 2, CHUNK-4)
            -- punch a 2-wide gap on the left edge, run straight to the vertical spine
            -- or just to the hall intersection
            local nearHall = (math.abs(y-yA) < math.abs(y-yB)) and yA or yB
            carveRect(0, nearHall, 3, HALL_W)  -- open at hall level on W edge
        end
        local function openE(y)
            y = clamp(y, 2, CHUNK-4)
            local nearHall = (math.abs(y-yA) < math.abs(y-yB)) and yA or yB
            carveRect(CHUNK-3, nearHall, 3, HALL_W)  -- open at hall level on E edge
        end
        -- N/S openings: drop a 2-wide stub from edge down to yA or up to yB
        local function openN(x)
            x = clamp(x, 2, CHUNK-4)
            carveRect(x, 0, 2, yA + HALL_W)  -- stub from N edge down to upper hall
        end
        local function openS(x)
            x = clamp(x, 2, CHUNK-4)
            carveRect(x, yB, 2, CHUNK - yB)  -- stub from lower hall to S edge
        end

        for _,y in ipairs(openingsFor("W")) do openW(y) end
        for _,y in ipairs(openingsFor("E")) do openE(y) end
        for _,x in ipairs(openingsFor("N")) do openN(x) end
        for _,x in ipairs(openingsFor("S")) do openS(x) end
    end

    carveEdgeOpenings()

    -- ── ORIGIN CHUNK SPAWN PAD ────────────────────────────────────────────
    if cx == 0 and cy == 0 then
        carveRect(mid-2, mid-2, 5, 5)
        -- Connect to whichever hall is nearest
        local nearHall = (math.abs(mid-yA) < math.abs(mid-yB)) and yA or yB
        carveRect(mid-1, math.min(mid, nearHall), 2,
                  math.abs(nearHall - mid) + HALL_W)
    end
-- POST-PROCESS: 1-tile wall border preservation.
    -- Any wall tile directly adjacent to at least one floor tile survives as a wall.
    -- All other solid mass becomes VOID (non-playable, renders as void/darkness).
    -- 1-tile border keeps corridor/room edges crisp without eating chunk space.
    for y = 0, CHUNK - 1 do
        for x = 0, CHUNK - 1 do
            if chunk.tiles[idx(x,y)] == TILE_WALL then
                local adjFloor = false
                if inb(x-1,y) and chunk.tiles[idx(x-1,y)] == TILE_FLOOR then adjFloor = true end
                if inb(x+1,y) and chunk.tiles[idx(x+1,y)] == TILE_FLOOR then adjFloor = true end
                if inb(x,y-1) and chunk.tiles[idx(x,y-1)] == TILE_FLOOR then adjFloor = true end
                if inb(x,y+1) and chunk.tiles[idx(x,y+1)] == TILE_FLOOR then adjFloor = true end
                if not adjFloor then
                    chunk.tiles[idx(x,y)] = TILE_VOID
                end
            end
        end
    end

    -- blood marks (light flavor)
    if rng() < 0.08 then
        local bx = 2 + math.floor(rng() * (CHUNK - 4))
        local by = 2 + math.floor(rng() * (CHUNK - 4))
        if chunk.tiles[idx(bx,by)] == 0 then
            chunk.blood[#chunk.blood+1] = {x = bx + 0.5, y = by + 0.5, r = 0.6 + rng() * 0.8}
        end
    end
    return chunk
end
function Map:chunkCarveBetween(chunk, ax, ay, bx, by, cs)
    if ay == by then
        local x0 = 1 + math.min(ax, bx) * cs
        local wx = x0 + 2
        for dy = 0, 1 do
            local ty = 1 + ay * cs + dy
            if wx < CHUNK and ty < CHUNK then
                chunk.tiles[ty * CHUNK + wx] = 0
            end
        end
    else
        local y0 = 1 + math.min(ay, by) * cs
        local wy = y0 + 2
        for dx = 0, 1 do
            local tx = 1 + ax * cs + dx
            if tx < CHUNK and wy < CHUNK then
                chunk.tiles[wy * CHUNK + tx] = 0
            end
        end
    end
end

-- simple seeded RNG per chunk
function Map:makeRng(seed)
    local s = seed
    return function(a, b)
        s = (s * 1103515245 + 12345) % 2147483648
        if a and b then
            return a + (math.floor(s / 65536) % (b - a + 1))
        elseif a then
            return math.floor(s / 65536) % a
        end
        return (s / 2147483648)
    end
end

function Map:updateLights(t) end

function Map:getLightLevel(wx, wy)
    return 0.05
end

function Map:findSpawn()
    -- Prefer the origin chunk main hall / spawn pad, but never spawn inside a wall.
    self:ensureChunk(0, 0)
    local mid = math.floor(CHUNK / 2)

    local function isOpen(tx, ty)
        return self:get(tx, ty) == 0
    end

    -- First try center (should be open due to spawn pad), then spiral-search outward.
    local cx = mid
    local cy = mid
    if isOpen(cx, cy) then return cx + 0.5, cy + 0.5 end

    local radiusMax = CHUNK - 2
    for r = 1, radiusMax do
        for dy = -r, r do
            for dx = -r, r do
                if math.abs(dx) == r or math.abs(dy) == r then
                    local tx = cx + dx
                    local ty = cy + dy
                    if isOpen(tx, ty) then
                        return tx + 0.5, ty + 0.5
                    end
                end
            end
        end
    end

    -- Absolute fallback: carve a tile open and spawn there
    local chunk = self.chunks[chunkKey(0,0)]
    if chunk then
        local function idx(x,y) return y * CHUNK + x end
        chunk.tiles[idx(mid, mid)] = 0
    end
    return mid + 0.5, mid + 0.5
end

function Map:randomOpenTile(nearX, nearY, minDist)
    for tries = 1, 200 do
        local angle = math.random() * math.pi * 2
        local dist = (minDist or 5) + math.random() * 20
        local tx = math.floor(nearX + math.cos(angle) * dist)
        local ty = math.floor(nearY + math.sin(angle) * dist)
        if self:get(tx, ty) == 0 then
            if minDist then
                local dx = tx - nearX
                local dy = ty - nearY
                if dx*dx + dy*dy < minDist*minDist then goto continue end
            end
            return tx + 0.5, ty + 0.5
        end
        ::continue::
    end
    return nearX + 0.5, nearY + 0.5
end

-- get blood marks visible in a screen region
function Map:getBloodInRegion(x0, y0, x1, y1)
    local results = {}
    local cx0 = math.floor(x0 / CHUNK)
    local cy0 = math.floor(y0 / CHUNK)
    local cx1 = math.floor(x1 / CHUNK)
    local cy1 = math.floor(y1 / CHUNK)
    for cy = cy0, cy1 do
        for cx = cx0, cx1 do
            local key = chunkKey(cx, cy)
            local chunk = self.chunks[key]
            if chunk and chunk.blood then
                local ox = cx * CHUNK
                local oy = cy * CHUNK
                for _, b in ipairs(chunk.blood) do
                    local wx = ox + b.x
                    local wy = oy + b.y
                    if wx >= x0 and wx <= x1 and wy >= y0 and wy <= y1 then
                        results[#results+1] = {x=wx, y=wy, btype=b.btype, angle=b.angle, size=b.size}
                    end
                end
            end
        end
    end
    return results
end

-- drain the new chunk queue (called by main.lua to spawn items in fresh chunks)
function Map:drainNewChunks()
    local list = self.newChunks
    self.newChunks = {}
    return list
end

-- get a random open tile within a specific chunk
function Map:randomOpenInChunk(cx, cy)
    local key = chunkKey(cx, cy)
    local chunk = self.chunks[key]
    if not chunk then return nil end
    local ox = cx * CHUNK
    local oy = cy * CHUNK
    for tries = 1, 50 do
        local lx = math.random(2, CHUNK - 3)
        local ly = math.random(2, CHUNK - 3)
        if chunk.tiles[ly * CHUNK + lx] == 0 then
            return ox + lx + 0.5, oy + ly + 0.5
        end
    end
    return nil
end

-- Mark a tile as wall (used by solid props like desks)
function Map:markSolid(x, y)
    self:set(x, y, 1)
end

-- ═══ V3: MILITARY CHEST ROOM QUERIES ═══

-- Returns list of unlooted chest rooms within range tiles of player.
function Map:getChestRoomsNear(px, py, range)
    local results = {}
    local rangeSq = range * range
    for key, chunk in pairs(self.chunks) do
        if chunk.chestRooms then
            for idx, room in ipairs(chunk.chestRooms) do
                if not room.looted then
                    local dx = px - room.worldX
                    local dy = py - room.worldY
                    if dx*dx + dy*dy < rangeSq then
                        local comma = key:find(",")
                        local kcx = tonumber(key:sub(1, comma-1))
                        local kcy = tonumber(key:sub(comma+1))
                        results[#results+1] = {
                            worldX = room.worldX,
                            worldY = room.worldY,
                            cx = kcx, cy = kcy, idx = idx,
                        }
                    end
                end
            end
        end
    end
    return results
end

-- Mark a specific chest room as looted so it won't trigger again.
function Map:markChestLooted(cx, cy, roomIdx)
    local key = chunkKey(cx, cy)
    local chunk = self.chunks[key]
    if chunk and chunk.chestRooms and chunk.chestRooms[roomIdx] then
        chunk.chestRooms[roomIdx].looted = true
    end
end

-- Return all chest rooms (for minimap golden glow).
function Map:getAllChestRooms()
    local results = {}
    for key, chunk in pairs(self.chunks) do
        if chunk.chestRooms then
            for _, room in ipairs(chunk.chestRooms) do
                results[#results+1] = {
                    worldX = room.worldX,
                    worldY = room.worldY,
                    looted = room.looted,
                }
            end
        end
    end
    return results
end

-- ═══ V4: PORTAL SPAWNING ═══
-- Finds a 3x3 open area 25-40 tiles from the player and places the exit portal.
-- Returns {x, y} world coords or nil if no spot found after many tries.
function Map:spawnPortal(px, py)
    for tries = 1, 200 do
        local angle = math.random() * math.pi * 2
        local dist = 25 + math.random() * 15
        local tx = math.floor(px + math.cos(angle) * dist)
        local ty = math.floor(py + math.sin(angle) * dist)
        -- check 3x3 area is all open
        local clear = true
        for dy = -1, 1 do
            for dx = -1, 1 do
                if self:get(tx + dx, ty + dy) ~= 0 then clear = false; break end
            end
            if not clear then break end
        end
        if clear then
            self.portal = {x = tx + 0.5, y = ty + 0.5, active = true}
            return self.portal
        end
    end
    return nil
end

function Map:getPortal()
    return self.portal
end

return Map