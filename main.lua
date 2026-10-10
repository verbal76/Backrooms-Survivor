-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║ BACKROOMS SURVIVOR — main.lua                                       ║
-- ║ LÖVE2D horror survival game                                         ║
-- ║                                                                     ║
-- ║ FILE MAP (search these headers to jump to sections):                ║
-- ║                                                                     ║
-- ║   SEC 1:  REQUIRES & GLOBALS ............. modules + variables      ║
-- ║   SEC 2:  GAME CONFIG & TUNING ........... tileSize, charScale etc  ║
-- ║   SEC 3:  STORY TEXT ..................... intro scroll lines       ║
-- ║   SEC 4:  NAME ENTRY STATE ............... on-screen keyboard       ║
-- ║   SEC 5:  love.load() .................... startup, fonts, sounds   ║
-- ║   SEC 6:  startGame / restartGame ........ creates game objects     ║
-- ║   SEC 7:  love.update(dt) ................ main game loop           ║
-- ║   SEC 8:  INPUT HANDLERS ................. keys, gamepad, touch     ║
-- ║   SEC 9:  TITLE SCREEN LOGIC ............ menu navigation          ║
-- ║   SEC 10: PAUSE MENU LOGIC .............. slider adjustments       ║
-- ║   SEC 11: KILL / MESSAGE HELPERS ......... XP, drops, messages     ║
-- ║   SEC 12: LIGHTING SYSTEM ................ headlamp, shadows       ║
-- ║   SEC 13: love.draw() DISPATCHER ......... routes to screens       ║
-- ║   SEC 14: SCREEN DRAWS ................... story, title, etc       ║
-- ║   SEC 15: MAP / ITEM / ORB DRAWING ....... tiles, pickups, orbs    ║
-- ║   SEC 16: ENEMY DRAWING .................. slenderman entities     ║
-- ║   SEC 17: BULLET DRAWING ................. projectile rendering    ║
-- ║   SEC 18: PLAYER DRAWING ................. hazmat suit character    ║
-- ║   SEC 19: HUD ............................ health bars, ammo, etc  ║
-- ║   SEC 20: STATUS HUD .................... Y-button full stats     ║
-- ║   SEC 21: MINIMAP ........................ bottom-right corner     ║
-- ╚══════════════════════════════════════════════════════════════════════╝

-- main.lua
-- Backrooms Survivor - LÖVE2D
-- One life survival, days counter (5 min = 1 day)

-- ═══ SEC 1: REQUIRES — all game modules ═══
-- === Per-slot stats ticker helpers ===
-- Global on purpose so drawCharSelect can always call them.
function buildSaveStatsTicker(summary)
    if not summary then return "" end
    return "Best Kills: "..(summary.bestKills or 0)..
        " | Best Streak: "..(summary.bestStreak or 0)
end
function drawRowTicker(text, x, y, w, h, speed, phase)
    if not text or text == "" then return end
    love.graphics.setScissor(x, y, w, h)
    local font = love.graphics.getFont()
    local tw = font:getWidth(text)
    local gap = 40
    local t = love.timer.getTime()
    local offset = -(((t * speed) + (phase or 0)) % (tw + gap))
    love.graphics.print(text, x + offset, y)
    love.graphics.print(text, x + offset + tw + gap, y)
    love.graphics.setScissor()
end

local Map = require("map")
local Player = require("player")
local Weapons = require("weapons")
local Enemies = require("enemies")
local Orbs = require("orbs")
local Items = require("items")
local Input = require("input")
local Music = require("music")
local Bomb = require("bomb")
local Options = require("options")
local EnemySounds = require("enemysounds")
local Props = require("props")
local Progression = require("progression")

-- ═══ SEC 2: GLOBALS & GAME CONFIG — tweak these for game feel ═══
local wallTopImg   -- wood-grain texture for skinny walls
local map, player, weapons, enemies, orbs, items, input, music, bomb, options, enemySounds
local props          -- environmental objects (furniture, bodies, clutter)
local progression    -- persistent meta-upgrades between runs
local tokensEarned = 0  -- tokens earned from last death (for death screen display)
local camera = {x = 0, y = 0}
local tileSize = 52  -- <<<< ZOOM: higher = closer camera, bigger map tiles
-- ╔══════════════════════════════════════════════════════════════╗
-- ║ CHARACTER SCALE — controls how big player + enemies appear  ║
-- ║ Characters were drawn for tileSize=24, so at 52 they need  ║
-- ║ ~2.17x magnification. Change this one number to resize ALL  ║
-- ║ characters, bullets, and visual effects proportionally.     ║
-- ╚══════════════════════════════════════════════════════════════╝
local charScale = tileSize / 24  -- <<<< MASTER CHARACTER SIZE (change to resize everything)
-- ╔══════════════════════════════════════════════════════════════╗
-- ║ PER-CHARACTER SCALING — multiply on top of charScale        ║
-- ║ 1.0 = normal, 1.5 = 50% bigger, 0.75 = 25% smaller        ║
-- ║ Final size = charScale * characterMult * (enemy type size)  ║
-- ╚══════════════════════════════════════════════════════════════╝
local playerScale   = 2.0  -- <<<< PLAYER SIZE multiplier (just the player character)
-- (enemy scale multipliers are now in enemies.lua type table, field: scale)
local bulletScale   = .85  -- <<<< BULLET SIZE multiplier

-- ╔══════════════════════════════════════════════════════════════╗
-- ║ SPRITESHEET SYSTEM — auto-loads player_spritesheet.png      ║
-- ║ If the file exists, uses it instead of procedural drawing.  ║
-- ║ Generate with RENDER_SPRITESHEET.bat + any 3D model.        ║
-- ╚══════════════════════════════════════════════════════════════╝
local playerSprite = nil       -- the loaded spritesheet image
local playerSpriteQuads = {}   -- array of quads, one per angle
local playerSpriteFrames = 16  -- how many rotation frames in the sheet
local playerSpriteSize = 128   -- pixel size of each frame
local useSprite = false        -- true when spritesheet is loaded

-- Enemy spritesheets (same system, one per enemy type)
-- Place these PNGs in the game folder to replace procedural enemies:
--   enemy_hound_spritesheet.png
--   enemy_crawler_spritesheet.png
--   enemy_wretch_spritesheet.png
--   enemy_shade_spritesheet.png
--   enemy_skinstealer_spritesheet.png
local enemySprites = {}  -- table: enemySprites["hound"] = {img, quads, frames, size}

-- Weapon sprites (optional, place in weapons/ folder)
-- Each PNG faces right (0°), game rotates to match aim direction
-- Replace any PNG to customize: weapons/machete.png, weapons/knife.png, etc.
local weaponSprites = {}  -- table: weaponSprites[weaponIdx] = image

-- ╔══════════════════════════════════════════════════════════════╗
-- ║ ENEMY SPRITE ROTATION TUNING                              ║
-- ║ Enemy spritesheets may be rotated vs movement math.        ║
-- ║ Adjust this offset to align enemy facing frames.           ║
-- ║  0 = no change                                             ║
-- ║  math.pi/2 = 90° clockwise                                 ║
-- ║  -math.pi/2 = 90° counterclockwise                         ║
-- ║  math.pi = 180° flip                                       ║
-- ╚══════════════════════════════════════════════════════════════╝
local ENEMY_SPRITE_ANGLE_OFFSET = -math.pi / 2  -- <<<< TUNE ME: start at -90°, adjust if needed

local kills = 0
local wave = 1
local gameTime = 0

-- ═══ V3-V5: FEATURE STATE (bundled to stay under Lua's 60 upvalue limit) ═══
local FS = {
    -- perk choice
    perkChoices = nil,          -- {perk1, perk2} table when player is choosing
    perkSelection = 1,          -- 1 or 2, which perk card is highlighted
    perkChoiceActive = false,   -- true = game paused for perk pick
    -- military chests
    CHEST_DETECT_RANGE = 10,    -- tiles from chest center to trigger swarm + loot
    CHEST_SWARM_COUNT = 12,      -- enemies spawned per chest encounter
    -- portal & victory
    PORTAL_DAY = 30,            -- day the exit portal spawns
    PORTAL_HORDE_SIZE = 15,     -- enemies guarding the portal
    PORTAL_INTERACT_DIST = 2,   -- tiles from portal center to interact
    portalSpawned = false,      -- true once portal has been placed
    portalPromptActive = false, -- true = showing escape/stay prompt
    portalPromptChoice = 1,     -- 1 = escape, 2 = stay
    victoryActive = false,      -- true = showing victory screen
    victoryTokens = 0,          -- tokens earned with victory bonus
    portalMsgCooldown = 0,      -- rate-limit "hostiles remain" messages
}
local dayLength = 120  -- <<<< seconds per day (2 min), shorter = harder
local diffSpawnScale = 1.0  -- <<<< difficulty spawn speed multiplier (set in startGame)
local diffMaxEnemyCap = 80  -- <<<< difficulty max enemy ceiling (set in startGame)
local messages = {}
local gameOver = false
local paused = false
local pauseSelection = 1
local deathSelection = 1
local deathItems = {"Retry", "Upgrades", "Main Menu"}
local pauseItems = {"Music Volume", "Enemy Sounds", "Brightness", "Headlamp", "Aim Assist", "Resume", "Options", "Quit to Menu"}
local lightCanvasSmall  -- smaller canvas for smooth lighting
local aimAssist = true  -- auto-aim at nearest enemy when right stick idle
local HEADLAMP_RADIUS = 14  -- <<<< headlamp reach in tiles
local HEADLAMP_CONE = 0.85  -- <<<< beam width in radians (higher = wider)
local PLAYER_SPRITE_ANGLE_OFFSET = -math.pi / 2  -- <<<< FIX: rotate player sprite 90° counterclockwise to match world facing
local HEADLAMP_ANGLE_OFFSET = 0  -- <<<< FIX: rotate headlamp 180° total (90° more CCW) so cone matches weapon/sprite
local HEADLAMP_FORWARD_OFFSET = 0.18       -- <<<< FIX: beam origin forward from player center (tiles). Increase to reduce 'shoulder' feel
local AMBIENT = 0.15  -- <<<< base light level (overridden by difficulty)  -- will be set by difficulty
local headlampOn = true

-- battery system
local headlampBattery = 100
local headlampBatteryMax = 100
local headlampDrainRate = 0.55    -- <<<< battery drain/sec when on    -- per second when on (~3 min of use)
local headlampRechargeRate = 0.85 -- <<<< battery recharge/sec when off -- per second when off (2x drain rate)
local introTimer = 3.0
local introActive = true
local introAlpha = 1.0

-- difficulty ambient levels: easy=well lit, hell=almost pitch black
local difficultyAmbient = {0.3, 0.2, 0.1, 0.05}  -- <<<< ambient light: Easy/Normal/Worse/Hell

-- fonts
local titleFont = nil      -- big title font
local titleFontHuge = nil   -- huge title font for main screen
local menuFont = nil        -- larger menu font
local storyFont = nil       -- story scroll font (2x default)
local defaultFont = nil
local hudFont = nil       -- small HUD font
local uiScale = 1.0        -- <<<< UI SCALE: auto-calculated from resolution (1.0 = 720p)

-- Rebuilds all fonts based on current window size
-- Called from love.load() and love.resize()
function rebuildFonts()
    local w, h = love.graphics.getDimensions()
local rawScale = h / 720  -- <<<< REFERENCE HEIGHT: everything designed for 720p
-- Pixel-perfect UI: snap to an integer scale to avoid sub-pixel HUD/text rendering
uiScale = math.max(1, math.floor(rawScale + 0.5))
love.graphics.setDefaultFilter("nearest", "nearest")
    local okFont, font = pcall(love.graphics.newFont, "Blackcraft.ttf", math.floor(36 * uiScale))
    if okFont then titleFont = font end
    local okHuge, fontHuge = pcall(love.graphics.newFont, "Blackcraft.ttf", math.floor(64 * uiScale))
    if okHuge then titleFontHuge = fontHuge end
    local okMenu, fontMenu = pcall(love.graphics.newFont, "Blackcraft.ttf", math.floor(22 * uiScale))
    if okMenu then menuFont = fontMenu end
    local okStory, fontStory = pcall(love.graphics.newFont, "Blackcraft.ttf", math.floor(28 * uiScale))
    if okStory then storyFont = fontStory end
    defaultFont = love.graphics.newFont(math.floor(14 * uiScale))
    hudFont = love.graphics.newFont(math.floor(8 * uiScale))

end

-- CRT "bold" helpers (fake bold by overdrawing with 1px offsets)
local function crtPrintBold(text, x, y)
    local o = math.max(1, math.floor(uiScale * 0.75))
    love.graphics.print(text, x + o, y)
    love.graphics.print(text, x, y + o)
    love.graphics.print(text, x + o, y + o)
    love.graphics.print(text, x, y)
end

local function crtPrintfBold(text, x, y, limit, align)
    local o = math.max(1, math.floor(uiScale * 0.75))
    love.graphics.printf(text, x + o, y, limit, align)
    love.graphics.printf(text, x, y + o, limit, align)
    love.graphics.printf(text, x, y, limit, align)
end

-- title screen state
local gameState = "story"  -- story, charselect, nameentry, title, playing, dead
local titleSelection = 1
local deathSelection = 1   -- 1=Try Again, 2=Upgrades, 3=Main Menu
local shopSelection = 1    -- which upgrade is highlighted in shop
local showShop = false      -- overlay shop on death screen
local difficulties = {"Easy", "Normal", "Getting Worse", "Hell"}
local difficultyIdx = 1  -- <<<< DEFAULT DIFFICULTY: 1=Easy, 2=Normal, 3=Worse, 4=Hell
local titleBrightness = 1.0  -- <<<< TITLE BRIGHTNESS default (0-1, starts maxed)

-- ═══ CHARACTER SELECT STATE ═══
local charSelectIdx = 1       -- highlighted slot (1..N+1 where N+1 = "New Character")
local charSelectDelete = false -- delete confirmation mode
local charSelectDeleteIdx = 0  -- which character is pending delete
local uiMusicSource = nil
local heartbeatSource = nil
local heartbeatBaseVol = 4.0   -- <<<< heartbeat vol at full stamina (>1.0 = amplified)
local heartbeatMaxVol = 6.0    -- <<<< heartbeat vol at zero stamina
local gunshotSource = nil       -- loaded from sounds/gunshot_sound.mp3 (pistol, suppressed)
local shotgunSource = nil       -- loaded from sounds/shotgun_sound.mp3
local smgSource = nil           -- loaded from sounds/smg_sound.mp3
local swingSource = nil         -- loaded from sounds/swing_sound.mp3 (all melee)
local whisperMale = nil         -- loaded from sounds/male_whispers.mp3
local whisperFemale = nil       -- loaded from sounds/female_whispers.mp3
local whisperCrossfade = 0      -- 0-1 timer for crossfading whispers
local whisperCrossfadeDir = 1   -- 1 = fading to female, -1 = fading to male
local whisperCrossfadeSpeed = 0.12 -- speed of crossfade oscillation

-- player name
local playerName = ""
-- ╔══════════════════════════════════════════════════════════════╗
-- ║ SUIT COLOR PALETTES — selected on character select screen    ║
-- ║ Each palette: {suit, suitDark, hood, belt, gloves, name}    ║
-- ║ Add new colors by copying a row and changing the RGB values  ║
-- ╚══════════════════════════════════════════════════════════════╝
local suitPalettes = {
    {suit={0.85,0.78,0.15}, suitDark={0.65,0.58,0.10}, hood={0.90,0.83,0.20}, belt={0.13,0.13,0.11}, gloves={0.10,0.10,0.08}, name="STANDARD YELLOW"},
    {suit={0.90,0.90,0.88}, suitDark={0.70,0.70,0.68}, hood={0.95,0.95,0.93}, belt={0.20,0.20,0.20}, gloves={0.15,0.15,0.13}, name="DECON WHITE"},
    {suit={0.90,0.50,0.10}, suitDark={0.70,0.35,0.05}, hood={0.95,0.55,0.15}, belt={0.15,0.10,0.05}, gloves={0.10,0.10,0.08}, name="HAZMAT ORANGE"},
    {suit={0.25,0.50,0.80}, suitDark={0.15,0.35,0.60}, hood={0.30,0.55,0.85}, belt={0.10,0.10,0.15}, gloves={0.08,0.08,0.12}, name="RESEARCH BLUE"},
    {suit={0.30,0.55,0.25}, suitDark={0.20,0.40,0.15}, hood={0.35,0.60,0.30}, belt={0.12,0.12,0.08}, gloves={0.08,0.10,0.06}, name="FIELD GREEN"},
    {suit={0.75,0.15,0.15}, suitDark={0.55,0.10,0.10}, hood={0.80,0.20,0.20}, belt={0.15,0.08,0.08}, gloves={0.12,0.08,0.08}, name="EMERGENCY RED"},
}
local suitColorIdx = 1  -- <<<< selected suit color (1-6)

-- story scroll state
Story = Story or { scrollY = 0, speed = 55, holdSeconds = 5, holdTimer = 0, inited = false }
-- ═══ SEC 3: STORY TEXT — edit lines to change intro scroll ═══
local storyLines = {
    "",
    "",
    "ASYNC RESEARCH LABORATORIES",
    "PROJECT: THRESHOLD",
    "CLASSIFICATION: LEVEL 5 - RESTRICTED",
    "",
    "Date: [REDACTED]",
    "Subject: Incident Report #4031-B",
    "",
    "You are a data collection specialist assigned to",
    "Async Research Lab's experimental spatial anomaly",
    "division. Your team has been studying unstable",
    "regions where physical reality appears to break",
    "down, areas the research team calls 'no-clip zones.'",
    "",
    "The Backrooms are a vast network of liminal spaces",
    "that exist behind the thin membrane of reality.",
    "Approximately 600 million square miles of empty,",
    "yellowed rooms, damp carpet, and buzzing",
    "fluorescent lights stretching on forever.",
    "",
    "The spaces feel familiar. Hallways you have walked",
    "before. Offices where someone should be sitting.",
    "But no one is here. No one has been here for a",
    "very long time. The absence of people is so total",
    "it feels like a presence of its own.",
    "",
    "There is a smell. Wet carpet. Old insulation.",
    "Something rotting just beyond the next corner.",
    "The hum of the lights is constant, maddening.",
    "Researchers believe the monotonous yellow hue",
    "of the walls accelerates psychological decay.",
    "",
    "Your team was testing a generated no-clip doorway",
    "in Lab 7-C, a controlled portal designed to allow",
    "brief excursions into the Backrooms for data",
    "collection. You stepped through as you had done",
    "twelve times before.",
    "",
    "But this time the door malfunctioned.",
    "",
    "The portal collapsed behind you. The steady green",
    "light of the lab flickered, turned red, and",
    "vanished. You heard your team shouting on the",
    "other side, their voices growing distant, then",
    "gone entirely.",
    "",
    "You are alone.",
    "",
    "The Backrooms are not empty. Things live here.",
    "Entities that have never seen daylight. Things",
    "that hunt by sound. Things that fear light.",
    "Things with no face and too many arms.",
    "",
    "Your headlamp battery will not last forever.",
    "Your sanity will erode in the darkness.",
    "Dehydration will set in. Hunger. Exhaustion.",
    "",
    "But there is hope.",
    "",
    "Async's emergency protocols include exit portals",
    "hidden deep within the Backrooms. Find one.",
    "Survive long enough to reach it.",
    "",
    "No one is coming for you.",
    "There is no saving. There is no loading.",
    "Only survival.",
    "",
    "",
    "[ Press A or ENTER to continue ]",
    "",
    "",
}

-- ═══ SEC 4: NAME ENTRY STATE — on-screen keyboard layout ═══
local nameKbRow = 1
local nameKbCol = 1
local nameKbRows = {
    {"A","B","C","D","E","F","G","H","I","J"},
    {"K","L","M","N","O","P","Q","R","S","T"},
    {"U","V","W","X","Y","Z","0","1","2","3"},
    {"4","5","6","7","8","9","-","_","DEL","OK"},
}

local function getNameEntryLayout(w, h)
    local s = uiScale
    local border = math.floor(30 * s)
    local cx = w / 2

    -- keyboard sizing
    local keyW  = math.floor(32 * s)
    local keyH  = math.floor(28 * s)
    local keyPad = math.floor(4 * s)
    local kbTotalW = #nameKbRows[1] * (keyW + keyPad) - keyPad
    local kbTotalH = #nameKbRows     * (keyH + keyPad) - keyPad
    local kbStartX = cx - kbTotalW / 2

    -- name box sizing
    local boxW = math.floor(300 * s)
    local boxH = math.floor(36 * s)
    local boxX = cx - boxW / 2

    -- vertical layout (stacked)
    local yTitle      = 0
    local ySep        = math.floor(22 * s)
    local yLine1      = math.floor(50 * s)
    local yLine2      = math.floor(74 * s)
    local yBox        = math.floor(115 * s)
    local yKb         = math.floor(165 * s)
    local yInstr      = yKb + kbTotalH + math.floor(36 * s)

    -- compute actual content height + a little padding
    local contentH = yInstr + math.floor(24 * s)

    -- center, but don’t crash into the border
    local baseY = math.floor((h - contentH) / 2)
    baseY = math.max(baseY, border + math.floor(10 * s))

    return {
        s=s, border=border, cx=cx, baseY=baseY,
        boxX=boxX, boxY=baseY + yBox, boxW=boxW, boxH=boxH,
        keyW=keyW, keyH=keyH, keyPad=keyPad,
        kbStartX=kbStartX, kbStartY=baseY + yKb,
        yTitle=baseY + yTitle, ySep=baseY + ySep, yLine1=baseY + yLine1, yLine2=baseY + yLine2,
        yInstr=baseY + yInstr
    }
end

-- ═══ THUMBSTICK CONTINUOUS MENU NAVIGATION ═══
-- Works for name entry, title menu, and pause menu.
-- Both left stick and right stick can navigate.
-- Repeats while held: first move instant, then repeats at menuRepeatRate.
local menuStickX = 0       -- current stick X deflection
local menuStickY = 0       -- current stick Y deflection
local menuRepeatTimer = 0  -- countdown until next repeat
local menuRepeatDelay = 0.35  -- seconds before first repeat
local menuRepeatRate = 0.08   -- seconds between repeats (fast continuous scroll)
local menuStickActive = false -- was stick deflected last frame?

-- ═══ SEC 5: love.load() — runs once at startup ═══
function love.load()
    -- ═══ AUTO-DETECT NATIVE RESOLUTION ═══
    -- Uses borderless fullscreen ("desktop") for seamless fit on any device.
    local dw, dh = love.window.getDesktopDimensions()
    if dw > 0 and dh > 0 then
        local success = love.window.setMode(dw, dh, {
            fullscreen = true,
            fullscreentype = "desktop",  -- borderless, uses native res, no mode switch
            resizable = true,
            vsync = 1,
            minwidth = 640,
            minheight = 480,
            highdpi = false,  -- disable DPI scaling so coords = pixels
        })
        if not success then
            love.window.setMode(math.floor(dw * 0.8), math.floor(dh * 0.8), {
                fullscreen = false,
                resizable = true,
                vsync = 1,
                minwidth = 640,
                minheight = 480,
                highdpi = false,
            })
        end
    end

    -- force resize handling now (setMode inside love.load doesn't fire love.resize)
    local aw, ah = love.graphics.getDimensions()
    local lw = math.ceil(aw / 4)
    local lh = math.ceil(ah / 4)
    lightCanvasSmall = love.graphics.newCanvas(lw, lh)
    lightCanvasSmall:setFilter("linear", "linear")

    love.graphics.setDefaultFilter("nearest", "nearest")

    -- Skinny wall top texture (wood grain)
    -- Textures (optional). If missing, we fall back to simple colors.
    local function tryLoadImage(candidates)
        for _, fname in ipairs(candidates) do
            local ok, img = pcall(love.graphics.newImage, fname)
            if ok and img then return img, fname end
        end
        return nil, nil
    end

    wallTopImg = select(1, tryLoadImage({
        "world_assets/wood_grain.jpg", "world_assets/wood_grain.png",
        "wood_grain.jpg", "wood_grain.png",
        -- legacy fallbacks (safe to keep)
        "wood_wall.jpg", "wood_wall.png",
        "ryanpro-trees-1915251.jpg"
    }))

    floorImg = select(1, tryLoadImage({
        "world_assets/carpet_tile.jpg", "world_assets/carpet_tile.png",
        "carpet_tile.jpg", "carpet_tile.png",
        -- legacy fallbacks (safe to keep)
        "carpet_floor.jpg", "carpet_floor.png",
        "nourison-nourison-essentials-area-rug-yellow-7-x10_media.01.jpg"
    }))


deadAreaImg = select(1, tryLoadImage({
    "world_assets/dead area.png", "world_assets/dead area.jpg",
    "world assets/dead area.png", "world assets/dead area.jpg",
    "dead area.png", "dead area.jpg",
    "dead_area.png", "dead_area.jpg"
}))
if deadAreaImg then deadAreaImg:setWrap("repeat","repeat") end

-- Dead Area shader (VOID tiles): subtle UV warp + pulse (anchored in world space)
if deadAreaImg then
    deadAreaShader = love.graphics.newShader([[
        extern number time;
        extern vec2 cam;        // camera world offset in pixels
        extern number uvScale;  // larger = larger pattern / slower drift

        vec4 effect(vec4 color, Image tex, vec2 texCoord, vec2 screenCoord)
        {
            vec2 worldPos = screenCoord + cam;
            vec2 uv = worldPos / uvScale;

            float t = time;
            float w1 = sin(uv.y * 4.0 + t * 1.6) * 0.035;
            float w2 = cos(uv.x * 3.0 + t * 1.3) * 0.030;
            float w3 = sin((uv.x + uv.y) * 6.0 + t * 0.9) * 0.020;
            uv += vec2(w1 + w3, w2 - w3);

            vec4 texel = Texel(tex, uv);
            float pulse = 0.92 + 0.08 * sin(t * 2.2 + uv.x * 2.0 + uv.y * 1.7);
            texel.rgb *= pulse;

            return texel * color;
        }
    ]])
end


    if wallTopImg then wallTopImg:setWrap("repeat","repeat") end
    if floorImg then floorImg:setWrap("repeat","repeat") end

    -- Prebuild a quad for one tile of the floor texture (uses wrapping)
    if floorImg then
        floorQuad = love.graphics.newQuad(0, 0, tileSize, tileSize, floorImg:getWidth(), floorImg:getHeight())
    end
    love.mouse.setVisible(false)
    math.randomseed(os.time())

    -- fonts
    defaultFont = love.graphics.getFont()
    rebuildFonts()

    input = Input.new()
    options = Options.new()
    music = Music.new()
    enemySounds = EnemySounds.new()

    music:load()
    enemySounds:load("sounds")


    -- load heartbeat sound
    local ok, sndItems = pcall(love.filesystem.getDirectoryItems, "sounds")
    if ok and sndItems then
        for _, file in ipairs(sndItems) do
            if file:lower():find("heartbeat") then
                local ext = file:match("%.(%w+)$")
                if ext and (ext == "wav" or ext == "ogg" or ext == "mp3") then
                    local okLoad, src = pcall(love.audio.newSource, "sounds/" .. file, "static")
                    if okLoad and src then
                        heartbeatSource = src
                        heartbeatSource:setLooping(true)
                        heartbeatSource:setVolume(0)
                        break
                    end
                end
            end
        end
    end

    -- load weapon sounds from sounds/ folder
    -- matches: gunshot_sound, shotgun_sound, smg_sound, swing_sound
    if ok and sndItems then
        for _, file in ipairs(sndItems) do
            local lower = file:lower()
            local ext = file:match("%.(%w+)$")
            if ext and (ext == "wav" or ext == "ogg" or ext == "mp3") then
                local target = nil
                if lower:find("smg_sound") or lower:find("smg sound") then target = "smg"
                elseif lower:find("shotgun_sound") or lower:find("shotgun sound") then target = "shotgun"
                elseif lower:find("gunshot_sound") or lower:find("gunshot sound") then target = "gunshot"
                elseif lower:find("swing_sound") or lower:find("swing sound") then target = "swing"
                end
                if target then
                    local okLoad, src = pcall(love.audio.newSource, "sounds/" .. file, "static")
                    if okLoad and src then
                        src:setLooping(false)
                        if target == "smg" then smgSource = src
                        elseif target == "shotgun" then shotgunSource = src
                        elseif target == "gunshot" then gunshotSource = src
                        elseif target == "swing" then swingSource = src
                        end
                    end
                end
            end
        end
    end

    -- load whisper sounds for low sanity (not volume-sliderable, gameplay cue)
    if ok and sndItems then
        for _, file in ipairs(sndItems) do
            local lower = file:lower()
            local ext = file:match("%.(%w+)$")
            if ext and (ext == "wav" or ext == "ogg" or ext == "mp3") then
                if lower:find("male_whisper") or lower:find("male whisper") then
                    local okLoad, src = pcall(love.audio.newSource, "sounds/" .. file, "static")
                    if okLoad and src then src:setLooping(true); src:setVolume(0); whisperMale = src end
                elseif lower:find("female_whisper") or lower:find("female whisper") then
                    local okLoad, src = pcall(love.audio.newSource, "sounds/" .. file, "static")
                    if okLoad and src then src:setLooping(true); src:setVolume(0); whisperFemale = src end
                end
            end
        end
    end

    -- try to get UI music
    local uiSrc = enemySounds:getUISound()

    -- ═══ SPRITESHEET LOADER — auto-detect player_spritesheet.png ═══
    local spriteOk, spriteImg = pcall(love.graphics.newImage, "player_spritesheet.png")
    if spriteOk and spriteImg then
        playerSprite = spriteImg
        local sheetW = playerSprite:getWidth()
        local sheetH = playerSprite:getHeight()
        playerSpriteSize = sheetH  -- each frame is square, height = frame size
        playerSpriteFrames = math.floor(sheetW / playerSpriteSize)
        playerSpriteQuads = {}
        for i = 0, playerSpriteFrames - 1 do
            playerSpriteQuads[i + 1] = love.graphics.newQuad(
                i * playerSpriteSize, 0,
                playerSpriteSize, playerSpriteSize,
                sheetW, sheetH)
        end
        useSprite = true
        print("[SPRITE] Loaded player_spritesheet.png: " .. playerSpriteFrames .. " frames @ " .. playerSpriteSize .. "px")
    else
        useSprite = false
        print("[SPRITE] No player_spritesheet.png found, using procedural character")
    end

    -- ═══ ENEMY SPRITESHEET LOADER ═══
    local enemySpriteFiles = {
        {name="hound",       file="enemy_hound_spritesheet.png"},
        {name="crawler",     file="enemy_crawler_spritesheet.png"},
        {name="wretch",      file="enemy_wretch_spritesheet.png"},
        {name="shade",       file="enemy_shade_spritesheet.png"},
        {name="skin stealer", file="enemy_skinstealer_spritesheet.png"},
    }
    for _, es in ipairs(enemySpriteFiles) do
        local eOk, eImg = pcall(love.graphics.newImage, es.file)
        if eOk and eImg then
            local sw = eImg:getWidth()
            local sh = eImg:getHeight()
            local fSize = sh
            local fCount = math.floor(sw / fSize)
            local quads = {}
            for i = 0, fCount - 1 do
                quads[i + 1] = love.graphics.newQuad(i * fSize, 0, fSize, fSize, sw, sh)
            end
            enemySprites[es.name] = {img = eImg, quads = quads, frames = fCount, size = fSize}
            print("[SPRITE] Loaded " .. es.file .. ": " .. fCount .. " frames @ " .. fSize .. "px")
        end
    end

    -- ═══ WEAPON SPRITE LOADER ═══
    local weaponSpriteFiles = {
        {idx=1, file="weapons/machete.png"},
        {idx=2, file="weapons/knife.png"},
        {idx=3, file="weapons/pipe.png"},
        {idx=4, file="weapons/axe.png"},
        {idx=5, file="weapons/pistol.png"},
        {idx=6, file="weapons/shotgun.png"},
        {idx=7, file="weapons/smg.png"},
        {idx=8, file="weapons/suppressed_pistol.png"},
    }
    for _, ws in ipairs(weaponSpriteFiles) do
        local wOk, wImg = pcall(love.graphics.newImage, ws.file)
        if wOk and wImg then
            weaponSprites[ws.idx] = wImg
            print("[SPRITE] Loaded " .. ws.file .. ": " .. wImg:getWidth() .. "x" .. wImg:getHeight())
        end
    end
    if uiSrc then
        uiMusicSource = uiSrc:clone()
        uiMusicSource:setLooping(true)
        uiMusicSource:setVolume(options.musicVolume)
        uiMusicSource:play()
    end

    local w, h = love.graphics.getDimensions()
    local lw = math.ceil(w / 4)
    local lh = math.ceil(h / 4)
    lightCanvasSmall = love.graphics.newCanvas(lw, lh)
    lightCanvasSmall:setFilter("linear", "linear")

    love.window.setTitle("Backrooms Survivor")

    -- ═══ PERSISTENT PROGRESSION — load saved upgrade data ═══
    progression = Progression.new()
    -- Save-system sanity check (prints once at startup)
    if love.filesystem and love.filesystem.getSaveDirectory then
        print("Save dir: " .. tostring(love.filesystem.getSaveDirectory()))
        print("Save identity: " .. tostring(love.filesystem.getIdentity()))
    end
    -- Ensure a save exists once we have a progression object (does not wipe existing data)
    if progression and not love.filesystem.getInfo("backrooms_save.dat") then
        progression:save()
    end

    -- ═══ PROPS SPRITE SHEET — load placeholder/real art ═══
    -- Props object is created per-run in startGame(), but sprites load once
    local propsProto = Props.new()
    propsProto:loadSprites()
    Props._sharedSheet = propsProto.spriteSheet
    Props._sharedQuads = propsProto.quads
end

function love.resize(w, h)
    -- recreate all canvases after resolution change (setMode invalidates them)
    local lw = math.ceil(w / 4)
    local lh = math.ceil(h / 4)
    lightCanvasSmall = love.graphics.newCanvas(lw, lh)
    lightCanvasSmall:setFilter("linear", "linear")
    -- rebuild fonts at new scale
    rebuildFonts()
end


-- ═══ PERSISTENCE HOOKS — save on focus loss / quit ═══
function love.focus(focused)
    -- When the window loses focus (alt-tab, click away), persist progression immediately.
    if not focused and progression and progression.save then
        pcall(function() progression:save() end)
    end
end

function love.quit()
    -- Last-chance persistence on exit (alt+F4, close button, etc.)
    if progression and progression.save then
        pcall(function() progression:save() end)
    end
end


-- ═══ SEC 6: GAME START / RESTART — creates all game objects ═══
function startGame()
    -- Persist meta-progression right before a new run starts
    if progression then progression:save() end
    gameState = "playing"
    introActive = true
    introTimer = 3.0
    kills = 0
    wave = 1
    gameTime = 0
    messages = {}
    gameOver = false
    showShop = false
    paused = false
    pauseSelection = 1

    -- Auto-aim is disabled on Getting Worse / Hell
    if difficultyIdx >= 3 then aimAssist = false end

    -- V3: reset perk and chest state
    FS.perkChoices = nil
    FS.perkSelection = 1
    FS.perkChoiceActive = false

    -- V4: reset portal and victory state
    FS.portalSpawned = false
    FS.portalPromptActive = false
    FS.portalPromptChoice = 1
    FS.victoryActive = false
    FS.victoryTokens = 0
    FS.portalMsgCooldown = 0

    -- stop UI music
    if uiMusicSource then uiMusicSource:stop() end

    map = Map.new()
    map:generate()
    local sx, sy = map:findSpawn()
    player = Player.new(sx, sy)
    weapons = Weapons.new()
    enemies = Enemies.new()

    -- DEV: sprite spacing test (single follower enemy, disables normal spawns)
    if Enemies.SPACING_TEST_ENABLED and enemies.enableSpacingTest then
        enemies:enableSpacingTest(map, player)
    end

    -- ═══ DIFFICULTY SCALING — this is where the real teeth are ═══
    -- Easy=1, Normal=2, Getting Worse=3, Hell=4
    local diffEnemyHp    = {1.0, 1.0, 1.35, 1.8}    -- <<<< enemy HP multiplier
    local diffEnemyDmg   = {0.70, 1.20, 1.4,  2.0}    -- <<<< enemy damage multiplier
    local diffEnemySpd   = {1.0, 1.0, 1.10, 1.20}   -- <<<< enemy speed multiplier
    local diffSanityMult = {1.0, 1.0, 1.5,  2.0}    -- <<<< sanity drain multiplier
    local diffHydraMult  = {0.9, 1.0, 1.3,  1.7}    -- <<<< hydration drain multiplier
    local diffSpawnMult  = {1.5, 2.0, 2.5,  3.0}    -- <<<< spawn rate multiplier (higher=faster spawns)
    local diffDayLength  = {120,  120, 120,  120}     -- <<<< seconds per day (longer=easier)
    local diffMaxCap     = {90,   100,  110,   130}     -- <<<< max enemy cap ceiling

    enemies.hpMult  = diffEnemyHp[difficultyIdx]  or 1.0
    enemies.dmgMult = diffEnemyDmg[difficultyIdx] or 1.0
    enemies.spdMult = diffEnemySpd[difficultyIdx] or 1.0
    player.sanityDrain   = player.sanityDrain   * (diffSanityMult[difficultyIdx] or 1.0)
    player.hydrationDrain = player.hydrationDrain * (diffHydraMult[difficultyIdx] or 1.0)
    dayLength = diffDayLength[difficultyIdx] or 300
    diffSpawnScale = diffSpawnMult[difficultyIdx] or 1.0  -- used in update loop
    diffMaxEnemyCap = diffMaxCap[difficultyIdx] or 80     -- used in update loop
    orbs = Orbs.new()
    items = Items.new(difficultyIdx)
    bomb = Bomb.new()
    props = Props.new()
    if Props._sharedSheet then
        props.spriteSheet = Props._sharedSheet
        props.quads = Props._sharedQuads
    end

    -- reset headlamp to base before progression modifies it
    headlampBatteryMax = 100

    -- apply persistent upgrades from progression
    if progression then
        progression:applyToPlayer(difficultyIdx, player)
        progression:applyToWeapons(difficultyIdx, weapons)
        progression:applyToBomb(difficultyIdx, bomb)
        -- headlamp battery bonus
        local lampBonus = progression:getLampBonus(difficultyIdx)
        if lampBonus > 0 then
            headlampBatteryMax = headlampBatteryMax * (1 + lampBonus)
        end
    end

    options.brightness = titleBrightness
    AMBIENT = difficultyAmbient[difficultyIdx] or 0.12
    headlampOn = true
    headlampBattery = headlampBatteryMax

    -- scale initial spawns by difficulty
    local L = Items.LOOT
    items:spawnOnMap(map, player.x, player.y, L.initialItems)
    for i = 1, math.floor(L.initialOrbs * items.dropScale) do
        local ox, oy = map:randomOpenTile(player.x, player.y, 6)
        orbs:spawn(ox, oy)
    end

    enemySounds:stopAll()
    if whisperMale and whisperMale:isPlaying() then whisperMale:stop() end
    if whisperFemale and whisperFemale:isPlaying() then whisperFemale:stop() end
    music:setVolume(options.musicVolume)

    -- start heartbeat
    if heartbeatSource then
        heartbeatSource:setVolume(heartbeatBaseVol)
        heartbeatSource:play()
    end

    -- welcome message
    addMessage(playerName.." has entered the Backrooms", {0.9, 0.8, 0.2})
end

function restartGame()
    gameOver = false
    showShop = false
    startGame()
end

function backToTitle()
    gameState = "title"
    titleSelection = 1
    gameOver = false
    showShop = false
    paused = false
    -- V4: clear victory/portal state
    FS.victoryActive = false
    FS.portalPromptActive = false
    enemySounds:stopAll()
    if heartbeatSource then heartbeatSource:stop() end
    if whisperMale and whisperMale:isPlaying() then whisperMale:stop() end
    if whisperFemale and whisperFemale:isPlaying() then whisperFemale:stop() end
    -- restart UI music
    if uiMusicSource then
        uiMusicSource:setVolume(options.musicVolume)
        uiMusicSource:play()
    end
end

-- ═══ THUMBSTICK + DPAD CONTINUOUS MENU NAVIGATION ═══
-- Reads both left and right sticks, combines with keyboard arrows.
-- First deflection moves immediately, then repeats at menuRepeatRate.
function updateMenuStickNavigation(dt, context)
    local gp = input.gamepad
    if not gp then return end

    -- read both sticks, pick the one with greater deflection
    local lx = gp:getGamepadAxis("leftx") or 0
    local ly = gp:getGamepadAxis("lefty") or 0
    local rx = gp:getGamepadAxis("rightx") or 0
    local ry = gp:getGamepadAxis("righty") or 0
    local sx = math.abs(lx) > math.abs(rx) and lx or rx
    local sy = math.abs(ly) > math.abs(ry) and ly or ry
    local dz = 0.3  -- menu deadzone (slightly higher than gameplay)

    -- also read dpad held state for continuous repeat
    if gp:isGamepadDown("dpleft") then sx = -1 end
    if gp:isGamepadDown("dpright") then sx = 1 end
    if gp:isGamepadDown("dpup") then sy = -1 end
    if gp:isGamepadDown("dpdown") then sy = 1 end

    -- apply deadzone
    if math.abs(sx) < dz then sx = 0 end
    if math.abs(sy) < dz then sy = 0 end

    -- determine desired direction
    local dirX = sx > 0 and 1 or (sx < 0 and -1 or 0)
    local dirY = sy > 0 and 1 or (sy < 0 and -1 or 0)

    local anyInput = dirX ~= 0 or dirY ~= 0

    if anyInput then
        if not menuStickActive then
            -- first move: immediate
            menuStickActive = true
            menuRepeatTimer = menuRepeatDelay
            applyMenuMove(dirX, dirY, context)
        else
            menuRepeatTimer = menuRepeatTimer - dt
            if menuRepeatTimer <= 0 then
                menuRepeatTimer = menuRepeatRate
                applyMenuMove(dirX, dirY, context)
            end
        end
    else
        menuStickActive = false
        menuRepeatTimer = 0
    end
end

function applyMenuMove(dirX, dirY, context)
    if context == "charselect" then
        if dirY ~= 0 then
            local count = progression:getCharacterCount()
            local maxIdx = count + 1  -- +1 for "New Character"
            if count >= Progression.MAX_CHARACTERS then maxIdx = count end  -- no new slot if full
            charSelectIdx = charSelectIdx + dirY
            if charSelectIdx < 1 then charSelectIdx = maxIdx end
            if charSelectIdx > maxIdx then charSelectIdx = 1 end
        end

    elseif context == "nameentry" then
        if dirY ~= 0 then
            nameKbRow = nameKbRow + dirY
            if nameKbRow < 1 then nameKbRow = #nameKbRows end
            if nameKbRow > #nameKbRows then nameKbRow = 1 end
        end
        if dirX ~= 0 then
            nameKbCol = nameKbCol + dirX
            if nameKbCol < 1 then nameKbCol = #nameKbRows[nameKbRow] end
            if nameKbCol > #nameKbRows[nameKbRow] then nameKbCol = 1 end
        end

    elseif context == "title" then
        if dirY ~= 0 then
            titleSelection = titleSelection + dirY
            local menuCount = 11  -- number of title menu items
            if titleSelection < 1 then titleSelection = menuCount end
            if titleSelection > menuCount then titleSelection = 1 end
        end
        if dirX ~= 0 then
            handleTitleAdjust(dirX)
        end

    elseif context == "pause" then
        if dirY ~= 0 then
            pauseSelection = pauseSelection + dirY
            if pauseSelection < 1 then pauseSelection = #pauseItems end
            if pauseSelection > #pauseItems then pauseSelection = 1 end
        end
        if dirX ~= 0 then
            adjustPauseSlider(dirX)
        end

    elseif context == "death" then
        if dirY ~= 0 then
            deathSelection = deathSelection + dirY
            if deathSelection < 1 then deathSelection = #deathItems end
            if deathSelection > #deathItems then deathSelection = 1 end
        end

    elseif context == "shop" then
        if dirY ~= 0 then
            shopSelection = shopSelection + dirY
            if shopSelection < 1 then shopSelection = #Progression.UPGRADES end
            if shopSelection > #Progression.UPGRADES then shopSelection = 1 end
        end

    elseif context == "options" then
        -- Feed stick navigation into the same handler Options uses for d-pad.
        if dirY == -1 then options:handleGamepadInput("dpup")
        elseif dirY == 1 then options:handleGamepadInput("dpdown") end
        if dirX == -1 then options:handleGamepadInput("dpleft")
        elseif dirX == 1 then options:handleGamepadInput("dpright") end
    end
end
function love.update(dt)
    dt = math.min(dt, 0.05)
    if not input.gamepad then input:detectGamepad() end

    if gameState == "story" then
        if uiMusicSource then uiMusicSource:setVolume(options.musicVolume) end
        if Story and Story.holdTimer < (Story.holdSeconds or 5) then
            Story.holdTimer = Story.holdTimer + dt
            return
        end
        Story.scrollY = (Story.scrollY or 0) + (Story.speed or 55) * dt
        return
    end

    if gameState == "charselect" then
        if uiMusicSource then uiMusicSource:setVolume(options.musicVolume) end
        updateMenuStickNavigation(dt, "charselect")
        return
    end

    if gameState == "nameentry" then
        if uiMusicSource then uiMusicSource:setVolume(options.musicVolume) end
        updateMenuStickNavigation(dt, "nameentry")
        return
    end


    if gameState == "dead" then
        if uiMusicSource then uiMusicSource:setVolume(options.musicVolume) end
        updateMenuStickNavigation(dt, "dead")
        return
    end



    if gameState == "title" then
        if uiMusicSource then uiMusicSource:setVolume(options.musicVolume) end
        updateMenuStickNavigation(dt, showShop and "shop" or "title")
        return
    end

    if gameOver then
        music:update(dt)
        updateMenuStickNavigation(dt, showShop and "shop" or "death")
        return
    end

    if introActive then
        introTimer = introTimer - dt
        introAlpha = math.max(0, introTimer / 3.0)
        if introTimer <= 0 then introActive = false end
        music:update(dt)
        return
    end

    input.mode = options:getControlMode()
    input:update(dt, player.x, player.y, player.angle, camera.x, camera.y, tileSize)

    if options.visible then
        music:setVolume(options.musicVolume)
        music:update(dt)
        updateMenuStickNavigation(dt, "options")
        return
    end

    if input.pause then
        paused = not paused
        if paused then pauseSelection = 1 end
        input.pause = false
    end
    if paused then music:update(dt); updateMenuStickNavigation(dt, "pause"); return end

    -- V3: freeze game while player is picking a perk
    if FS.perkChoiceActive then music:update(dt); return end

    -- V4: freeze game during portal prompt or victory screen
    if FS.portalPromptActive or FS.victoryActive then music:update(dt); return end

    gameTime = gameTime + dt
    music:setVolume(options.musicVolume)
    music:update(dt)

    -- movement
    local dx, dy = 0, 0
    local activeMode = input:getActiveMode()
    if activeMode == "gamepad" or activeMode == "touch" then
        dx = input.moveX; dy = input.moveY
    else
        local rawF, rawB, rawL, rawR = 0, 0, 0, 0
        if input.moveY < 0 then rawF = 1 end
        if input.moveY > 0 then rawB = 1 end
        if input.moveX < 0 then rawL = 1 end
        if input.moveX > 0 then rawR = 1 end
        local ax = math.cos(input.aimAngle); local ay = math.sin(input.aimAngle)
        local sx = -ay; local sy = ax
        dx = ax*(rawF-rawB) + sx*(rawR-rawL)
        dy = ay*(rawF-rawB) + sy*(rawR-rawL)
    end
    if input.aimActive then
        player:aimAt(input.aimX, input.aimY)
    elseif aimAssist and difficultyIdx <= 2 and input:getActiveMode() == "gamepad" then
        -- auto-aim at nearest enemy that can see us or is in melee range
        local bestDist = 999
        local bestX, bestY = nil, nil
        local meleeReach = weapons:getMeleeReach() + 0.5  -- damage ring
        for _, e in ipairs(enemies.list) do
            local edx = e.x - player.x
            local edy = e.y - player.y
            local eDist = math.sqrt(edx*edx + edy*edy)
            if eDist < 15 and eDist < bestDist then
                -- lock if enemy is in melee range (edge, not center), has LOS, or is aggressive
                local inDamageRing = eDist < meleeReach + (e.radius or 0.3)
                local hasLOS = e.cachedLOS
                local isAggressive = e.state == "hunt" or e.state == "search"
                if inDamageRing or hasLOS or isAggressive then
                    bestDist = eDist
                    bestX = e.x; bestY = e.y
                end
            end
        end
        if bestX then
            player:aimAt(bestX, bestY)
        end
    end

    -- fire
    local firedThisFrame = false
    if input.fire then
        -- sanity < 25%: chance to miss, worse as sanity drops
        local sanityPct = player.sanity / player.maxSanity
        local sanityMiss = false
        if sanityPct < 0.25 then
            local missChance = (1 - sanityPct / 0.25) * 0.5  -- up to 50% miss at 0 sanity
            if math.random() < missChance then
                sanityMiss = true
                if not self_missMsg or self_missMsg <= 0 then
                    addMessage("HANDS SHAKING...", {0.6, 0.2, 0.8})
                    self_missMsg = 2.0
                end
            end
        end
        if sanityMiss then
            -- consume stamina and make noise but deal no damage
            local wep = weapons:getCurrent()
            -- still need ammo for ranged weapons (no phantom shots)
            local hasAmmo = (wep.type == "melee") or (weapons.ammo > 0)
            if hasAmmo and weapons.fireTimer <= 0 and player.stamina >= wep.staminaCost then
                weapons.fireTimer = wep.rate * weapons.rateMod
                player.stamina = player.stamina - wep.staminaCost
                player.noise = math.min(100, player.noise + wep.noise * 0.5)
                if wep.type ~= "melee" then
                    weapons.ammo = weapons.ammo - 1
                    -- play weapon-specific fire sound on miss
                    local fireSrc = (wep.name == "shotgun" and shotgunSource)
                        or (wep.name == "smg" and smgSource)
                        or gunshotSource
                    if fireSrc then
                        local gunVol = math.max(0.15, math.min(1.0, wep.noise / 85))
                        local gs = fireSrc:clone()
                        gs:setVolume(gunVol)
                        gs:play()
                    end
                else
                    -- melee swing sound on miss
                    if swingSource then
                        local gs = swingSource:clone()
                        gs:setVolume(0.6)
                        gs:play()
                    end
                end
                firedThisFrame = true
            end
        else
            local result, cost, noise = weapons:fire(player.x, player.y, player.angle, player.dmgMult, player.stamina)
            if result == "no_ammo" then
                if not self_noAmmoMsg or self_noAmmoMsg <= 0 then
                    addMessage("NO AMMO", {1, 0.3, 0.3})
                    self_noAmmoMsg = 1.0
                end
            elseif result then
                player.stamina = player.stamina - cost
                player.noise = math.min(100, player.noise + noise)
                firedThisFrame = true
                if result == "melee" then
                    local mk, mhits = enemies:meleeCheck(player.x, player.y, player.angle, weapons:getMeleeReach(), weapons:getMeleeDamage(player.dmgMult))
                    for _, kd in ipairs(mk) do processKill(kd) end
                    -- play hurt sound for non-lethal melee hits
                    for _, h in ipairs(mhits) do
                        enemySounds:playHurt(h.x, h.y, player.x, player.y, false)
                    end
                    -- melee swing sound
                    if swingSource then
                        local gs = swingSource:clone()
                        gs:setVolume(0.6)
                        gs:play()
                    end
                elseif result == "ranged" then
                    -- weapon-specific fire sound
                    local wep = weapons:getCurrent()
                    local fireSrc = (wep.name == "shotgun" and shotgunSource)
                        or (wep.name == "smg" and smgSource)
                        or gunshotSource
                    if fireSrc then
                        local gunVol = math.max(0.15, math.min(1.0, wep.noise / 85))
                        local gs = fireSrc:clone()
                        gs:setVolume(gunVol)
                        gs:play()
                    end
                end
            end
        end
    end
    -- no ammo message cooldown
    if self_noAmmoMsg and self_noAmmoMsg > 0 then self_noAmmoMsg = self_noAmmoMsg - dt end
    if self_missMsg and self_missMsg > 0 then self_missMsg = self_missMsg - dt end

    -- bomb
    if input.useBomb and bomb:canUse() then
        local bk = bomb:use(player.x, player.y, map, enemies)
        for _, kd in ipairs(bk) do processKill(kd) end
        player.noise = math.min(100, player.noise + 90)
        addMessage("BOMB! ("..bomb.count.." left)", {1, 0.5, 0.1})
    end

    -- consumables
    if input.useHealth then if player:useAlmondWater() then addMessage("Drank Almond Water", {0.3, 0.8, 1}) end end
    if input.useBandage then if player:useBandage() then addMessage("Used Bandage", {0.3, 1, 0.3}) end end

    -- weapon cycling
    if input.cycleWeaponLeft then weapons:cyclePrev(); addMessage(weapons:getCurrent().name:upper(), weapons:getCurrent().color) end
    if input.cycleWeaponRight then weapons:cycleNext(); addMessage(weapons:getCurrent().name:upper(), weapons:getCurrent().color) end

    -- update systems (pass real headlamp light level for sanity calculation)
    local plR, plG, plB = getLightAtWorld(player.x, player.y)
    local playerLight = math.max(plR, plG, plB)
    player:update(dt, map, dx, dy, input.sprint, firedThisFrame, playerLight)
    weapons:update(dt)
    bomb:update(dt)
    map:updateLights(gameTime)
    enemies:update(dt, player.x, player.y, player.noise, map, player.moving, player.fx, player.fy, dx, dy)
    orbs:update(dt, player.x, player.y, player.baseSpeed)
    orbs:updateEffects(dt, player, weapons, enemies)

    -- bullet hits
    local bh = weapons:updateBullets(dt, map, enemies.list)
    table.sort(bh, function(a, b) return a.enemy > b.enemy end)
    for _, hit in ipairs(bh) do
        local e = enemies.list[hit.enemy]
        if e and not e.invulnerable then
            e.hp = e.hp - hit.dmg
            if e.hp <= 0 then
                local kd = enemies:kill(hit.enemy)
                if kd then processKill(kd) end
            else
                -- non-lethal hit: play random hurt sound (one-shot)
                enemySounds:playHurt(e.x, e.y, player.x, player.y, false)
            end
        end
    end

    -- contact damage
    local ch = enemies:checkPlayerCollision(player.x, player.y, 0.3)
    for _, hit in ipairs(ch) do
        local dead = player:takeDamage(hit.dmg)
        -- play attack sound
        enemySounds:playAttack(hit.ex or player.x, hit.ey or player.y, player.x, player.y)
        if dead then
            gameOver = true
            gameState = "dead"
            deathSelection = 1
            showShop = false
            addMessage(playerName.." died", {1, 0.2, 0.2})
            enemySounds:stopAll()
            if heartbeatSource then heartbeatSource:stop() end
            if whisperMale and whisperMale:isPlaying() then whisperMale:stop() end
            if whisperFemale and whisperFemale:isPlaying() then whisperFemale:stop() end
            -- earn tokens from this run (V2: now includes bestStreak and time)
            if progression then
                tokensEarned = progression:addRunResults(difficultyIdx, wave, kills, player.bestRunStreak, gameTime)
            end
        end
    end

    -- pickups
    local im = items:checkPickup(player.x, player.y, player, weapons, bomb)
    for _, m in ipairs(im) do addMessage(m.text, m.color) end
    local orbPickup, orbIsBuff = orbs:checkPickup(player.x, player.y)
    if orbPickup then
        local effect = Orbs.rollEffect(player, weapons, enemies, orbs.activeEffects, bomb, orbIsBuff)
        addMessage("CHAOS: "..effect.text, effect.color)
        player.dmgFlash = 0.3
    end
    items:update(dt, player.x, player.y)
    if props then props:cleanup(player.x, player.y) end

    -- enemy spawning (baby-stepped for 30-day runs, difficulty-scaled)
    if not enemies.testMode then

    enemies.spawnTimer = enemies.spawnTimer + dt
    local baseRate = math.max(0.90, enemies.spawnRate - wave * 0.07)
    local rate = baseRate / diffSpawnScale  -- <<<< difficulty makes spawns faster/slower
    if enemies.spawnTimer >= rate then
        enemies.spawnTimer = 0
        enemies:spawn(player.x, player.y, map, wave, enemySounds)
    end
    end

    -- day/wave
    local currentDay = math.floor(gameTime / dayLength) + 1
    if currentDay > wave then
        wave = currentDay
        addMessage("DAY "..wave, {1, 0.8, 0.2})
        enemies.maxEnemies = math.min(diffMaxEnemyCap, 30 + wave * 2)  -- <<<< cap scales by difficulty
    end

    if not enemies.testMode then
    -- V3: military chest proximity detection
    local nearbyChests = map:getChestRoomsNear(player.x, player.y, FS.CHEST_DETECT_RANGE)
    for _, chest in ipairs(nearbyChests) do
        -- spawn loot cluster and enemy swarm, mark as looted
        items:spawnChestLoot(chest.worldX, chest.worldY, weapons)
        enemies:spawnChestSwarm(chest.worldX, chest.worldY, FS.CHEST_SWARM_COUNT, map, wave, enemySounds)
        map:markChestLooted(chest.cx, chest.cy, chest.idx)
        addMessage("MILITARY CHEST FOUND!", {0.2, 0.8, 1})
        addMessage("HOSTILES INCOMING!", {1, 0.3, 0.2})
    end
    end

    if not enemies.testMode then
    -- V4: portal spawning on Day 30
    if wave >= FS.PORTAL_DAY and not FS.portalSpawned then
        local portal = map:spawnPortal(player.x, player.y)
        if portal then
            FS.portalSpawned = true
            -- spawn horde + loot around portal
            enemies:spawnPortalHorde(portal.x, portal.y, FS.PORTAL_HORDE_SIZE, map, wave, enemySounds)
            -- spawn orbs and items near portal as reward
            for i = 1, 6 do
                local ox = portal.x + (math.random() - 0.5) * 6
                local oy = portal.y + (math.random() - 0.5) * 6
                orbs:spawn(ox, oy)
            end
            for i = 1, 4 do
                items:spawnDrop(portal.x + (math.random() - 0.5) * 5, portal.y + (math.random() - 0.5) * 5, false)
            end
            addMessage("AN EXIT HAS APPEARED!", {0.2, 1, 0.5})
            addMessage("Clear the horde to escape!", {0.9, 0.8, 0.2})
        end
    end

    -- V4: portal proximity check
    local portal = map:getPortal()
    if portal and portal.active and not FS.portalPromptActive then
        local pdx = player.x - portal.x
        local pdy = player.y - portal.y
        if pdx*pdx + pdy*pdy < FS.PORTAL_INTERACT_DIST * FS.PORTAL_INTERACT_DIST then
            local guardsLeft = enemies:countPortalGuards()
            if guardsLeft <= 0 then
                FS.portalPromptActive = true
                FS.portalPromptChoice = 1
            elseif FS.portalMsgCooldown <= 0 and guardsLeft <= 5 then
                addMessage(guardsLeft.." hostiles remain!", {1, 0.5, 0.2})
                FS.portalMsgCooldown = 3.0
            end
        end
    end
    if FS.portalMsgCooldown > 0 then FS.portalMsgCooldown = FS.portalMsgCooldown - dt end
    end


    -- enemy sounds
    enemySounds:setVolume(options.sfxVolume)
    enemySounds:update(dt, enemies.list, player.x, player.y)

    -- camera
    local w, h = love.graphics.getDimensions()
    local tcx = player.x - (w / tileSize) / 2
    local tcy = player.y - (h / tileSize) / 2
    local smooth = 1.0 - math.exp(-8 * dt)
    camera.x = camera.x + (tcx - camera.x) * smooth
    camera.y = camera.y + (tcy - camera.y) * smooth

    -- expand infinite map as player moves
    local viewTiles = math.max(w, h) / tileSize
    map:expandAround(player.x, player.y, viewTiles)

    -- spawn items and orbs in freshly generated chunks
    local newChunks = map:drainNewChunks()
    local L = Items.LOOT

    -- Current player chunk (used to avoid spawning props on top of the player)
    -- NOTE: player.x/y are in tile units.
    local pChunkX = math.floor(player.x / (map.CHUNK or 48))
    local pChunkY = math.floor(player.y / (map.CHUNK or 48))

    for _, nc in ipairs(newChunks) do
        local count = math.floor(math.random(L.chunkItemsMin, L.chunkItemsMax) * items.dropScale)
        for i = 1, count do
            local ix, iy = map:randomOpenInChunk(nc.cx, nc.cy)
            if ix then
                local item = {x = ix, y = iy, pulseTimer = math.random() * 3}
                items:assignType(item, false)
                items.list[#items.list + 1] = item
            end
        end

        -- V5: BAD LUCK PROTECTION — force a weapon drop if too many chunks without one
        if items:trackChunkForBadLuck() then
            local fx, fy = map:randomOpenInChunk(nc.cx, nc.cy)
            if fx then
                items:spawnForcedWeapon(fx, fy)
            end
        end

        for i = 1, math.random(L.chunkOrbsMin, L.chunkOrbsMax) do
            local ox, oy = map:randomOpenInChunk(nc.cx, nc.cy)
            if ox then orbs:spawn(ox, oy) end
        end
        -- spawn environmental props (furniture, bodies, clutter)
        -- SAFETY: never spawn props in the player's current chunk; it can trap the player at spawn.
        -- (Backrooms vibe is fine with chunks changing, but getting stuck on frame 1 looks like a bug.)
        if props and not (nc.cx == pChunkX and nc.cy == pChunkY) then
            props:spawnInChunk(nc.cx, nc.cy, map)
        end
    end

    -- headlamp battery
    if headlampOn then
        headlampBattery = headlampBattery - headlampDrainRate * dt
        if headlampBattery <= 0 then
            headlampBattery = 0
            headlampOn = false
            addMessage("HEADLAMP DEAD", {1, 0.3, 0.3})
        end
    else
        -- slow passive recharge when off
        headlampBattery = math.min(headlampBatteryMax, headlampBattery + headlampRechargeRate * dt)
    end

    -- heartbeat: always audible, louder as stamina drops
    if heartbeatSource then
        local staminaPct = player.stamina / player.maxStamina
        local hbVol = heartbeatBaseVol + (heartbeatMaxVol - heartbeatBaseVol) * (1.0 - staminaPct)
        -- heartbeat is NOT scaled by sfxVolume, it's a core gameplay cue
        heartbeatSource:setVolume(hbVol)
        if not heartbeatSource:isPlaying() then heartbeatSource:play() end
    end

    -- ═══ SANITY WHISPERS: below 10% sanity, crossfading male/female whispers ═══
    -- NOT sliderable, this is a gameplay punishment cue like Hellblade
    local sanityPctW = player.sanity / player.maxSanity
    if sanityPctW < 0.10 then
        -- intensity scales from 0 at 10% to 1.0 at 0%
        local whisperIntensity = 1.0 - (sanityPctW / 0.10)
        local maxWhisperVol = 0.7 * whisperIntensity

        -- crossfade oscillation
        whisperCrossfade = whisperCrossfade + whisperCrossfadeDir * whisperCrossfadeSpeed * dt
        if whisperCrossfade >= 1.0 then
            whisperCrossfade = 1.0
            whisperCrossfadeDir = -1
        elseif whisperCrossfade <= 0 then
            whisperCrossfade = 0
            whisperCrossfadeDir = 1
        end

        -- smoothed crossfade curve (sine for natural feel)
        local fadeT = (math.sin(whisperCrossfade * math.pi - math.pi/2) + 1) / 2
        local maleVol = maxWhisperVol * (1.0 - fadeT)
        local femaleVol = maxWhisperVol * fadeT

        if whisperMale then
            whisperMale:setVolume(maleVol)
            if not whisperMale:isPlaying() then whisperMale:play() end
        end
        if whisperFemale then
            whisperFemale:setVolume(femaleVol)
            if not whisperFemale:isPlaying() then whisperFemale:play() end
        end
    else
        -- above 10% sanity: stop whispers
        if whisperMale and whisperMale:isPlaying() then whisperMale:stop() end
        if whisperFemale and whisperFemale:isPlaying() then whisperFemale:stop() end
    end

    -- ═══ HEADLAMP LIGHT DAMAGE: enemies in direct beam take tick damage ═══
    if headlampOn and headlampBattery > 0 then
        local hlDmgPerSec = 1.25  -- <<<< HP per second in direct beam
        local lightKills = {}
        for i, e in ipairs(enemies.list) do
            if e.lightFear > 0 then
                local dx = e.x - player.x
                local dy = e.y - player.y
                local dist = math.sqrt(dx*dx + dy*dy)
                if dist < HEADLAMP_RADIUS and dist > 0.1 then
                    local angleToEnemy = math.atan2(dy, dx)
                    local angleDiff = angleToEnemy - player.angle
                    while angleDiff > math.pi do angleDiff = angleDiff - math.pi * 2 end
                    while angleDiff < -math.pi do angleDiff = angleDiff + math.pi * 2 end
                    if math.abs(angleDiff) < HEADLAMP_CONE then
                        -- in direct beam: damage scales with lightFear and closeness
                        local closeness = 1.0 - (dist / HEADLAMP_RADIUS)
                        local dmg = hlDmgPerSec * e.lightFear * closeness * dt
                        e.hp = e.hp - dmg
                        e.hitFlash = 0.05
                        if e.hp <= 0 then lightKills[#lightKills+1] = i end
                    end
                end
            end
        end
        -- process light kills in reverse order so indices stay valid
        for k = #lightKills, 1, -1 do
            local kd = enemies:kill(lightKills[k])
            if kd then processKill(kd) end
        end
    end

    -- messages
    local i = 1
    while i <= #messages do
        messages[i].life = messages[i].life - dt
        if messages[i].life <= 0 then table.remove(messages, i) else i = i + 1 end
    end
end

-- ═══ SEC 8: INPUT HANDLERS — keyboard, gamepad, touch, mouse ═══
function love.keypressed(key)
    -- story scroll: any key skips to character select
    if gameState == "story" then
        gameState = "charselect"
        charSelectIdx = 1
        charSelectDelete = false
        return
    end

    -- character select screen
    if gameState == "charselect" then
        handleCharSelectKeyboard(key)
        return
    end

    -- name entry: keyboard typing
    if gameState == "nameentry" then
        handleNameKeyboard(key)
        return
    end




    -- death screen
    if gameState == "dead" then
        if key == "up" then deathSelection = deathSelection - 1; if deathSelection < 1 then deathSelection = #deathItems end
        elseif key == "down" then deathSelection = deathSelection + 1; if deathSelection > #deathItems then deathSelection = 1 end
        elseif key == "return" or key == "space" then
            local choice = deathItems[deathSelection]
            if choice == "Retry" then restartGame()
            elseif choice == "Upgrades" then gameState = "title"; showShop = true
            elseif choice == "Main Menu" then backToTitle() end
        elseif key == "escape" then backToTitle() end
        return
    end

    if options.visible then options:handleInput(key); return end

    -- V3: perk choice keyboard input
    if FS.perkChoiceActive and FS.perkChoices then
-- Allow UI navigation via D-pad OR left stick (from input.lua ui pulses)
if input.uiLeft then  FS.perkSelection = 1 end
if input.uiRight then FS.perkSelection = 2 end
        if key == "1" or key == "left" then FS.perkSelection = 1
        elseif key == "2" or key == "right" then FS.perkSelection = 2
        elseif key == "return" or key == "space" then
            local chosen = FS.perkChoices[FS.perkSelection]
            if chosen and chosen.apply then
                chosen.apply(player, weapons, bomb)
                player.activeRunPerks[#player.activeRunPerks + 1] = {id = chosen.id, name = chosen.name}
                addMessage("PERK: "..chosen.name:upper(), {0.3, 1, 0.5})
            end
            player.pendingPerkChoice = false
            FS.perkChoiceActive = false
            FS.perkChoices = nil
        end
        return
    end

    -- V4: victory screen keyboard input
    if FS.victoryActive then
        if key == "return" or key == "space" then
            backToTitle()
        end
        return
    end

    -- V4: portal prompt keyboard input
    if FS.portalPromptActive then
        if key == "left" or key == "1" then FS.portalPromptChoice = 1
        elseif key == "right" or key == "2" then FS.portalPromptChoice = 2
        elseif key == "return" or key == "space" then
            if FS.portalPromptChoice == 1 then
                -- ESCAPE: victory!
                FS.portalPromptActive = false
                FS.victoryActive = true
                enemySounds:stopAll()
                if heartbeatSource then heartbeatSource:stop() end
                if whisperMale and whisperMale:isPlaying() then whisperMale:stop() end
                if whisperFemale and whisperFemale:isPlaying() then whisperFemale:stop() end
                -- earn tokens with 2x victory bonus
                if progression then
                    local base = progression:addRunResults(difficultyIdx, wave, kills, player.bestRunStreak, gameTime)
                    FS.victoryTokens = base * 2
                    -- add the bonus tokens (base already added by addRunResults)
                    local profile = progression:getProfile(difficultyIdx)
                    profile.tokens = profile.tokens + base  -- extra base = 2x total
                    progression:save()
                end
            else
                -- STAY: deactivate portal, no more exits
                FS.portalPromptActive = false
                local portal = map:getPortal()
                if portal then portal.active = false end
                addMessage("LIVING LEGEND MODE!", {1, 0.8, 0.2})
                addMessage("No more exits. Survive forever.", {0.7, 0.6, 0.5})
            end
        elseif key == "escape" then
            FS.portalPromptActive = false  -- dismiss without choosing (portal stays active)
        end
        return
    end

    if gameState == "title" and showShop then
        if key == "up" then shopSelection = shopSelection - 1; if shopSelection < 1 then shopSelection = #Progression.UPGRADES end
        elseif key == "down" then shopSelection = shopSelection + 1; if shopSelection > #Progression.UPGRADES then shopSelection = 1 end
        elseif key == "return" or key == "space" then
            progression:buyUpgrade(difficultyIdx, Progression.UPGRADES[shopSelection].id)
        elseif key == "escape" then showShop = false end
        return
    end
    if gameState == "title" then handleTitleInput(key); return end
    if paused then
        if key == "escape" or (key == "return" and pauseSelection == 6) then paused = false; return end
        if key == "return" and pauseSelection == 5 then if difficultyIdx >= 3 then aimAssist = false else aimAssist = not aimAssist end; return end
        if key == "return" and pauseSelection == 7 then options:toggle(); paused = false; return end
        if key == "return" and pauseSelection == 8 then paused = false; backToTitle(); return end
        if key == "up" then pauseSelection = pauseSelection - 1; if pauseSelection < 1 then pauseSelection = #pauseItems end
        elseif key == "down" then pauseSelection = pauseSelection + 1; if pauseSelection > #pauseItems then pauseSelection = 1 end
        elseif key == "left" then adjustPauseSlider(-1)
        elseif key == "right" then adjustPauseSlider(1) end
        if key == "1" then if player:useAlmondWater() then addMessage("Drank Almond Water", {0.3,0.8,1}) end end
        if key == "2" then if player:useBandage() then addMessage("Used Bandage", {0.3,1,0.3}) end end
        return
    end
    -- death screen
    if gameOver then
        if showShop then
            -- upgrade shop navigation
            if key == "up" then shopSelection = shopSelection - 1; if shopSelection < 1 then shopSelection = #Progression.UPGRADES end
            elseif key == "down" then shopSelection = shopSelection + 1; if shopSelection > #Progression.UPGRADES then shopSelection = 1 end
            elseif key == "return" or key == "space" then
                progression:buyUpgrade(difficultyIdx, Progression.UPGRADES[shopSelection].id)
            elseif key == "escape" or key == "backspace" then
                showShop = false
            end
        else
            -- death menu navigation
            if key == "up" then deathSelection = deathSelection - 1; if deathSelection < 1 then deathSelection = 3 end
            elseif key == "down" then deathSelection = deathSelection + 1; if deathSelection > 3 then deathSelection = 1 end
            elseif key == "return" or key == "space" or key == "r" then
                if deathSelection == 1 then restartGame()
                elseif deathSelection == 2 then showShop = true; shopSelection = 1
                elseif deathSelection == 3 then backToTitle() end
            elseif key == "escape" then backToTitle() end
        end
        return
    end
    if key == "escape" then paused = true; pauseSelection = 1 end
    if key == "h" then
        if headlampBattery > 0 then
            headlampOn = not headlampOn
            addMessage(headlampOn and "HEADLAMP ON" or "HEADLAMP OFF", {1, 0.95, 0.7})
        else
            addMessage("NO BATTERY", {1, 0.3, 0.3})
        end
    end
    if key == "x" then
        if player and player.batteries > 0 then
            player.batteries = player.batteries - 1
            headlampBattery = headlampBatteryMax
            headlampOn = true
            addMessage("BATTERY REPLACED ("..player.batteries.." left)", {0.2, 1, 0.6})
        else
            addMessage("NO BATTERIES", {1, 0.3, 0.3})
        end
    end
    if key == "f10" then options:toggle() end
    if key == "1" then if player and player:useAlmondWater() then addMessage("Drank Almond Water", {0.3,0.8,1}) end end
    if key == "2" then if player and player:useBandage() then addMessage("Used Bandage", {0.3,1,0.3}) end end
    if key == "q" then input.useBomb = true end
    if key == "e" or key == "tab" then weapons:cycleNext(); addMessage(weapons:getCurrent().name:upper(), weapons:getCurrent().color) end
end

function love.gamepadpressed(joystick, button)
    -- story scroll: any button skips
    if gameState == "story" then
        gameState = "charselect"
        charSelectIdx = 1
        charSelectDelete = false
        return
    end

    -- character select: d-pad navigates, A selects
    if gameState == "charselect" then
        handleCharSelectGamepad(button)
        return
    end

    -- name entry: d-pad navigates, A selects
    if gameState == "nameentry" then
        handleNameGamepad(button)
        return
    end




    -- death screen
    if gameState == "dead" then
        if button == "dpup" then deathSelection = deathSelection - 1; if deathSelection < 1 then deathSelection = #deathItems end
        elseif button == "dpdown" then deathSelection = deathSelection + 1; if deathSelection > #deathItems then deathSelection = 1 end
        elseif button == "a" then
            local choice = deathItems[deathSelection]
            if choice == "Retry" then restartGame()
            elseif choice == "Upgrades" then gameState = "title"; showShop = true
            elseif choice == "Main Menu" then backToTitle() end
        elseif button == "b" or button == "back" then backToTitle() end
        return
    end

    if options.visible then options:handleGamepadInput(button); return end

    -- V3: perk choice gamepad input
    if FS.perkChoiceActive and FS.perkChoices then
        if button == "dpleft" or button == "leftshoulder" then FS.perkSelection = 1
        elseif button == "dpright" or button == "rightshoulder" then FS.perkSelection = 2
        elseif button == "a" then
            local chosen = FS.perkChoices[FS.perkSelection]
            if chosen and chosen.apply then
                chosen.apply(player, weapons, bomb)
                player.activeRunPerks[#player.activeRunPerks + 1] = {id = chosen.id, name = chosen.name}
                addMessage("PERK: "..chosen.name:upper(), {0.3, 1, 0.5})
            end
            player.pendingPerkChoice = false
            FS.perkChoiceActive = false
            FS.perkChoices = nil
        end
        return
    end

    -- V4: victory screen gamepad input
    if FS.victoryActive then
        if button == "a" or button == "start" then backToTitle() end
        return
    end

    -- V4: portal prompt gamepad input
    if FS.portalPromptActive then
        if button == "dpleft" or button == "leftshoulder" then FS.portalPromptChoice = 1
        elseif button == "dpright" or button == "rightshoulder" then FS.portalPromptChoice = 2
        elseif button == "a" then
            if FS.portalPromptChoice == 1 then
                FS.portalPromptActive = false
                FS.victoryActive = true
                enemySounds:stopAll()
                if heartbeatSource then heartbeatSource:stop() end
                if whisperMale and whisperMale:isPlaying() then whisperMale:stop() end
                if whisperFemale and whisperFemale:isPlaying() then whisperFemale:stop() end
                if progression then
                    local base = progression:addRunResults(difficultyIdx, wave, kills, player.bestRunStreak, gameTime)
                    FS.victoryTokens = base * 2
                    local profile = progression:getProfile(difficultyIdx)
                    profile.tokens = profile.tokens + base
                    progression:save()
                end
            else
                FS.portalPromptActive = false
                local portal = map:getPortal()
                if portal then portal.active = false end
                addMessage("LIVING LEGEND MODE!", {1, 0.8, 0.2})
                addMessage("No more exits. Survive forever.", {0.7, 0.6, 0.5})
            end
        elseif button == "b" then
            FS.portalPromptActive = false  -- dismiss without choosing (portal stays active)
        end
        return
    end

    if gameState == "title" and showShop then
        if button == "a" then
            progression:buyUpgrade(difficultyIdx, Progression.UPGRADES[shopSelection].id)
        elseif button == "b" or button == "back" then
            showShop = false
        end
        return
    end
    if gameState == "title" then handleTitleGamepad(button); return end
    -- death screen
    if gameOver then
        if showShop then
            -- d-pad handled by continuous system; just handle A/B
            if button == "a" then
                progression:buyUpgrade(difficultyIdx, Progression.UPGRADES[shopSelection].id)
            elseif button == "b" or button == "back" then
                showShop = false
            end
        else
            -- d-pad handled by continuous system; just handle A/B/start
            if button == "a" or button == "start" then
                if deathSelection == 1 then restartGame()
                elseif deathSelection == 2 then showShop = true; shopSelection = 1
                elseif deathSelection == 3 then backToTitle() end
            elseif button == "b" or button == "back" then backToTitle() end
        end
        return
    end
    if paused then
        if button == "b" or button == "back" or (button == "a" and pauseSelection == 6) then paused = false; return end
        if button == "a" and pauseSelection == 5 then if difficultyIdx >= 3 then aimAssist = false else aimAssist = not aimAssist end; return end
        if button == "a" and pauseSelection == 7 then options:toggle(); paused = false; return end
        if button == "a" and pauseSelection == 8 then paused = false; backToTitle(); return end
        -- d-pad navigation now handled by continuous stick system in love.update
        return
    end
    -- B = cycle weapons, Y = almond water, X = food
    -- D-pad up/down = HUD & run stats (handled in input.lua)
    -- D-pad left = battery
    -- RB = bomb, LB = headlamp toggle
    if button == "b" then
        weapons:cycleNext()
        addMessage(weapons:getCurrent().name:upper(), weapons:getCurrent().color)
        return
    end
    if button == "y" then
        if player and player:useAlmondWater() then
            addMessage("Drank Almond Water", {0.3, 0.8, 1})
        else
            addMessage("NO ALMOND WATER", {1, 0.3, 0.3})
        end
        return
    end
if button == "x" then
    if player and player:useBandage() then
        addMessage("Used Bandage", {0.3, 1, 0.3})
    else
        addMessage("NO BANDAGES", {1, 0.3, 0.3})
    end
    return
end
if button == "leftstick" then
        if player and player.batteries > 0 then
            player.batteries = player.batteries - 1
            headlampBattery = headlampBatteryMax
            headlampOn = true
            addMessage("BATTERY REPLACED ("..player.batteries.." left)", {0.2, 1, 0.6})
        else
            addMessage("NO BATTERIES", {1, 0.3, 0.3})
        end
        return
    end
    if button == "rightshoulder" then
        if bomb:canUse() then
            local bk = bomb:use(player.x, player.y, map, enemies)
            for _, kd in ipairs(bk) do processKill(kd) end
            player.noise = math.min(100, player.noise + 90)
            addMessage("BOMB! ("..bomb.count.." left)", {1, 0.5, 0.1})
        end
        return
    end
    if button == "leftshoulder" then
    if headlampBattery > 0 then
        headlampOn = not headlampOn
        addMessage(headlampOn and "HEADLAMP ON" or "HEADLAMP OFF", {1, 0.95, 0.7})
    else
        addMessage("NO BATTERY", {1, 0.3, 0.3})
    end
    return
end
    if button == "back" then paused = true; pauseSelection = 1; return end
end

function love.wheelmoved(x, y)
    if gameState ~= "playing" or not weapons then return end
    if y > 0 then weapons:cycleNext(); addMessage(weapons:getCurrent().name:upper(), weapons:getCurrent().color)
    elseif y < 0 then weapons:cyclePrev(); addMessage(weapons:getCurrent().name:upper(), weapons:getCurrent().color) end
end

function love.touchpressed(id, x, y)
    local w, h = love.graphics.getDimensions()
    if gameState == "story" then gameState = "charselect"; charSelectIdx = 1; charSelectDelete = false; return end
    if gameState == "charselect" then handleCharSelectKeyboard("return"); return end
    if gameState == "nameentry" then handleNameTouch(x, y, w, h); return end

    if options.visible then if y > h - 60 then options:handleInput("escape") end; return end
    if gameState == "title" then handleTitleInput("return"); return end
    if paused then paused = false; return end
    if gameOver then
        if showShop then showShop = false else restartGame() end
        return
    end
    input:touchpressed(id, x, y, w, h)
end
function love.touchmoved(id, x, y) input:touchmoved(id, x, y) end
function love.touchreleased(id) input:touchreleased(id) end

function love.textinput(t)
    if gameState == "nameentry" and #playerName < 16 then
        local ch = t:upper()
        if ch:match("[A-Z0-9%- _]") then
            playerName = playerName .. ch
        end
    end
end

-- ═══ SEC 9: TITLE SCREEN LOGIC — menu navigation, settings ═══
function handleTitleInput(key)
    local menuItems = {"Difficulty", "Brightness", "Music Volume", "Enemy Sounds", "Headlamp", "Aim Assist", "START", "UPGRADES", "CHARACTER", "Options", "EXIT"}
    local numItems = #menuItems
    if key == "up" then titleSelection = titleSelection - 1; if titleSelection < 1 then titleSelection = numItems end
    elseif key == "down" then titleSelection = titleSelection + 1; if titleSelection > numItems then titleSelection = 1 end
    elseif key == "left" then
        if titleSelection == 1 then difficultyIdx = math.max(1, difficultyIdx - 1)
        elseif titleSelection == 2 then titleBrightness = math.max(0, titleBrightness - 0.05)
        elseif titleSelection == 3 then options.musicVolume = math.max(0, options.musicVolume - 0.05)
        elseif titleSelection == 4 then options.sfxVolume = math.max(0, options.sfxVolume - 0.05)
        elseif titleSelection == 5 then options.headlampBrightness = math.max(0.1, options.headlampBrightness - 0.05)
        elseif titleSelection == 6 then if difficultyIdx >= 3 then aimAssist = false else aimAssist = not aimAssist end end
    elseif key == "right" then
        if titleSelection == 1 then difficultyIdx = math.min(4, difficultyIdx + 1)
        elseif titleSelection == 2 then titleBrightness = math.min(1, titleBrightness + 0.05)
        elseif titleSelection == 3 then options.musicVolume = math.min(1, options.musicVolume + 0.05)
        elseif titleSelection == 4 then options.sfxVolume = math.min(1, options.sfxVolume + 0.05)
        elseif titleSelection == 5 then options.headlampBrightness = math.min(1, options.headlampBrightness + 0.05) 
        elseif titleSelection == 6 then if difficultyIdx >= 3 then aimAssist = false else aimAssist = not aimAssist end end
    elseif key == "return" or key == "space" then
        local item = menuItems[titleSelection]
        if item == "Aim Assist" then
            if difficultyIdx >= 3 then aimAssist = false else aimAssist = not aimAssist end
        elseif item == "START" then
            startGame()
        elseif item == "Options" then
            options:toggle()  -- Options menu
        elseif item == "UPGRADES" then
            showShop = true; shopSelection = 1  -- Upgrades shop
        elseif item == "CHARACTER" then
            gameState = "charselect"; charSelectIdx = 1; charSelectDelete = false  -- Switch character
        elseif item == "EXIT" then
            love.event.quit()
        end
    end
end

function handleTitleGamepad(button)
    -- d-pad navigation now handled by continuous stick system in love.update
    if button == "a" or button == "start" then handleTitleInput("return") end
end

function handleTitleAdjust(dir)
    if dir > 0 then handleTitleInput("right")
    elseif dir < 0 then handleTitleInput("left") end
end

-- ═══ SEC 10: PAUSE MENU LOGIC — volume/brightness sliders ═══
function adjustPauseSlider(dir)
    local step = 0.05
    if pauseSelection == 1 then options.musicVolume = math.max(0, math.min(1, options.musicVolume + dir * step))
    elseif pauseSelection == 2 then options.sfxVolume = math.max(0, math.min(1, options.sfxVolume + dir * step))
    elseif pauseSelection == 3 then options.brightness = math.max(0, math.min(1, options.brightness + dir * step))
    elseif pauseSelection == 4 then options.headlampBrightness = math.max(0.1, math.min(1, options.headlampBrightness + dir * step))
    elseif pauseSelection == 5 then if difficultyIdx >= 3 then aimAssist = false else aimAssist = not aimAssist end end
end

-- ═══ SEC 11: KILL / MESSAGE HELPERS — XP, drops, messages ═══
function processKill(killData)
    if not killData then return end
    kills = kills + 1

    -- V2: track kill streak (resets on damage in player:takeDamage)
    player:recordKill()
    if player.streakDisplayTimer > 0 then
        addMessage(player.currentStreak.." KILL STREAK!", {1, 0.5, 0.1})
    end

    -- V2: addXp now applies streak multiplier internally
    local leveled = player:addXp(killData.xp)
    if leveled then
        addMessage(playerName.." leveled up! (Lv."..player.level..")", {1, 0.8, 0.2})
        -- V3: trigger perk choice if player has pendingPerkChoice flag
        if player.pendingPerkChoice then
            local Progression = require("progression")

            local excludeIds = {}
            for _, p in ipairs(player.activeRunPerks) do
                excludeIds[#excludeIds + 1] = p.id
            end
            FS.perkChoices = Progression.rollPerkChoice(excludeIds)
            if FS.perkChoices and #FS.perkChoices >= 2 then
                FS.perkSelection = 1
                FS.perkChoiceActive = true
            else
                player.pendingPerkChoice = false  -- no perks left to offer
            end
        end
    end
    -- death sound
    if killData.soundUID then
        enemySounds:onEnemyDeath(killData.soundUID, killData.x, killData.y, player.x, player.y)
    end
    if math.random() < killData.dropChance then
        local L = Items.LOOT
        if math.random() < L.killOrbChance * items.dropScale then orbs:spawn(killData.x, killData.y)
        else items:spawnDrop(killData.x, killData.y, true) end
    end
end

function addMessage(text, color) messages[#messages+1] = {text = text, color = color or {1,1,1}, life = 3.0} end
function formatTime(s) return string.format("%d:%02d", math.floor(s/60), math.floor(s%60)) end

-- ═══ SEC 12: LIGHTING SYSTEM — headlamp cone, wall shadows, ambient ═══
-- simple wall raycast for light occlusion (optimized: fewer steps for speed)
function lightRayBlocked(x1, y1, x2, y2)
    -- Returns true if there is a wall BETWEEN the start and end points.
    -- With skinny walls, we must be careful: points that land inside the *target wall face*
    -- should still receive light, but walls before that must still occlude.
    local dx = x2 - x1; local dy = y2 - y1
    local dist = math.sqrt(dx*dx + dy*dy)
    if dist < 0.5 then return false end

    local endInsideWall = map:isWall(x2, y2)

    -- Higher step density reduces "wobble" on thin geometry.
    local steps = math.ceil(dist * 2.2)
    local hitIndex = nil

    for i = 1, steps do
        local t = i / steps
        local sx = x1 + dx * t
        local sy = y1 + dy * t
        if map:isWall(sx, sy) then
            hitIndex = i
            break
        end
    end

    if not hitIndex then return false end

    -- If the end point is inside the wall, allow lighting only if the first hit is
    -- VERY near the end of the ray (meaning we hit the target face, not an earlier wall).
    if endInsideWall then
        if hitIndex >= steps - 2 then
            return false
        end
        -- also allow if the hit point is within a small epsilon of the end point
        local t = hitIndex / steps
        local hx = x1 + dx * t
        local hy = y1 + dy * t
        local edx = x2 - hx
        local edy = y2 - hy
        if (edx*edx + edy*edy) <= 0.07 then
            return false
        end
    end

    return true
end

function getLightAtWorld(wx, wy)
    -- FIX: Align headlamp to sprite facing.
    -- The right stick drives player.angle; the spritesheet frames are rotated vs math angle,
    -- so we apply HEADLAMP_ANGLE_OFFSET (90° clockwise by default).
    local lampAngle = player.angle + HEADLAMP_ANGLE_OFFSET

    -- FIX: Move the light origin slightly forward so the beam doesn't look like it comes from the shoulder.
    -- (This is in world/tile units; tweak HEADLAMP_FORWARD_OFFSET in the tuning block above.)
    local lampX = player.x + math.cos(lampAngle) * HEADLAMP_FORWARD_OFFSET
    local lampY = player.y + math.sin(lampAngle) * HEADLAMP_FORWARD_OFFSET

    local dx = wx - lampX
    local dy = wy - lampY
    local dist = math.sqrt(dx*dx + dy*dy)

    local headlamp = 0
    local hlBright = (options.headlampBrightness or 0.7)
    local batteryFactor = headlampBattery / headlampBatteryMax  -- 0-1 linear, directly controls brightness

    -- sanity flicker: headlamp flashes when sanity <= 25%
    local sanityPct = player.sanity / player.maxSanity
    if sanityPct <= 0.25 and sanityPct > 0 then
        local flickerSpeed = 6 + (1 - sanityPct / 0.25) * 10  -- faster as sanity drops
        local flicker = math.sin(gameTime * flickerSpeed) * 0.4 + 0.6
        batteryFactor = batteryFactor * flicker
    end

    if headlampOn and batteryFactor > 0 and dist < HEADLAMP_RADIUS then
        -- wall occlusion check (use lamp origin!)
        if not lightRayBlocked(lampX, lampY, wx, wy) then
            local angleTo = math.atan2(dy, dx)
            local ad = angleTo - lampAngle
            while ad > math.pi do ad = ad - math.pi * 2 end
            while ad < -math.pi do ad = ad + math.pi * 2 end

            local cf = 1.0
            if math.abs(ad) > HEADLAMP_CONE then
                cf = math.max(0, 1.0 - (math.abs(ad) - HEADLAMP_CONE) * 1.0) * 0.35
            end
            local df = 1.0 - (dist / HEADLAMP_RADIUS)
            headlamp = (df ^ 1.3) * cf * hlBright * batteryFactor
            if dist < 3.0 then headlamp = math.max(headlamp, 0.7 * hlBright * batteryFactor * (1.0 - dist / 3.0)) end
        end
    end

    local ambient = AMBIENT + options:getAmbientBoost()
    local baseLight = math.max(ambient, headlamp)

    -- ═══ ORB GLOW: colored point light with wall occlusion ═══
    -- Green orbs (buffs) emit green light, yellow orbs (nerfs) emit warm yellow.
    -- Both count as real light for sanity regeneration.
    local orbR, orbG, orbB = 0, 0, 0
    local ORB_RADIUS = 5.0      -- glow reach in tiles
    local ORB_BRIGHTNESS = 0.55  -- peak brightness at center
    for _, orb in ipairs(orbs.list) do
        local odx = wx - orb.x
        local ody = wy - orb.y
        local odist = math.sqrt(odx*odx + ody*ody)
        if odist < ORB_RADIUS then
            -- wall occlusion: light doesn't pass through walls
            if not lightRayBlocked(orb.x, orb.y, wx, wy) then
                local falloff = 1.0 - (odist / ORB_RADIUS)
                local pulse = math.sin((orb.pulseTimer or 0) * 3) * 0.15 + 0.85
                local intensity = (falloff ^ 1.5) * ORB_BRIGHTNESS * pulse
                if orb.isBuff then
                    -- green glow
                    orbR = orbR + intensity * 0.25
                    orbG = orbG + intensity
                    orbB = orbB + intensity * 0.2
                else
                    -- yellow/amber glow
                    orbR = orbR + intensity * 0.9
                    orbG = orbG + intensity * 0.75
                    orbB = orbB + intensity * 0.15
                end
            end
        end
    end

    -- return r, g, b (colored channels near orbs)
    local r = math.min(1.0, baseLight + orbR)
    local g = math.min(1.0, baseLight + orbG)
    local b = math.min(1.0, baseLight + orbB)
    return r, g, b
end

function drawLightOverlay(w, h)
    -- ═══ PERFORMANCE: scale controls lighting resolution ═══
    -- Higher scale = fewer light samples = faster but blockier
    -- The bilinear filter smooths it out so 8 still looks good
    -- At 1920x1080: scale 4 = 129K samples (SLOW), scale 8 = 32K (smooth), scale 12 = 14K (fast)
    local scale = 8  -- <<<< LIGHTING QUALITY: 4=best/slow, 8=good/fast, 12=fastest/blocky
    if w * h > 1500000 then scale = 10 end  -- auto-boost at very high res (>~1440p)

    local sw = math.ceil(w / scale)
    local sh = math.ceil(h / scale)
    local needRecreate = not lightCanvasSmall
    if not needRecreate then
        local ok, cw, ch = pcall(function() return lightCanvasSmall:getDimensions() end)
        if not ok or cw ~= sw or ch ~= sh then needRecreate = true end
    end
    if needRecreate then
        lightCanvasSmall = love.graphics.newCanvas(sw, sh)
        lightCanvasSmall:setFilter("linear", "linear")
    end

    -- render to small canvas for smooth bilinear filtering
    love.graphics.setCanvas(lightCanvasSmall)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setBlendMode("replace")
    for sy = 0, sh - 1 do
        for sx = 0, sw - 1 do
            local screenX = (sx + 0.5) * scale
            local screenY = (sy + 0.5) * scale
            local wx = screenX / tileSize + camera.x
            local wy = screenY / tileSize + camera.y
            local r, g, b = getLightAtWorld(wx, wy)
            love.graphics.setColor(r, g, b, 1)
            love.graphics.rectangle("fill", sx, sy, 1, 1)
        end
    end
    love.graphics.setCanvas()
    love.graphics.setBlendMode("alpha")

    -- draw scaled up with linear filtering for smooth result
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setBlendMode("multiply", "premultiplied")
    love.graphics.draw(lightCanvasSmall, 0, 0, 0, scale, scale)
    love.graphics.setBlendMode("alpha")
end

-- ═══ SEC 13: love.draw() — main render dispatcher ═══
function love.draw()
    local w, h = love.graphics.getDimensions()

    if gameState == "story" then drawStoryScreen(w, h); return end
    if gameState == "charselect" then drawCharSelect(w, h); return end
    if gameState == "nameentry" then drawNameEntry(w, h); return end

    if gameState == "dead" then drawDeathScreen(w, h); return end

    if gameState == "title" and options.visible then options:draw(w, h); return end
    if gameState == "title" then drawTitle(w, h); return end
    if options.visible then options:draw(w, h); return end
    if introActive then drawIntro(w, h); return end

    love.graphics.push()
    love.graphics.translate(-camera.x * tileSize, -camera.y * tileSize)
    drawMap(w, h)
    if props then props:draw(tileSize, camera.x, camera.y, w, h) end
    drawItems(); drawOrbs(); drawEnemies(); drawBullets(); drawPlayer()
    drawChestMarkers()  -- V3: golden glow on unlooted chest rooms
    drawPortal()        -- V4: exit portal with particle effect
    love.graphics.pop()

    bomb:draw(tileSize, camera.x, camera.y)
    drawLightOverlay(w, h)

    if player.dmgFlash > 0 then
        love.graphics.setColor(1, 0, 0, player.dmgFlash * 0.5)
        love.graphics.rectangle("fill", 0, 0, w, h)
    end
    if player.sanity < 40 then
        local int = (40 - player.sanity) / 40
        love.graphics.setColor(0.15, 0, 0.2, int * 0.4)
        love.graphics.rectangle("fill", 0, 0, w, 40); love.graphics.rectangle("fill", 0, h-40, w, 40)
        love.graphics.rectangle("fill", 0, 0, 40, h); love.graphics.rectangle("fill", w-40, 0, 40, h)
    end

    -- ═══ VCR TRACKING DISTORTION: kicks in below 25% sanity ═══
    local sanityPctDraw = player.sanity / player.maxSanity
    if sanityPctDraw < 0.25 then
        local intensity = 1.0 - (sanityPctDraw / 0.25) -- 0 at 25%, 1.0 at 0%
        local t = love.timer.getTime()

        -- VCR horizontal tracking lines (wavy displaced bands)
        local bandCount = math.floor(3 + intensity * 8) -- 3-11 bands
        for i = 1, bandCount do
            local seed = i * 137.5 + t * (0.3 + intensity * 0.7)
            local bandY = (math.sin(seed * 0.7) * 0.5 + 0.5) * h
            local bandH = 2 + math.random() * (3 + intensity * 6)
            local bandAlpha = 0.08 + intensity * 0.18

            -- white/dark horizontal tear lines
            if math.sin(seed * 3.7) > 0 then
                love.graphics.setColor(1, 1, 1, bandAlpha)
            else
                love.graphics.setColor(0, 0, 0, bandAlpha * 1.5)
            end
            love.graphics.rectangle("fill", 0, bandY, w, bandH)
        end

        -- rolling bar (the big VCR tracking bar that scrolls up)
        local rollSpeed = 0.4 + intensity * 0.8
        local rollY = ((t * rollSpeed * h) % (h * 1.4)) - h * 0.2
        local rollH = 30 + intensity * 50
        local rollAlpha = 0.06 + intensity * 0.15
        love.graphics.setColor(0.1, 0, 0.15, rollAlpha)
        love.graphics.rectangle("fill", 0, rollY, w, rollH)
        -- bright edge on rolling bar
        love.graphics.setColor(1, 1, 1, rollAlpha * 0.6)
        love.graphics.rectangle("fill", 0, rollY, w, 2)
        love.graphics.rectangle("fill", 0, rollY + rollH - 1, w, 2)

        -- scanline overlay (faint horizontal lines across whole screen)
        if intensity > 0.3 then
            local scanAlpha = (intensity - 0.3) * 0.08
            for sy = 0, h, 4 do
                love.graphics.setColor(0, 0, 0, scanAlpha)
                love.graphics.rectangle("fill", 0, sy, w, 2)
            end
        end

        -- color fringing (slight RGB split feel via colored edge rectangles)
        if intensity > 0.5 then
            local fringeAlpha = (intensity - 0.5) * 0.12
            local fringeOff = math.sin(t * 7) * (2 + intensity * 4)
            love.graphics.setColor(1, 0, 0, fringeAlpha)
            love.graphics.rectangle("fill", fringeOff, 0, 2, h)
            love.graphics.setColor(0, 1, 1, fringeAlpha)
            love.graphics.rectangle("fill", w - 2 + fringeOff, 0, 2, h)
        end

        -- static noise dots (increases with intensity)
        local dotCount = math.floor(intensity * 200)
        for i = 1, dotCount do
            local dx = math.random(0, w)
            local dy = math.random(0, h)
            local bright = math.random() * 0.3
            love.graphics.setColor(bright, bright, bright, 0.15 + intensity * 0.2)
            love.graphics.rectangle("fill", dx, dy, 2, 2)
        end
    end

    drawHud(w, h); drawActiveEffects(w, h); drawMessages(w, h)
	--; drawMinimap(w, h) << that was at he end of line 1433 it brings back the minimap if uncommented, it needs that semicolon too
    if input.altFire and not paused and not gameOver then drawTacticalMap(w, h) end
    if input:getActiveMode() ~= "touch" and input:getActiveMode() ~= "gamepad" then drawCrosshair() end
    input:drawTouchControls(w, h)

    love.graphics.setColor(0.5, 0.5, 0.5, 0.5)
    love.graphics.print(input:getActiveMode():upper(), 10, h - 20)

    if input.showStatusHud and not paused and not gameOver then drawStatusHud(w, h) end
    if input.showRunStats and not paused and not gameOver then drawRunStats(w, h) end  -- V5
    if input.showControls and not paused and not gameOver then drawControlsHud(w, h) end
    if paused then drawPauseMenu(w, h) end
    if FS.perkChoiceActive then drawPerkChoice(w, h) end  -- V3: perk selection overlay
    if FS.portalPromptActive then drawPortalPrompt(w, h) end  -- V4: escape/stay prompt
    if FS.victoryActive then drawVictoryScreen(w, h) end       -- V4: victory celebration
    if gameOver then drawDeathScreen(w, h) end
end

-- ═══ SEC 14: SCREEN DRAWS — story, name entry, title, intro, pause, death ═══
function drawStoryScreen(w, h)
    local s = uiScale
    love.graphics.setColor(0, 0, 0); love.graphics.rectangle("fill", 0, 0, w, h)

    -- subtle scanline effect
    love.graphics.setColor(0, 0.04, 0, 0.3)
    for y = 0, h, 3 do
        love.graphics.line(0, y, w, y)
    end

    -- use larger story font
    if storyFont then love.graphics.setFont(storyFont) end

    -- scrolling text (doubled line height for readability)
    local lineH = math.floor(36 * s)  -- <<<< STORY LINE HEIGHT (was 22, now scales with resolution)
    -- initialize scroll so the first screen is full of text (and not under the top bar)
    if Story and not Story.inited then
        local topSafe = math.floor(60 * s)  -- keeps text below header/fade bar
        local firstTextIdx = 3              -- first non-empty line in storyLines
        local desiredY = topSafe + math.floor(10 * s)
        local startY0 = desiredY - (firstTextIdx - 1) * lineH
        Story.scrollY = h - startY0
        Story.holdTimer = 0
        Story.inited = true
    end
    local startY = h - (Story and (Story.scrollY or 0) or 0)
    love.graphics.setColor(0.1, 0.8, 0.1)  -- green terminal text
    for i, line in ipairs(storyLines) do
        local ly = startY + (i - 1) * lineH
        if ly > -lineH and ly < h + lineH then
            if line:find("%[") then
                -- blink the skip prompt
                local blink = math.sin(love.timer.getTime() * 3) > 0
                if blink then
                    love.graphics.setColor(0.1, 0.9, 0.1)
                    love.graphics.printf(line, 0, ly, w, "center")
                end
                love.graphics.setColor(0.1, 0.8, 0.1)
            else
                love.graphics.printf(line, math.floor(40*s), ly, w - math.floor(80*s), "center")
            end
        end
    end

    if defaultFont then love.graphics.setFont(defaultFont) end

    -- top/bottom fade
    love.graphics.setColor(0, 0, 0)
    love.graphics.rectangle("fill", 0, 0, w, math.floor(40*s))
    love.graphics.rectangle("fill", 0, h - math.floor(30*s), w, math.floor(30*s))

    -- header
    love.graphics.setColor(0.1, 0.5, 0.1, 0.5)
    crtPrintfBold("ASYNC RESEARCH LABS // INCIDENT REPORT", 0, math.floor(8*s), w, "center")

    -- auto-advance when scroll finishes
    local totalH = #storyLines * lineH
    if (Story and (Story.scrollY or 0) or 0) > totalH + h * 0.5 then
        gameState = "nameentry"
    end
end

----------- NAME ENTRY TERMINAL -----------
function drawNameEntry(w, h)
    local L = getNameEntryLayout(w, h)
    local s = L.s
    local cx = L.cx

    love.graphics.setColor(0, 0, 0); love.graphics.rectangle("fill", 0, 0, w, h)

    -- scanlines
    love.graphics.setColor(0, 0.03, 0, 0.2)
    for y = 0, h, 2 do
        love.graphics.line(0, y, w, y)
    end

    -- CRT glow border
    love.graphics.setColor(0, 0.15, 0, 0.3)
    love.graphics.rectangle("line", L.border, L.border, w-L.border*2, h-L.border*2, 8, 8)
    love.graphics.rectangle("line", L.border+2, L.border+2, w-L.border*2-4, h-L.border*2-4, 8, 8)

    if menuFont then love.graphics.setFont(menuFont) end
    love.graphics.setColor(0.1, 0.7, 0.1)
    love.graphics.printf("ASYNC RESEARCH TERMINAL v4.31", 0, L.yTitle, w, "center")
    love.graphics.setColor(0, 0.4, 0)
    love.graphics.printf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", 0, L.ySep, w, "center")

    love.graphics.setColor(0.1, 0.8, 0.1)
    love.graphics.printf("> NEW SUBJECT FILE", 0, L.yLine1, w, "center")
    love.graphics.printf("> ENTER SUBJECT NAME TO PROCEED", 0, L.yLine2, w, "center")

    -- name display box
    love.graphics.setColor(0, 0.2, 0, 0.5)
    love.graphics.rectangle("fill", L.boxX, L.boxY, L.boxW, L.boxH, 4, 4)
    love.graphics.setColor(0.1, 0.7, 0.1)
    love.graphics.rectangle("line", L.boxX, L.boxY, L.boxW, L.boxH, 4, 4)

    -- name text with blinking cursor
    local cursor = math.sin(love.timer.getTime() * 4) > 0 and "_" or ""
    love.graphics.setColor(0.2, 1, 0.2)
    love.graphics.printf(playerName .. cursor, L.boxX + math.floor(8*s), L.boxY + math.floor(10*s), L.boxW - math.floor(16*s), "left")

    if defaultFont then love.graphics.setFont(defaultFont) end

    -- on-screen keyboard
    for r, row in ipairs(nameKbRows) do
        for c, ch in ipairs(row) do
            local kx = L.kbStartX + (c-1) * (L.keyW + L.keyPad)
            local ky = L.kbStartY + (r-1) * (L.keyH + L.keyPad)
            local sel = (r == nameKbRow and c == nameKbCol)

            if sel then
                love.graphics.setColor(0.1, 0.7, 0.1, 0.6)
                love.graphics.rectangle("fill", kx-2, ky-2, L.keyW+4, L.keyH+4, 3, 3)
                love.graphics.setColor(0.2, 1, 0.2)
            else
                love.graphics.setColor(0, 0.15, 0, 0.4)
                love.graphics.rectangle("fill", kx, ky, L.keyW, L.keyH, 3, 3)
                love.graphics.setColor(0.1, 0.6, 0.1)
            end

            love.graphics.rectangle("line", kx, ky, L.keyW, L.keyH, 3, 3)
            love.graphics.setColor(sel and 0.2 or 0.1, sel and 1 or 0.7, sel and 0.2 or 0.1)
            love.graphics.printf(ch, kx, ky + math.floor(6*s), L.keyW, "center")
        end
    end

    -- instructions
    love.graphics.setColor(0, 0.4, 0, 0.7)
    love.graphics.printf("Select OK when finished", 0, L.yInstr, w, "center")
end


function handleNameKeyboard(key)
    if key == "return" then
        local ch = nameKbRows[nameKbRow][nameKbCol]
        if ch == "OK" then
            if playerName == "" then playerName = "Subject" end
            progression:addCharacter(playerName)
            progression:setActiveCharacter(progression:getCharacterCount())
            gameState = "title"
        elseif ch == "DEL" then
            playerName = playerName:sub(1, -2)
        else
            if #playerName < 16 then playerName = playerName .. ch end
        end
    elseif key == "backspace" then
        playerName = playerName:sub(1, -2)
    elseif key == "escape" then
        gameState = "charselect"
        charSelectIdx = 1
        charSelectDelete = false
    elseif key == "up" then
        nameKbRow = nameKbRow - 1; if nameKbRow < 1 then nameKbRow = #nameKbRows end
    elseif key == "down" then
        nameKbRow = nameKbRow + 1; if nameKbRow > #nameKbRows then nameKbRow = 1 end
    elseif key == "left" then
        nameKbCol = nameKbCol - 1; if nameKbCol < 1 then nameKbCol = #nameKbRows[nameKbRow] end
    elseif key == "right" then
        nameKbCol = nameKbCol + 1; if nameKbCol > #nameKbRows[nameKbRow] then nameKbCol = 1 end
    end
    -- actual character input handled by love.textinput
end

function handleNameGamepad(button)
    -- d-pad navigation now handled by continuous stick system in love.update
    if button == "a" then
        local ch = nameKbRows[nameKbRow][nameKbCol]
        if ch == "OK" then
            if playerName == "" then playerName = "Subject" end
            progression:addCharacter(playerName)
            progression:setActiveCharacter(progression:getCharacterCount())
            gameState = "title"
        elseif ch == "DEL" then
            playerName = playerName:sub(1, -2)
        else
            if #playerName < 16 then playerName = playerName .. ch end
        end
    elseif button == "b" then
        if #playerName > 0 then
            playerName = playerName:sub(1, -2)
        else
            gameState = "charselect"
            charSelectIdx = 1
            charSelectDelete = false
        end
    elseif button == "back" then
        gameState = "charselect"
        charSelectIdx = 1
        charSelectDelete = false
    elseif button == "start" then
        if playerName == "" then playerName = "Subject" end
        progression:addCharacter(playerName)
        progression:setActiveCharacter(progression:getCharacterCount())
        gameState = "title"
    end
end

function handleNameTouch(x, y, w, h)
    local L = getNameEntryLayout(w, h)

    for r, row in ipairs(nameKbRows) do
        for c, ch in ipairs(row) do
            local kx = L.kbStartX + (c-1) * (L.keyW + L.keyPad)
            local ky = L.kbStartY + (r-1) * (L.keyH + L.keyPad)

            if x >= kx and x <= kx+L.keyW and y >= ky and y <= ky+L.keyH then
                nameKbRow = r; nameKbCol = c

                if ch == "OK" then
                    if playerName == "" then playerName = "Subject" end
                    progression:addCharacter(playerName)
                    progression:setActiveCharacter(progression:getCharacterCount())
                    gameState = "title"
                elseif ch == "DEL" then
                    playerName = playerName:sub(1, -2)
                else
                    if #playerName < 16 then playerName = playerName .. ch end
                end
                return
            end
        end
    end
end


-- ╔══════════════════════════════════════════════════════════════╗
-- ║ CHARACTER SELECT — front-facing portrait with color picker   ║
-- ║ Player sees their character face-to-face after naming them   ║
-- ╚══════════════════════════════════════════════════════════════╝

-- ╔══════════════════════════════════════════════════════════════╗
-- ║ CHARACTER SELECT — choose existing or create new character   ║
-- ║ Up to 10 independent characters, each with own save data    ║
-- ╚══════════════════════════════════════════════════════════════╝

function drawCharSelect(w, h)
    local s = uiScale
    love.graphics.setColor(0, 0, 0); love.graphics.rectangle("fill", 0, 0, w, h)

    -- scanlines
    love.graphics.setColor(0, 0.03, 0, 0.2)
    for y = 0, h, 2 do love.graphics.line(0, y, w, y) end

    -- CRT glow border
    local border = math.floor(30*s)
    love.graphics.setColor(0, 0.15, 0, 0.3)
    love.graphics.rectangle("line", border, border, w-border*2, h-border*2, 8, 8)

    local cx = w / 2
    local count = progression:getCharacterCount()

    -- delete confirmation overlay
    if charSelectDelete then
        local summary = progression:getCharacterSummary(charSelectDeleteIdx)
        local dName = summary and summary.name or "?"

        local blockH = math.floor(140 * s)
        local topY = math.floor((h - blockH) / 2)

        love.graphics.setColor(0, 0, 0, 0.9)
        love.graphics.rectangle("fill", cx - math.floor(200*s), topY - math.floor(20*s), math.floor(400*s), blockH + math.floor(40*s), 8, 8)
        love.graphics.setColor(1, 0.3, 0.2, 0.8)
        love.graphics.rectangle("line", cx - math.floor(200*s), topY - math.floor(20*s), math.floor(400*s), blockH + math.floor(40*s), 8, 8)

        if menuFont then love.graphics.setFont(menuFont) end
        love.graphics.setColor(1, 0.3, 0.2)
        love.graphics.printf("DELETE CHARACTER?", 0, topY, w, "center")

        love.graphics.setColor(0.9, 0.8, 0.2)
        love.graphics.printf(dName:upper(), 0, topY + math.floor(30*s), w, "center")

        if summary then
            love.graphics.setColor(0.6, 0.6, 0.6)
            love.graphics.printf(summary.totalRuns.." Runs  |  Best Day "..summary.bestDay.."  |  Best Kills "..summary.bestKills.."  |  "..summary.totalTokens.." Tokens", 0, topY + math.floor(55*s), w, "center")
        end

        love.graphics.setColor(1, 0.4, 0.3)
        love.graphics.printf("This cannot be undone!", 0, topY + math.floor(80*s), w, "center")

        if defaultFont then love.graphics.setFont(defaultFont) end
        love.graphics.setColor(0.7, 0.7, 0.7)
        love.graphics.printf("[Y/A] Confirm Delete    [N/B] Cancel", 0, topY + math.floor(110*s), w, "center")
        return
    end

    -- header
    local contentH = math.floor((count + 3) * 42 * s + 120 * s)
    local baseY = math.max(math.floor(30*s), math.floor((h - contentH) / 2))

    if menuFont then love.graphics.setFont(menuFont) end
    love.graphics.setColor(0.1, 0.7, 0.1)
    love.graphics.printf("ASYNC RESEARCH TERMINAL v4.31", 0, baseY, w, "center")
    love.graphics.setColor(0, 0.4, 0)
    love.graphics.printf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", 0, baseY + math.floor(22*s), w, "center")

    love.graphics.setColor(0.1, 0.8, 0.1)
    love.graphics.printf("> SELECT SUBJECT FILE", 0, baseY + math.floor(50*s), w, "center")
    love.graphics.setColor(0, 0.5, 0)
    love.graphics.printf(count.."/"..Progression.MAX_CHARACTERS.." Subject Files on Record", 0, baseY + math.floor(72*s), w, "center")

    if defaultFont then love.graphics.setFont(defaultFont) end

    local startY = baseY + math.floor(100*s)
    local rowH = math.floor(42*s)
    local listW = math.floor(360*s)

    -- existing characters
    for i = 1, count do
        local y = startY + (i-1) * rowH
        local sel = i == charSelectIdx
        local summary = progression:getCharacterSummary(i)

        if sel then
            love.graphics.setColor(0.1, 0.5, 0.1, 0.4)
            love.graphics.rectangle("fill", cx - listW/2, y - math.floor(2*s), listW, rowH - math.floor(4*s), 4, 4)
            love.graphics.setColor(0.1, 0.7, 0.1)
            love.graphics.rectangle("line", cx - listW/2, y - math.floor(2*s), listW, rowH - math.floor(4*s), 4, 4)
        end

        -- character name
        if sel then love.graphics.setColor(0.2, 1, 0.2) else love.graphics.setColor(0.1, 0.7, 0.1) end
        local prefix = sel and "> " or "  "
        love.graphics.printf(prefix..summary.name:upper(), cx - listW/2 + math.floor(8*s), y + math.floor(4*s), math.floor(160*s), "left")-- stats (ticker): scrolling in a defined area next to each save slot
love.graphics.setColor(0, 0.5, 0)
local statsText = buildSaveStatsTicker(summary)

-- Ticker region: everything to the right of the name column inside the list box
local nameW = math.floor(160*s)
local statsX = cx - listW/2 + math.floor(8*s) + nameW + math.floor(10*s)
local statsY = y + math.floor(4*s)
local statsW = (cx + listW/2) - statsX - math.floor(12*s)
local statsH = rowH - math.floor(8*s)

drawRowTicker(statsText, statsX, statsY, statsW, statsH, 35, i * 120)
    end

    -- "New Character" option (only if not full)
    if count < Progression.MAX_CHARACTERS then
        local newIdx = count + 1
        local y = startY + count * rowH
        local sel = charSelectIdx == newIdx

        if sel then
            love.graphics.setColor(0.1, 0.5, 0.1, 0.4)
            love.graphics.rectangle("fill", cx - listW/2, y - math.floor(2*s), listW, rowH - math.floor(4*s), 4, 4)
            love.graphics.setColor(0.1, 0.7, 0.1)
            love.graphics.rectangle("line", cx - listW/2, y - math.floor(2*s), listW, rowH - math.floor(4*s), 4, 4)
        end

        if sel then love.graphics.setColor(0.2, 1, 0.2) else love.graphics.setColor(0.1, 0.7, 0.1) end
        love.graphics.printf(sel and "> + NEW SUBJECT" or "  + NEW SUBJECT", cx - listW/2 + math.floor(8*s), y + math.floor(4*s), listW, "left")
    end

    -- instructions
    local instrY = startY + (math.min(count + 1, Progression.MAX_CHARACTERS) + 1) * rowH
    instrY = math.min(instrY, h - math.floor(50*s))

    -- V4: leaderboard (show ALL saves for the selected difficulty)
do
    local rows = {}
    local countChars = progression:getCharacterCount()
    for i = 1, countChars do
        local sum = progression:getCharacterSummary(i)
        if sum then
            local bd = sum.bestDayByDiff or {0,0,0,0}
            rows[#rows+1] = {
                    idx = i,
                    name = sum.name or ("SAVE "..i),
                    bd = bd,
                    runs = sum.totalRuns or 0
                }
        end
    end

    table.sort(rows, function(a,b)
        local ad = (a.bd and a.bd[difficultyIdx]) or 0
            local bdv = (b.bd and b.bd[difficultyIdx]) or 0
            if ad == bdv then
                return (a.runs or 0) > (b.runs or 0)
            end
            return ad > bdv
    end)

    local lbY = instrY
    love.graphics.setColor(0, 0.5, 0, 0.5)
    crtPrintfBold("━━ "..difficulties[difficultyIdx]:upper().." SAVES ━━", 0, lbY, w, "center")
    lbY = lbY + math.floor(16 * s)

    love.graphics.setColor(0, 0.4, 0, 0.6)
    -- Leaderboard table: its columns exceed listW, so compute its own width and center it
local cols = {rank=0, name=22, easy=170, normal=235, getting=330, hell=430}
local lbW = math.floor((cols.hell + 60) * s) -- +60 gives padding beyond last column
local lbLeft = cx - lbW/2

crtPrintBold("#", lbLeft + math.floor(cols.rank*s), lbY)
crtPrintBold("NAME", lbLeft + math.floor(cols.name*s), lbY)
crtPrintBold("EASY", lbLeft + math.floor(cols.easy*s), lbY)
crtPrintBold("NORMAL", lbLeft + math.floor(cols.normal*s), lbY)
crtPrintBold("GETTING THERE", lbLeft + math.floor(cols.getting*s), lbY)
crtPrintBold("HELL", lbLeft + math.floor(cols.hell*s), lbY)
lbY = lbY + math.floor(14 * s)

    local maxShow = math.min(#rows, 10)
    for rank = 1, maxShow do
        local r = rows[rank]
        local isActive = r.idx == progression.activeCharIdx
        if isActive then
            love.graphics.setColor(0.2, 0.9, 0.2)
        else
            love.graphics.setColor(0, 0.55, 0, 0.8)
        end

        local nameStr = r.name
        if #nameStr > 16 then nameStr = nameStr:sub(1,15).."." end

                crtPrintBold(rank..".", lbLeft + math.floor(cols.rank*s), lbY)
        crtPrintBold(nameStr, lbLeft + math.floor(cols.name*s), lbY)
        local bd = r.bd or {0,0,0,0}
        love.graphics.print(tostring(bd[1] or 0), lbLeft + math.floor(cols.easy*s), lbY)
        love.graphics.print(tostring(bd[2] or 0), lbLeft + math.floor(cols.normal*s), lbY)
        love.graphics.print(tostring(bd[3] or 0), lbLeft + math.floor(cols.getting*s), lbY)
        love.graphics.print(tostring(bd[4] or 0), lbLeft + math.floor(cols.hell*s), lbY)
        lbY = lbY + math.floor(13 * s)
    end

    instrY = lbY + math.floor(8 * s)
end

    instrY = math.min(instrY, h - math.floor(30*s))
    love.graphics.setColor(0, 0.4, 0, 0.7)
end

function handleCharSelectKeyboard(key)
    local count = progression:getCharacterCount()
    local maxIdx = count + 1
    if count >= Progression.MAX_CHARACTERS then maxIdx = count end

    -- delete confirmation mode
    if charSelectDelete then
        if key == "y" then
            progression:deleteCharacter(charSelectDeleteIdx)
            charSelectDelete = false
            charSelectIdx = math.max(1, math.min(charSelectIdx, progression:getCharacterCount() + 1))
            if progression:getCharacterCount() >= Progression.MAX_CHARACTERS then
                charSelectIdx = math.min(charSelectIdx, progression:getCharacterCount())
            end
        elseif key == "n" or key == "escape" or key == "backspace" then
            charSelectDelete = false
        end
        return
    end

    if key == "up" then
        charSelectIdx = charSelectIdx - 1
        if charSelectIdx < 1 then charSelectIdx = maxIdx end
    elseif key == "down" then
        charSelectIdx = charSelectIdx + 1
        if charSelectIdx > maxIdx then charSelectIdx = 1 end
    elseif key == "return" or key == "space" then
        if charSelectIdx <= count then
            -- load existing character
            progression:setActiveCharacter(charSelectIdx)
            playerName = progression:getActiveCharacterName()
            gameState = "title"
            titleSelection = 1
        elseif charSelectIdx == count + 1 and count < Progression.MAX_CHARACTERS then
            -- new character
            playerName = ""
            nameKbRow = 1
            nameKbCol = 1
            gameState = "nameentry"
        end
    elseif key == "delete" or key == "x" then
        if charSelectIdx <= count then
            charSelectDeleteIdx = charSelectIdx
            charSelectDelete = true
        end
    end
end

function handleCharSelectGamepad(button)
    local count = progression:getCharacterCount()

    if charSelectDelete then
        if button == "a" then
            progression:deleteCharacter(charSelectDeleteIdx)
            charSelectDelete = false
            charSelectIdx = math.max(1, math.min(charSelectIdx, progression:getCharacterCount() + 1))
            if progression:getCharacterCount() >= Progression.MAX_CHARACTERS then
                charSelectIdx = math.min(charSelectIdx, progression:getCharacterCount())
            end
        elseif button == "b" or button == "back" then
            charSelectDelete = false
        end
        return
    end

    if button == "a" or button == "start" then
        if charSelectIdx <= count then
            progression:setActiveCharacter(charSelectIdx)
            playerName = progression:getActiveCharacterName()
            gameState = "title"
            titleSelection = 1
        elseif charSelectIdx == count + 1 and count < Progression.MAX_CHARACTERS then
            playerName = ""
            nameKbRow = 1
            nameKbCol = 1
            gameState = "nameentry"
        end
    elseif button == "x" then
        if charSelectIdx <= count then
            charSelectDeleteIdx = charSelectIdx
            charSelectDelete = true
        end
    elseif button == "b" or button == "back" then
        -- back to story (or just ignore if no character loaded)
    end
end

function drawTitle(w, h)
    local s = uiScale  -- shorthand for UI scale factor
    love.graphics.setColor(0, 0, 0); love.graphics.rectangle("fill", 0, 0, w, h)
    -- static noise
    for i = 1, 600 do
        local rx = math.random(0, w); local ry = math.random(0, h)
        love.graphics.setColor(math.random()*0.15, math.random()*0.12, math.random()*0.05)
        love.graphics.rectangle("fill", rx, ry, 2, 2)
    end

    -- calculate vertical centering
    local menuItems = {"Difficulty", "Brightness", "Music Volume", "Enemy Sounds", "Headlamp", "Aim Assist", "START", "UPGRADES", "CHARACTER", "Options", "EXIT"}
    local itemSpacing = math.floor(36 * s)
    local titleH = math.floor(142 * s)   -- title + welcome + PB line height
    local menuH = #menuItems * itemSpacing
    local totalH = titleH + menuH
    local topY = math.floor((h - totalH) / 2)  -- vertically centered

    -- title (huge font)
    local useTitleFont = titleFontHuge or titleFont
    if useTitleFont then love.graphics.setFont(useTitleFont) end
    love.graphics.setColor(0.9, 0.8, 0.2)
    love.graphics.printf("BACKROOMS SURVIVOR", 0, topY, w, "center")

    -- welcome message with player name (below title with breathing room)
    local useMenuFont = menuFont or defaultFont
    if useMenuFont then love.graphics.setFont(useMenuFont) end
    love.graphics.setColor(0.5, 0.45, 0.2)
    local welcome = playerName ~= "" and ("Subject: "..playerName.."  |  Status: STRANDED") or "There is no saving. There is no loading. Only survival."
    love.graphics.printf(welcome, 0, topY + math.floor(80 * s), w, "center")

    -- V4: personal bests for current difficulty
    if progression and playerName ~= "" then
        local stats = progression:getProfileStats(difficultyIdx)
        if stats and stats.totalRuns > 0 then
            if defaultFont then love.graphics.setFont(defaultFont) end
            love.graphics.setColor(0.4, 0.4, 0.35)
            local timeStr = stats.bestTime > 0 and string.format("%d:%02d", math.floor(stats.bestTime/60), math.floor(stats.bestTime%60)) or "--:--"
            local pbLine = "PB: Day "..stats.bestDay.."  |  "..stats.bestKills.." Kills  |  x"..stats.bestStreak.." Streak  |  "..timeStr.."  |  "..stats.totalRuns.." Runs"
            love.graphics.printf(pbLine, 0, topY + math.floor(112 * s), w, "center")
            if useMenuFont then love.graphics.setFont(useMenuFont) end
        end
    end

    local cx = w / 2
    local startY = topY + titleH
    local sliderW = math.floor(170 * s)
    local labelW = math.floor(130 * s)
    local halfMenu = math.floor(220 * s)
    local selH = math.floor(30 * s)

    for i, item in ipairs(menuItems) do
        local y = startY + (i-1) * itemSpacing; local sel = i == titleSelection
        if sel then
            love.graphics.setColor(0.4, 0.35, 0.15, 0.5)
            love.graphics.rectangle("fill", cx-halfMenu, y - math.floor(4*s), halfMenu*2, selH, 4, 4)
            love.graphics.setColor(1, 0.9, 0.3)
        else love.graphics.setColor(0.7, 0.7, 0.7) end

        if item == "Difficulty" then
            love.graphics.printf("Difficulty", cx - halfMenu + math.floor(10*s), y, labelW, "right")
            local dc = {[1]={0.3,1,0.3}, [2]={1,0.9,0.3}, [3]={1,0.5,0.2}, [4]={1,0.2,0.2}}
            love.graphics.setColor(dc[difficultyIdx])
            love.graphics.print("< "..difficulties[difficultyIdx].." >", cx - math.floor(60*s), y)
        elseif item == "Brightness" then
            love.graphics.printf("Brightness", cx - halfMenu + math.floor(10*s), y, labelW, "right")
            drawPauseSlider(cx - math.floor(60*s), y, sliderW, titleBrightness, sel)
        elseif item == "Music Volume" then
            love.graphics.printf("Music", cx - halfMenu + math.floor(10*s), y, labelW, "right")
            drawPauseSlider(cx - math.floor(60*s), y, sliderW, options.musicVolume, sel)
        elseif item == "Enemy Sounds" then
            love.graphics.printf("Enemy Sounds", cx - halfMenu + math.floor(10*s), y, labelW, "right")
            drawPauseSlider(cx - math.floor(60*s), y, sliderW, options.sfxVolume, sel)
        elseif item == "Headlamp" then
            love.graphics.printf("Headlamp", cx - halfMenu + math.floor(10*s), y, labelW, "right")
            drawPauseSlider(cx - math.floor(60*s), y, sliderW, options.headlampBrightness, sel)
        elseif item == "Aim Assist" then
            love.graphics.printf("Aim Assist", cx - halfMenu + math.floor(10*s), y, labelW, "right")
            local locked = (difficultyIdx >= 3) -- Getting Worse / Hell
            if locked then
                love.graphics.setColor(0.6, 0.6, 0.6)
                love.graphics.printf("LOCKED", cx - math.floor(60*s), y, sliderW, "left")
            else
                if aimAssist then love.graphics.setColor(0.3,1,0.3) else love.graphics.setColor(1,0.3,0.3) end
                love.graphics.printf(aimAssist and "ON" or "OFF", cx - math.floor(60*s), y, sliderW, "left")
            end
        elseif item == "Options" then
            love.graphics.printf("[ OPTIONS ]", 0, y, w, "center")
        elseif item == "UPGRADES" then
            local profile = progression and progression:getProfile(difficultyIdx)
            local tkns = profile and profile.tokens or 0
            love.graphics.printf("[ UPGRADES ]  ("..tkns.." Tokens)", 0, y, w, "center")
        elseif item == "CHARACTER" then
            local charName = progression and progression:getActiveCharacterName() or "?"
            love.graphics.printf("[ CHARACTER: "..charName:upper().." ]", 0, y, w, "center")
        elseif item == "START" then
            love.graphics.printf("[ START GAME ]", 0, y, w, "center")
        elseif item == "EXIT" then
            love.graphics.setColor(sel and {1,0.4,0.3} or {0.5,0.4,0.4})
            love.graphics.printf("[ EXIT ]", 0, y, w, "center")
        end
    end
    if defaultFont then love.graphics.setFont(defaultFont) end
    love.graphics.setColor(0.5, 0.5, 0.5)
-- brightness preview
    local previewAmbient = (difficultyAmbient[difficultyIdx] or 0.14) + titleBrightness * 0.08
    local darkness = 1.0 - math.min(1.0, previewAmbient * 3.0)
    if darkness > 0.02 then
        love.graphics.setColor(0, 0, 0, darkness * 0.85)
        love.graphics.rectangle("fill", 0, 0, w, h)
    end

    -- upgrade shop overlay (reuses death screen shop drawer)
    if showShop then
        drawUpgradeShop(w, h)
    end
end

function drawIntro(w, h)
    love.graphics.setColor(0, 0, 0); love.graphics.rectangle("fill", 0, 0, w, h)
    for i = 1, 800 do
        local rx = math.random(0, w); local ry = math.random(0, h)
        love.graphics.setColor(math.random()*0.3, 0, 0, introAlpha)
        love.graphics.rectangle("fill", rx, ry, 2, 2)
    end
    if introTimer > 1.5 then
        love.graphics.setColor(0.8, 0.8, 0.2, introAlpha)
        -- slower shake: sin-based wobble instead of random jitter
        local shakeX = math.sin(love.timer.getTime() * 1.5) * 3
        love.graphics.printf("NOCLIP DETECTED", shakeX, h/2-30, w, "center")
    elseif introTimer > 0.5 then
        love.graphics.setColor(0.8, 0.7, 0.1, introAlpha)
        love.graphics.printf(playerName:upper().." HAS ENTERED THE BACKROOMS", 0, h/2-30, w, "center")
    end
    love.graphics.setColor(0.5, 0.45, 0.2, introAlpha * 0.7)
    love.graphics.printf(difficulties[difficultyIdx]:upper().." MODE  |  Subject: "..(playerName ~= "" and playerName or "Unknown"), 0, h/2+20, w, "center")
end

function drawPauseMenu(w, h)
    local s = uiScale
    love.graphics.setColor(0, 0, 0, 0.8); love.graphics.rectangle("fill", 0, 0, w, h)

    local itemSpacing = math.floor(32 * s)
    local headerH = math.floor(70 * s)
    local menuH = #pauseItems * itemSpacing
    local totalH = headerH + menuH
    local topY = math.floor((h - totalH) / 2)

    if titleFont then love.graphics.setFont(titleFont) end
    love.graphics.setColor(1, 1, 1); love.graphics.printf("PAUSED", 0, topY, w, "center")
    if titleFont then love.graphics.setFont(defaultFont) end
    love.graphics.setColor(0.9, 0.8, 0.2)
    love.graphics.printf("Day "..wave.."  |  "..formatTime(gameTime).."  |  Kills "..kills.."  |  Streak "..player.currentStreak.."  |  "..difficulties[difficultyIdx], 0, topY + math.floor(35*s), w, "center")

    local cx = w/2
    local startY = topY + headerH
    local sliderW = math.floor(150 * s)
    local labelW = math.floor(100 * s)
    local halfMenu = math.floor(180 * s)
    local selH = math.floor(24 * s)

    for i, item in ipairs(pauseItems) do
        local y = startY + (i-1)*itemSpacing; local sel = i == pauseSelection
        if sel then love.graphics.setColor(0.4,0.35,0.15,0.5); love.graphics.rectangle("fill",cx-halfMenu,y-math.floor(3*s),halfMenu*2,selH,4,4); love.graphics.setColor(1,0.9,0.3)
        else love.graphics.setColor(0.7,0.7,0.7) end
        if item == "Music Volume" then
            love.graphics.printf("Music",cx-halfMenu+math.floor(10*s),y,labelW,"right"); drawPauseSlider(cx-math.floor(50*s),y,sliderW,options.musicVolume,sel)
        elseif item == "Enemy Sounds" then
            love.graphics.printf("Enemy Sounds",cx-halfMenu+math.floor(10*s),y,labelW,"right"); drawPauseSlider(cx-math.floor(50*s),y,sliderW,options.sfxVolume,sel)
        elseif item == "Brightness" then
            love.graphics.printf("Brightness",cx-halfMenu+math.floor(10*s),y,labelW,"right"); drawPauseSlider(cx-math.floor(50*s),y,sliderW,options.brightness,sel)
        elseif item == "Headlamp" then
            love.graphics.printf("Headlamp",cx-halfMenu+math.floor(10*s),y,labelW,"right"); drawPauseSlider(cx-math.floor(50*s),y,sliderW,options.headlampBrightness,sel)
        elseif item == "Aim Assist" then
            love.graphics.printf("Aim Assist",cx-halfMenu+math.floor(10*s),y,labelW,"right")
            local locked = (difficultyIdx >= 3) -- Getting Worse / Hell
            if locked then
                love.graphics.setColor(0.6, 0.6, 0.6)
                love.graphics.printf("LOCKED", cx-math.floor(50*s),y,sliderW,"left")
            else
                if aimAssist then love.graphics.setColor(0.3,1,0.3) else love.graphics.setColor(1,0.3,0.3) end
                love.graphics.printf(aimAssist and "ON" or "OFF", cx-math.floor(50*s),y,sliderW,"left")
            end
        elseif item == "Resume" then love.graphics.printf("[ Resume ]",0,y,w,"center")
        elseif item == "Options" then love.graphics.printf("[ Options ]",0,y,w,"center")
        elseif item == "Quit to Menu" then love.graphics.setColor(sel and {1,0.4,0.3} or {0.6,0.3,0.3}); love.graphics.printf("[ Quit to Menu ]",0,y,w,"center") end
    end
    love.graphics.setColor(0.5,0.5,0.5)
    -- (hints removed)
end

-- ═══ V3: PERK CHOICE OVERLAY — pick 1 of 2 perks on level up ═══
function drawPerkChoice(w, h)
    if not FS.perkChoices or #FS.perkChoices < 2 then return end
    local s = uiScale

    -- darken background
    love.graphics.setColor(0, 0, 0, 0.75)
    love.graphics.rectangle("fill", 0, 0, w, h)

    -- title
    if titleFont then love.graphics.setFont(titleFont) end
    love.graphics.setColor(0.9, 0.8, 0.2)
    love.graphics.printf("LEVEL UP! CHOOSE A PERK", 0, math.floor(h * 0.18), w, "center")
    love.graphics.setColor(0.6, 0.6, 0.6)
    if menuFont then love.graphics.setFont(menuFont) end
    love.graphics.printf("These perks last for this run only.", 0, math.floor(h * 0.26), w, "center")

    -- two perk cards side by side
    local cardW = math.floor(260 * s)
    local cardH = math.floor(130 * s)
    local gap = math.floor(40 * s)
    local totalW = cardW * 2 + gap
    local startX = math.floor((w - totalW) / 2)
    local cardY = math.floor(h * 0.34)

    for i = 1, 2 do
        local perk = FS.perkChoices[i]
        local cx = startX + (i - 1) * (cardW + gap)
        local sel = i == FS.perkSelection

        -- card background
        if sel then
            love.graphics.setColor(0.15, 0.3, 0.12, 0.95)
            love.graphics.rectangle("fill", cx - 3, cardY - 3, cardW + 6, cardH + 6, 8, 8)
            love.graphics.setColor(0.3, 1, 0.3, 0.9)
            love.graphics.rectangle("line", cx - 3, cardY - 3, cardW + 6, cardH + 6, 8, 8)
        else
            love.graphics.setColor(0.08, 0.08, 0.08, 0.95)
            love.graphics.rectangle("fill", cx, cardY, cardW, cardH, 6, 6)
            love.graphics.setColor(0.35, 0.35, 0.35, 0.6)
            love.graphics.rectangle("line", cx, cardY, cardW, cardH, 6, 6)
        end

        -- perk number badge
        love.graphics.setColor(sel and {1, 0.9, 0.3} or {0.45, 0.45, 0.45})
        if menuFont then love.graphics.setFont(menuFont) end
        love.graphics.printf("["..i.."]", cx, cardY + math.floor(10 * s), cardW, "center")

        -- perk name
        love.graphics.setColor(sel and {1, 1, 1} or {0.65, 0.65, 0.65})
        love.graphics.printf(perk.name:upper(), cx, cardY + math.floor(38 * s), cardW, "center")

        -- perk description
        love.graphics.setColor(sel and {0.8, 0.9, 0.7} or {0.45, 0.45, 0.45})
        if defaultFont then love.graphics.setFont(defaultFont) end
        love.graphics.printf(perk.desc, cx + math.floor(12 * s), cardY + math.floor(68 * s), cardW - math.floor(24 * s), "center")
        if menuFont then love.graphics.setFont(menuFont) end
    end

    -- instructions
    if defaultFont then love.graphics.setFont(defaultFont) end
    love.graphics.setColor(0.55, 0.55, 0.55)
    -- (hints removed)

    -- show previously chosen perks
    if #player.activeRunPerks > 0 then
        love.graphics.setColor(0.3, 0.8, 0.5, 0.6)
        local names = {}
        for _, p in ipairs(player.activeRunPerks) do names[#names + 1] = p.name end
        love.graphics.printf("Active: "..table.concat(names, ", "), 0, cardY + cardH + math.floor(48 * s), w, "center")
    end
end

-- ═══ V3: CHEST ROOM MARKERS — golden glow on unlooted chest areas ═══
function drawChestMarkers()
    local allChests = map:getAllChestRooms()
    for _, chest in ipairs(allChests) do
        if not chest.looted then
            local sx = (chest.worldX - camera.x) * tileSize
            local sy = (chest.worldY - camera.y) * tileSize
            local w, h = love.graphics.getDimensions()
            if sx > -80 and sx < w + 80 and sy > -80 and sy < h + 80 then
                local t = love.timer.getTime()
                local pulse = math.sin(t * 2) * 0.12 + 0.28
                -- outer glow
                love.graphics.setColor(0.9, 0.7, 0.1, pulse * 0.5)
                love.graphics.circle("fill", sx, sy, tileSize * 2.5)
                -- inner glow
                love.graphics.setColor(1, 0.85, 0.2, pulse * 1.2)
                love.graphics.circle("fill", sx, sy, tileSize * 0.8)
            end
        end
    end
end

-- ═══ V4: PORTAL — pulsing cyan/green circle with particle effect ═══
function drawPortal()
    local portal = map:getPortal()
    if not portal or not portal.active then return end
    local sx = (portal.x - camera.x) * tileSize
    local sy = (portal.y - camera.y) * tileSize
    local w, h = love.graphics.getDimensions()
    if sx < -120 or sx > w + 120 or sy < -120 or sy > h + 120 then return end

    local t = love.timer.getTime()
    local pulse = math.sin(t * 3) * 0.15 + 0.85

    -- outer glow ring
    love.graphics.setColor(0.1, 0.9, 0.5, 0.15 * pulse)
    love.graphics.circle("fill", sx, sy, tileSize * 3.5)

    -- mid ring
    love.graphics.setColor(0.1, 0.8, 0.9, 0.3 * pulse)
    love.graphics.circle("fill", sx, sy, tileSize * 2.0)

    -- inner bright core
    love.graphics.setColor(0.2, 1, 0.7, 0.7 * pulse)
    love.graphics.circle("fill", sx, sy, tileSize * 1.0)

    -- spinning particles
    for i = 1, 8 do
        local angle = t * 2 + (i / 8) * math.pi * 2
        local dist = tileSize * (1.5 + math.sin(t * 4 + i) * 0.4)
        local px = sx + math.cos(angle) * dist
        local py = sy + math.sin(angle) * dist
        love.graphics.setColor(0.3, 1, 0.8, 0.6)
        love.graphics.circle("fill", px, py, 3)
    end

    -- label
    local guardsLeft = enemies:countPortalGuards()
    if guardsLeft > 0 then
        love.graphics.setColor(1, 0.3, 0.2, pulse)
        love.graphics.printf(guardsLeft.." HOSTILES REMAIN", sx - 80, sy - tileSize * 4, 160, "center")
    else
        love.graphics.setColor(0.2, 1, 0.5, pulse)
        love.graphics.printf("EXIT PORTAL", sx - 60, sy - tileSize * 4, 120, "center")
    end
end

-- ═══ V4: PORTAL PROMPT — escape or stay overlay ═══
function drawPortalPrompt(w, h)
    local s = uiScale

    -- darken
    love.graphics.setColor(0, 0, 0, 0.8)
    love.graphics.rectangle("fill", 0, 0, w, h)

    -- title
    if titleFont then love.graphics.setFont(titleFont) end
    love.graphics.setColor(0.2, 1, 0.6)
    love.graphics.printf("EXIT PORTAL ACTIVE", 0, math.floor(h * 0.18), w, "center")

    if menuFont then love.graphics.setFont(menuFont) end
    love.graphics.setColor(0.7, 0.8, 0.7)
    love.graphics.printf("You cleared the horde. The portal beckons.", 0, math.floor(h * 0.27), w, "center")

    -- run stats summary
    love.graphics.setColor(0.5, 0.5, 0.5)
    local timeStr = string.format("%d:%02d", math.floor(gameTime/60), math.floor(gameTime%60))
    love.graphics.printf("Day "..wave.."  |  "..kills.." Kills  |  "..timeStr.."  |  Lv."..player.level, 0, math.floor(h * 0.33), w, "center")

    -- two choice cards
    local cardW = math.floor(240 * s)
    local cardH = math.floor(140 * s)
    local gap = math.floor(50 * s)
    local totalW = cardW * 2 + gap
    local startX = math.floor((w - totalW) / 2)
    local cardY = math.floor(h * 0.40)

    local choices = {
        {title = "ESCAPE", subtitle = "Complete your run", desc = "Earn 2x token bonus.\nYour survival is recorded.\nReturn to title screen.", color = {0.2, 1, 0.5}},
        {title = "STAY", subtitle = "Become a Living Legend", desc = "No more exits.\nThe game continues until death.\nMaximize your scores.", color = {1, 0.7, 0.2}},
    }

    for i = 1, 2 do
        local c = choices[i]
        local cx = startX + (i - 1) * (cardW + gap)
        local sel = i == FS.portalPromptChoice

        -- card bg
        if sel then
            love.graphics.setColor(0.1, 0.2, 0.1, 0.95)
            love.graphics.rectangle("fill", cx - 3, cardY - 3, cardW + 6, cardH + 6, 8, 8)
            love.graphics.setColor(c.color[1], c.color[2], c.color[3], 0.9)
            love.graphics.rectangle("line", cx - 3, cardY - 3, cardW + 6, cardH + 6, 8, 8)
        else
            love.graphics.setColor(0.06, 0.06, 0.06, 0.95)
            love.graphics.rectangle("fill", cx, cardY, cardW, cardH, 6, 6)
            love.graphics.setColor(0.3, 0.3, 0.3, 0.5)
            love.graphics.rectangle("line", cx, cardY, cardW, cardH, 6, 6)
        end

        -- number badge
        love.graphics.setColor(sel and c.color or {0.4, 0.4, 0.4})
        if menuFont then love.graphics.setFont(menuFont) end
        love.graphics.printf("["..i.."]", cx, cardY + math.floor(10 * s), cardW, "center")

        -- title
        love.graphics.setColor(sel and {1, 1, 1} or {0.5, 0.5, 0.5})
        love.graphics.printf(c.title, cx, cardY + math.floor(36 * s), cardW, "center")

        -- subtitle
        love.graphics.setColor(sel and c.color or {0.4, 0.4, 0.4})
        if defaultFont then love.graphics.setFont(defaultFont) end
        love.graphics.printf(c.subtitle, cx, cardY + math.floor(60 * s), cardW, "center")

        -- description
        love.graphics.setColor(sel and {0.7, 0.8, 0.7} or {0.35, 0.35, 0.35})
        love.graphics.printf(c.desc, cx + math.floor(10 * s), cardY + math.floor(80 * s), cardW - math.floor(20 * s), "center")
    end

    -- instructions
    if defaultFont then love.graphics.setFont(defaultFont) end
    love.graphics.setColor(0.5, 0.5, 0.5)
    -- (hints removed)
end

-- ═══ V4: VICTORY SCREEN — successful escape celebration ═══
function drawVictoryScreen(w, h)
    local s = uiScale

    love.graphics.setColor(0, 0, 0); love.graphics.rectangle("fill", 0, 0, w, h)

    -- ambient particles
    local t = love.timer.getTime()
    for i = 1, 40 do
        local px = (math.sin(t * 0.3 + i * 7.3) * 0.5 + 0.5) * w
        local py = (math.cos(t * 0.2 + i * 5.7) * 0.5 + 0.5) * h
        local brightness = math.sin(t * 2 + i) * 0.3 + 0.4
        love.graphics.setColor(0.1, brightness, brightness * 0.7, 0.3)
        love.graphics.circle("fill", px, py, 2 + math.sin(t + i) * 1.5)
    end

    local centerY = math.floor(h * 0.12)

    -- title
    if titleFontHuge or titleFont then love.graphics.setFont(titleFontHuge or titleFont) end
    love.graphics.setColor(0.2, 1, 0.5)
    love.graphics.printf("ESCAPED", 0, centerY, w, "center")

    if titleFont then love.graphics.setFont(titleFont) end
    love.graphics.setColor(0.8, 0.9, 0.7)
    love.graphics.printf(playerName.." found the way out.", 0, centerY + math.floor(65 * s), w, "center")

    -- stats block
    if menuFont then love.graphics.setFont(menuFont) end
    local statsY = centerY + math.floor(120 * s)
    local lineH = math.floor(30 * s)

    love.graphics.setColor(0.9, 0.8, 0.2)
    love.graphics.printf("FINAL STATS", 0, statsY, w, "center")
    statsY = statsY + lineH + math.floor(5 * s)

    if defaultFont then love.graphics.setFont(defaultFont) end
    local statLines = {
        {"Day Survived", tostring(wave)},
        {"Total Kills", tostring(kills)},
        {"Best Streak", tostring(player.bestRunStreak)},
        {"Level Reached", tostring(player.level)},
        {"Time Survived", string.format("%d:%02d", math.floor(gameTime/60), math.floor(gameTime%60))},
        {"Difficulty", difficulties[difficultyIdx] or "?"},
    }

    for _, line in ipairs(statLines) do
        love.graphics.setColor(0.6, 0.6, 0.6)
        love.graphics.printf(line[1], w/2 - math.floor(180*s), statsY, math.floor(160*s), "right")
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf(line[2], w/2 + math.floor(20*s), statsY, math.floor(160*s), "left")
        statsY = statsY + math.floor(20 * s)
    end

    -- perks
    if #player.activeRunPerks > 0 then
        statsY = statsY + math.floor(8 * s)
        local names = {}
        for _, p in ipairs(player.activeRunPerks) do names[#names + 1] = p.name end
        love.graphics.setColor(0.3, 0.8, 0.5, 0.7)
        love.graphics.printf("Perks: "..table.concat(names, ", "), 0, statsY, w, "center")
        statsY = statsY + math.floor(20 * s)
    end

    -- token reward
    statsY = statsY + math.floor(15 * s)
    if menuFont then love.graphics.setFont(menuFont) end
    love.graphics.setColor(0.9, 0.8, 0.2)
    love.graphics.printf("+"..FS.victoryTokens.." TOKENS (2x Escape Bonus!)", 0, statsY, w, "center")

    -- continue prompt
    statsY = statsY + math.floor(50 * s)
    if defaultFont then love.graphics.setFont(defaultFont) end
    local blink = math.sin(t * 3) > 0
    if blink then love.graphics.setColor(0.7, 0.8, 0.7) else love.graphics.setColor(0.4, 0.5, 0.4) end
    love.graphics.printf("[ Press Enter / A to continue ]", 0, statsY, w, "center")
end

function drawDeathScreen(w, h)
    local s = uiScale
    love.graphics.setColor(0, 0, 0, 0.85); love.graphics.rectangle("fill", 0, 0, w, h)

    if showShop then
        drawUpgradeShop(w, h)
        return
    end

    -- center the death screen content vertically
    local blockH = math.floor(200 * s)
    local topY = math.floor((h - blockH) / 2)

    love.graphics.setColor(1, 0.2, 0.2); love.graphics.printf(playerName:upper().." DIED IN THE BACKROOMS", 0, topY, w, "center")
    love.graphics.setColor(0.9, 0.8, 0.2); love.graphics.printf(playerName.." survived "..wave.." Day"..(wave>1 and "s" or ""), 0, topY + math.floor(35*s), w, "center")
    love.graphics.setColor(0.7, 0.7, 0.7); love.graphics.printf("Time: "..formatTime(gameTime).."  |  Kills: "..kills.."  |  Level: "..player.level.."  |  Best Streak: "..player.bestRunStreak, 0, topY + math.floor(60*s), w, "center")

    -- tokens earned
    love.graphics.setColor(1, 0.85, 0.2)
    love.graphics.printf("+"..tokensEarned.." Tokens Earned", 0, topY + math.floor(90*s), w, "center")
    local profile = progression and progression:getProfile(difficultyIdx)
    if profile then
        love.graphics.setColor(0.7, 0.6, 0.2)
        love.graphics.printf("Total Tokens: "..profile.tokens.."  |  Best Day: "..profile.bestDay.."  |  Best Streak: "..(profile.bestStreak or 0).."  |  Runs: "..profile.totalRuns, 0, topY + math.floor(112*s), w, "center")
    end

    -- V3: show active perks on death screen
    if #player.activeRunPerks > 0 then
        local names = {}
        for _, p in ipairs(player.activeRunPerks) do names[#names + 1] = p.name end
        love.graphics.setColor(0.3, 0.8, 0.5, 0.7)
        love.graphics.printf("Perks: "..table.concat(names, ", "), 0, topY + math.floor(130*s), w, "center")
    end

    -- menu options
    local deathItems = {"[ TRY AGAIN ]", "[ UPGRADES ]", "[ MAIN MENU ]"}
    local menuStartY = topY + math.floor(155*s)
    local menuSpacing = math.floor(28*s)
    for i, label in ipairs(deathItems) do
        local y = menuStartY + (i-1) * menuSpacing
        local sel = i == deathSelection
        if sel then
            love.graphics.setColor(0.4, 0.35, 0.15, 0.5)
            love.graphics.rectangle("fill", w/2 - math.floor(120*s), y - math.floor(3*s), math.floor(240*s), math.floor(24*s), 4, 4)
            love.graphics.setColor(1, 0.9, 0.3)
        else
            love.graphics.setColor(0.6, 0.6, 0.6)
        end
        love.graphics.printf(label, 0, y, w, "center")
    end

    love.graphics.setColor(0.5, 0.5, 0.5); love.graphics.printf(playerName.." was lost in the Backrooms.", 0, menuStartY + 3 * menuSpacing + math.floor(8*s), w, "center")
end

function drawUpgradeShop(w, h)
    local s = uiScale
    love.graphics.setColor(0, 0, 0, 0.95); love.graphics.rectangle("fill", 0, 0, w, h)

    local profile = progression and progression:getProfile(difficultyIdx)
    local tokens = profile and profile.tokens or 0

    -- header
    if titleFont then love.graphics.setFont(titleFont) end
    love.graphics.setColor(0.9, 0.8, 0.2)
    love.graphics.printf("UPGRADES", 0, math.floor(20*s), w, "center")
    if menuFont then love.graphics.setFont(menuFont) end
    love.graphics.setColor(1, 0.85, 0.2)
    love.graphics.printf("Tokens: "..tokens.."  |  "..difficulties[difficultyIdx].." Profile", 0, math.floor(55*s), w, "center")
    if defaultFont then love.graphics.setFont(defaultFont) end

    -- upgrade list
    local startY = math.floor(90*s)
    local rowH = math.floor(32*s)
    local cx = w/2
    local listW = math.floor(380*s)

    for i, def in ipairs(Progression.UPGRADES) do
        local y = startY + (i-1) * rowH
        if y > h - math.floor(60*s) then break end  -- don't draw off screen

        local level = progression:getUpgradeLevel(difficultyIdx, def.id)
        local maxed = level >= def.maxLevel
        local cost = progression:getUpgradeCost(def.id, level)
        local canBuy = not maxed and tokens >= cost
        local sel = i == shopSelection

        -- highlight bar
        if sel then
            love.graphics.setColor(0.3, 0.25, 0.1, 0.6)
            love.graphics.rectangle("fill", cx - listW/2, y - math.floor(2*s), listW, rowH - math.floor(4*s), 4, 4)
        end

        -- name
        if sel then love.graphics.setColor(1, 0.9, 0.3) else love.graphics.setColor(0.7, 0.7, 0.7) end
        love.graphics.printf(def.name, cx - listW/2 + math.floor(8*s), y + math.floor(4*s), math.floor(140*s), "left")

        -- level pips
        local pipX = cx - listW/2 + math.floor(155*s)
        for p = 1, def.maxLevel do
            if p <= level then
                love.graphics.setColor(0.3, 1, 0.3)
            else
                love.graphics.setColor(0.2, 0.2, 0.2)
            end
            local pipW = math.max(2, math.floor(math.min(10, 100 / def.maxLevel) * s))
            love.graphics.rectangle("fill", pipX + (p-1) * (pipW + 2), y + math.floor(8*s), pipW, math.floor(10*s), 1, 1)
        end

        -- cost or MAXED
        local costX = cx + listW/2 - math.floor(70*s)
        if maxed then
            love.graphics.setColor(0.4, 0.8, 0.4)
            love.graphics.printf("MAXED", costX, y + math.floor(4*s), math.floor(65*s), "right")
        else
            if canBuy then love.graphics.setColor(1, 0.85, 0.2) else love.graphics.setColor(0.5, 0.3, 0.2) end
            love.graphics.printf(cost.." T", costX, y + math.floor(4*s), math.floor(65*s), "right")
        end
    end

    -- description of selected upgrade
    local selDef = Progression.UPGRADES[shopSelection]
    if selDef then
        local descY = math.min(startY + #Progression.UPGRADES * rowH + math.floor(10*s), h - math.floor(60*s))
        love.graphics.setColor(0.6, 0.6, 0.6)
        love.graphics.printf(selDef.desc, 0, descY, w, "center")
    end

    -- instructions
    love.graphics.setColor(0.5, 0.5, 0.5)
end

function drawPauseSlider(x, y, sw, value, sel)
    local s = uiScale
    local barH = math.floor(12 * s)
    local knobR = math.floor(7 * s)
    local barY = y + math.floor(4 * s)
    love.graphics.setColor(0.15, 0.15, 0.15); love.graphics.rectangle("fill", x, barY, sw, barH, 4, 4)
    love.graphics.setColor(sel and {0.9,0.8,0.2} or {0.5,0.45,0.2}); love.graphics.rectangle("fill", x, barY, sw*value, barH, 4, 4)
    love.graphics.setColor(1,1,1,sel and 1 or 0.6); love.graphics.circle("fill", x+sw*value, barY + barH/2, knobR)
    love.graphics.setColor(0.3,0.3,0.3); love.graphics.circle("line", x+sw*value, barY + barH/2, knobR)
    love.graphics.setColor(1,1,1); love.graphics.print(math.floor(value*100).."%", x+sw+math.floor(14*s), y+math.floor(1*s))
end

function drawCrosshair()
    local mx,my = love.mouse.getPosition()
    love.graphics.setColor(1,0.3,0.2,0.8); love.graphics.setLineWidth(2)
    love.graphics.line(mx-10,my,mx-4,my); love.graphics.line(mx+4,my,mx+10,my)
    love.graphics.line(mx,my-10,mx,my-4); love.graphics.line(mx,my+4,mx,my+10)
    love.graphics.circle("line",mx,my,3); love.graphics.setLineWidth(1)
end

-- ═══ SEC 15: MAP / ITEM / ORB DRAWING — tiles, walls, blood, pickups ═══
function drawMap(w, h)
    local vx0 = math.floor(camera.x) - 1
    local vy0 = math.floor(camera.y) - 1
    local vx1 = vx0 + math.ceil(w / tileSize) + 3
    local vy1 = vy0 + math.ceil(h / tileSize) + 3

    for ty = vy0, vy1 do
        for tx = vx0, vx1 do
            local sx = tx * tileSize
            local sy = ty * tileSize

            -- FLOOR (always draws first, even under wall tiles)
            if floorImg and floorQuad then
                love.graphics.setColor(1,1,1,1)
                love.graphics.draw(floorImg, floorQuad, sx, sy)
            else
                if (tx + ty) % 2 == 0 then love.graphics.setColor(0.28,0.25,0.18) else love.graphics.setColor(0.25,0.22,0.15) end
                love.graphics.rectangle("fill", sx, sy, tileSize, tileSize)
            end
            -- TILE TYPES:
            --   0 = playable floor
            --   1 = wall (solid)
            --   2 = void (non-playable dead space; render green; blocks movement/LOS; never spawns)
            local t = map:get(tx, ty)

            -- VOID: non-playable dead space
            if t == 2 then
                love.graphics.setColor(0.10, 0.35, 0.12, 0.55)
                love.graphics.rectangle("fill", sx, sy, tileSize, tileSize)

            
-- VOID / DEAD AREA (tile==2): draw warped, pulsing dead-area texture (no seams)
if map:get(tx, ty) == 2 and deadAreaImg and deadAreaShader then
    love.graphics.setShader(deadAreaShader)
    deadAreaShader:send("time", love.timer.getTime())
    deadAreaShader:send("uvScale", 220.0)
    deadAreaShader:send("cam", {camera.x * tileSize, camera.y * tileSize})

    love.graphics.setColor(1,1,1,1)
    local sxScale = tileSize / deadAreaImg:getWidth()
    local syScale = tileSize / deadAreaImg:getHeight()
    love.graphics.draw(deadAreaImg, sx, sy, 0, sxScale, syScale)

    love.graphics.setShader()
end

-- WALLS: gameplay footprint remains a full solid 32x32 tile (collision/LOS).
            -- Cosmetic: draw a subtle full-tile base (so walls still read as “solid” right up
            -- against the player), then overlay a skinny 1/2-tile core for style.
            elseif t == 1 then
                -- subtle full-tile base so the player can visually “hug” the wall without a dead-zone feel
                if wallTopImg then
                    -- Use the wood texture as a subtle full-tile base so corners/ends never look "cut off".
                    love.graphics.setColor(1,1,1,0.22)
                    local baseQuad = love.graphics.newQuad(0, 0, tileSize, tileSize, wallTopImg:getDimensions())
                    love.graphics.draw(wallTopImg, baseQuad, sx, sy)
                else
                    love.graphics.setColor(0,0,0,0.14)
                    love.graphics.rectangle("fill", sx, sy, tileSize, tileSize)
                end

                local rects = map:getWallRects(tx, ty)
                if rects then
                    for i = 1, #rects do
                        local r = rects[i]
                        local wx = r.x * tileSize
                        local wy = r.y * tileSize
                        local ww = r.w * tileSize
                        local wh = r.h * tileSize

                        if wallTopImg then
                            love.graphics.setColor(1,1,1,1)
                            local quad = love.graphics.newQuad(0, 0, ww, wh, wallTopImg:getDimensions())
                            love.graphics.draw(wallTopImg, quad, wx, wy)
                        else
                            -- avoid pure black; let carpet + lighting carry most of the darkness
                            love.graphics.setColor(0.22, 0.22, 0.22, 0.95)
                            love.graphics.rectangle("fill", wx, wy, ww, wh)
                            love.graphics.setColor(0,0,0,0.25)
                            love.graphics.rectangle("line", wx, wy, ww, wh)
                        end
                    end
                end
            end
        end
    end

    -- blood marks
    -- blood marks
    local bloods = map:getBloodInRegion(vx0, vy0, vx1, vy1)
    for _, b in ipairs(bloods) do
        local bsx = b.x * tileSize + tileSize/2
        local bsy = b.y * tileSize + tileSize/2
        local s = (b.size or 0.5) * tileSize
        if b.btype == 1 then
            -- blood splatter: irregular dots
            love.graphics.setColor(0.35,0.03,0.02,0.35)
            love.graphics.circle("fill", bsx, bsy, s*0.6)
            love.graphics.setColor(0.4,0.05,0.03,0.25)
            love.graphics.circle("fill", bsx+s*0.4, bsy-s*0.3, s*0.3)
            love.graphics.circle("fill", bsx-s*0.5, bsy+s*0.2, s*0.25)
            love.graphics.setColor(0.3,0.02,0.01,0.2)
            love.graphics.circle("fill", bsx+s*0.2, bsy+s*0.5, s*0.2)
        elseif b.btype == 2 then
            -- blood drag mark: smeared with splatter details
            local dx = math.cos(b.angle or 0) * s * 2
            local dy = math.sin(b.angle or 0) * s * 2
            -- main drag smear (tapered)
            love.graphics.setColor(0.35,0.04,0.02,0.3)
            local perpX = -math.sin(b.angle or 0) * s * 0.2
            local perpY = math.cos(b.angle or 0) * s * 0.2
            love.graphics.polygon("fill",
                bsx-dx-perpX*2, bsy-dy-perpY*2,
                bsx-dx+perpX*2, bsy-dy+perpY*2,
                bsx+dx+perpX*0.5, bsy+dy+perpY*0.5,
                bsx+dx-perpX*0.5, bsy+dy-perpY*0.5)
            -- parallel streak lines
            love.graphics.setColor(0.4,0.06,0.03,0.2)
            love.graphics.setLineWidth(1)
            for streak = -1, 1 do
                local ox = perpX * streak * 1.5
                local oy = perpY * streak * 1.5
                love.graphics.line(bsx-dx*0.8+ox, bsy-dy*0.8+oy, bsx+dx*0.9+ox, bsy+dy*0.9+oy)
            end
            -- splatter dots along drag path
            love.graphics.setColor(0.4,0.04,0.02,0.25)
            for sp = 1, 4 do
                local t = sp / 5
                local spx = bsx + dx * (t * 2 - 1) + (math.sin(b.angle * sp) * s * 0.6)
                local spy = bsy + dy * (t * 2 - 1) + (math.cos(b.angle * sp) * s * 0.4)
                love.graphics.circle("fill", spx, spy, s * 0.15 + sp * 0.3)
            end
            -- origin pool (wider end of drag)
            love.graphics.setColor(0.3,0.03,0.01,0.35)
            love.graphics.ellipse("fill", bsx-dx, bsy-dy, s*0.5, s*0.35)
            love.graphics.setLineWidth(1)
        else
            -- handprint
            love.graphics.setColor(0.35,0.04,0.02,0.3)
            love.graphics.push()
            love.graphics.translate(bsx, bsy)
            love.graphics.rotate(b.angle)
            love.graphics.ellipse("fill", 0, 0, s*0.5, s*0.4)
            -- fingers
            for f = -2, 2 do
                love.graphics.ellipse("fill", f*s*0.2, -s*0.55, s*0.08, s*0.2)
            end
            love.graphics.pop()
        end
    end
end

function drawItems()
    for _, item in ipairs(items.list) do
        local sx = item.x*tileSize; local sy = item.y*tileSize
        local p = math.sin(item.pulseTimer*3)*0.3+0.7
        love.graphics.setColor(0,0,0,0.6); love.graphics.circle("fill",sx,sy,7)
        love.graphics.setColor(item.color[1]*p,item.color[2]*p,item.color[3]*p); love.graphics.circle("fill",sx,sy,5)
        if item.type == "bomb" then
            love.graphics.setColor(1,0.3,0.1); love.graphics.circle("line",sx,sy,4)
            love.graphics.setColor(1,0.8,0.3); love.graphics.line(sx,sy-5,sx+2,sy-8)
        elseif item.type == "ammo" then
            love.graphics.setColor(0.9,0.7,0.1); love.graphics.rectangle("fill",sx-2,sy-3,4,6)
            love.graphics.setColor(1,0.9,0.3); love.graphics.rectangle("fill",sx-1,sy-4,2,2)
        elseif item.type == "weapon" then
            -- draw weapon shape based on weaponId
            local c = item.color
            local wid = item.weaponId or 2
            if wid == 1 then -- machete
                love.graphics.setColor(0.25, 0.15, 0.08)
                love.graphics.setLineWidth(2)
                love.graphics.line(sx+3,sy+3,sx+1,sy+1) -- handle
                love.graphics.setColor(0.75,0.78,0.82)
                love.graphics.setLineWidth(1.5)
                love.graphics.line(sx+1,sy+1,sx-5,sy-5) -- blade
                love.graphics.setColor(0.9,0.92,0.95,0.6)
                love.graphics.setLineWidth(0.5)
                love.graphics.line(sx,sy,sx-5,sy-5.5) -- edge
                love.graphics.setColor(0.5,0.5,0.45)
                love.graphics.setLineWidth(1.5)
                love.graphics.line(sx+1,sy-0.5,sx+1,sy+2) -- guard
            elseif wid == 2 then -- knife
                love.graphics.setColor(0.2,0.2,0.18)
                love.graphics.setLineWidth(2)
                love.graphics.line(sx+2,sy+3,sx+1,sy+1) -- handle
                love.graphics.setColor(0.5,0.5,0.48)
                love.graphics.setLineWidth(1.2)
                love.graphics.line(sx,sy-0.5,sx+2,sy+0.5) -- guard
                love.graphics.setColor(0.7,0.72,0.78)
                love.graphics.polygon("fill", sx-0.8,sy, sx+0.8,sy, sx,sy-5) -- blade
            elseif wid == 3 then -- pipe
                love.graphics.setColor(0.45,0.45,0.48)
                love.graphics.setLineWidth(2.5)
                love.graphics.line(sx-1,sy-6,sx+1,sy+6)
                love.graphics.setColor(0.3,0.3,0.32)
                love.graphics.setLineWidth(3)
                love.graphics.line(sx-1,sy-6,sx-1,sy-5) -- thread
                love.graphics.line(sx+1,sy+5,sx+1,sy+6)
                love.graphics.setColor(0.6,0.6,0.65,0.3)
                love.graphics.setLineWidth(0.5)
                love.graphics.line(sx,sy-5,sx,sy+5) -- highlight
            elseif wid == 4 then -- axe
                love.graphics.setColor(0.4,0.25,0.12)
                love.graphics.setLineWidth(1.8)
                love.graphics.line(sx,sy-6,sx,sy+5) -- handle
                love.graphics.setColor(0.55,0.55,0.58)
                love.graphics.polygon("fill", sx-3,sy-5, sx+3,sy-5, sx+2,sy-2, sx-2,sy-2) -- head
                love.graphics.setColor(0.8,0.82,0.85)
                love.graphics.setLineWidth(0.8)
                love.graphics.line(sx-3,sy-5, sx+3,sy-5) -- edge
            elseif wid == 5 then -- pistol
                love.graphics.setColor(0.3,0.3,0.32)
                love.graphics.polygon("fill", sx-4,sy-1.5, sx+3,sy-1.5, sx+3,sy+1, sx-4,sy+1) -- slide
                love.graphics.setColor(0.25,0.25,0.27)
                love.graphics.setLineWidth(1.5)
                love.graphics.line(sx+3,sy,sx+5,sy) -- barrel
                love.graphics.setColor(0.22,0.22,0.2)
                love.graphics.polygon("fill", sx-1,sy+1, sx-1.5,sy+4, sx+1,sy+3.5, sx+1,sy+1) -- grip
                love.graphics.setColor(0.1,0.1,0.1)
                love.graphics.circle("fill",sx+5.2,sy,0.5) -- muzzle
            elseif wid == 6 then -- shotgun
                love.graphics.setColor(0.3,0.3,0.32)
                love.graphics.polygon("fill", sx-2,sy-1.2, sx+2,sy-1.2, sx+2,sy+1, sx-2,sy+1) -- receiver
                love.graphics.setColor(0.25,0.25,0.27)
                love.graphics.setLineWidth(1.8)
                love.graphics.line(sx+2,sy,sx+7,sy) -- barrel
                love.graphics.setColor(0.4,0.25,0.12)
                love.graphics.setLineWidth(2)
                love.graphics.line(sx-2,sy+0.5,sx-5,sy+1.5) -- stock
                love.graphics.setColor(0.35,0.22,0.1)
                love.graphics.setLineWidth(2)
                love.graphics.line(sx+4,sy+0.5,sx+5.5,sy+0.5) -- foregrip
                love.graphics.setColor(1,0.3,0.1)
                love.graphics.circle("fill",sx+6.5,sy-1,0.4) -- bead sight
            elseif wid == 7 then -- smg
                love.graphics.setColor(0.32,0.32,0.36)
                love.graphics.polygon("fill", sx-3,sy-1.5, sx+4,sy-1.5, sx+4,sy+1.2, sx-3,sy+1.2) -- body
                love.graphics.setColor(0.25,0.25,0.28)
                love.graphics.setLineWidth(1.8)
                love.graphics.line(sx+4,sy,sx+6,sy) -- barrel
                love.graphics.setColor(0.28,0.28,0.3)
                love.graphics.polygon("fill", sx,sy+1.2, sx,sy+4, sx+1.5,sy+4, sx+1.5,sy+1.2) -- magazine
                love.graphics.setColor(0.1,0.1,0.1)
                love.graphics.circle("fill",sx+6.2,sy,0.5)
            elseif wid == 8 then -- suppressed pistol
                love.graphics.setColor(0.22,0.22,0.24)
                love.graphics.polygon("fill", sx-2,sy-1, sx+2,sy-1, sx+2,sy+0.8, sx-2,sy+0.8) -- body
                love.graphics.setColor(0.18,0.18,0.2)
                love.graphics.setLineWidth(2)
                love.graphics.line(sx+2,sy,sx+7,sy) -- suppressor
                love.graphics.setColor(0.25,0.25,0.28)
                love.graphics.setLineWidth(2.2)
                love.graphics.line(sx+2.5,sy,sx+3.5,sy) -- ring
                love.graphics.setColor(0.2,0.2,0.18)
                love.graphics.polygon("fill", sx-1,sy+0.8, sx-1.5,sy+3.5, sx+0.5,sy+3, sx+0.5,sy+0.8) -- grip
                love.graphics.setColor(0.12,0.12,0.14)
                love.graphics.circle("fill",sx+7.2,sy,0.8) -- tip
            else
                love.graphics.setColor(c[1],c[2],c[3])
                love.graphics.rectangle("fill",sx-1,sy-6,2,12)
            end
        elseif item.type == "battery" then
            love.graphics.setColor(0.2,1,0.6); love.graphics.rectangle("fill",sx-3,sy-4,6,8)
            love.graphics.setColor(0.1,0.7,0.4); love.graphics.rectangle("fill",sx-1,sy-6,2,2)
            love.graphics.setColor(1,1,0.8,0.5); love.graphics.rectangle("fill",sx-1,sy-2,2,4)
        end
        if math.sin(item.pulseTimer*4)>0.3 then love.graphics.setColor(1,1,1,0.4); love.graphics.circle("line",sx,sy,6) end
    end
end

function drawOrbs()
    for _, orb in ipairs(orbs.list) do
        local sx = orb.x*tileSize; local sy = orb.y*tileSize
        local p = math.sin(orb.pulseTimer*3)*0.3+0.7
        local ch = orb.state == "chase"
        local buff = orb.isBuff  -- true=green(buff), false=yellow(nerf)

        -- color palettes: green for buffs, yellow/amber for nerfs
        local glowR, glowG, glowB       -- outer glow
        local coreR, coreG, coreB       -- dark center tint
        local partR, partG, partB       -- orbiting particles
        local eyeR, eyeG, eyeB         -- chase eyes
        local symR, symG, symB         -- idle symbol
        local specR, specG, specB       -- specular highlight
        if buff then
            glowR, glowG, glowB = 0.1, 0.9, 0.35
            coreR, coreG, coreB = 0.03, 0.08, 0.04
            partR, partG, partB = 0.3, 1, 0.5
            eyeR, eyeG, eyeB = 0.3, 1, 0.4
            symR, symG, symB = 0.3, 0.8, 0.5
            specR, specG, specB = 0.7, 1, 0.8
        else
            glowR, glowG, glowB = 0.95, 0.75, 0.15
            coreR, coreG, coreB = 0.08, 0.06, 0.02
            partR, partG, partB = 1, 0.85, 0.3
            eyeR, eyeG, eyeB = 1, 0.9, 0.3
            symR, symG, symB = 0.8, 0.7, 0.2
            specR, specG, specB = 1, 0.95, 0.7
        end

        -- ═══ GLOW AURA ═══
        love.graphics.setColor(glowR*0.3, glowG*0.3, glowB*0.3, 0.08 * p)
        love.graphics.circle("fill", sx, sy, 32)
        love.graphics.setColor(glowR*0.5, glowG*0.5, glowB*0.5, 0.12 * p)
        love.graphics.circle("fill", sx, sy, 22)
        love.graphics.setColor(glowR*0.6, glowG*0.6, glowB*0.6, 0.18 * p)
        love.graphics.circle("fill", sx, sy, ch and 16 or 13)

        -- ═══ ORB CORE ═══
        love.graphics.setColor(coreR, coreG, coreB)
        love.graphics.circle("fill", sx, sy, 8 + p)

        -- ═══ ORBITING PARTICLES ═══
        for j = 0, 3 do
            local pa = orb.particleAngle + j * math.pi / 2
            local pr = 9 + p * 2
            love.graphics.setColor(partR, partG, partB, 0.7)
            love.graphics.circle("fill", sx + math.cos(pa) * pr, sy + math.sin(pa) * pr, 2)
            local trailAngle = pa - 0.3
            love.graphics.setColor(partR*0.7, partG*0.7, partB*0.7, 0.3)
            love.graphics.circle("fill", sx + math.cos(trailAngle) * pr, sy + math.sin(trailAngle) * pr, 1.2)
        end

        -- ═══ INNER DETAIL ═══
        if ch then
            love.graphics.setColor(eyeR, eyeG, eyeB)
            love.graphics.circle("fill", sx - 3, sy - 1, 2)
            love.graphics.circle("fill", sx + 3, sy - 1, 2)
            love.graphics.setColor(glowR, glowG, glowB, 0.3 * p)
            love.graphics.circle("fill", sx, sy, 5)
        else
            love.graphics.setColor(symR, symG, symB)
            love.graphics.printf(buff and "+" or "?", sx - 6, sy - 7, 12, "center")
        end

        -- ═══ SPECULAR HIGHLIGHT ═══
        love.graphics.setColor(specR, specG, specB, 0.25 * p)
        love.graphics.circle("fill", sx - 2, sy - 3, 2.5)
    end
end

-- ╔══════════════════════════════════════════════════════════════╗
-- ║ SEC 16: ENEMY DRAWING — Slenderman-style entities           ║
-- ║                                                             ║
-- ║ Each enemy drawn with sc = type size * charScale so they    ║
-- ║ scale with camera zoom AND vary by enemy type.              ║
-- ║                                                             ║
-- ║ DRAW ORDER (back to front):                                 ║
-- ║   Aura glow > Shadow > Legs > Torso > Tie > Arms+Fingers > ║
-- ║   Head > Face shadow > Eyes (state-colored) > HP bar        ║
-- ║                                                             ║
-- ║ ENEMY TYPES (see enemies.lua):                              ║
-- ║   Hound (RED tie)     sc=1.00  Fast, weak                  ║
-- ║   Crawler (GREEN tie) sc=1.43  Slow tank                   ║
-- ║   Wretch (YELLOW tie) sc=0.71  Tiny swarm                  ║
-- ║   Shade (PURPLE tie)  sc=0.86  Invisible in dark            ║
-- ║   Skin Stealer (ORANGE tie) sc=1.57  Boss enemy             ║
-- ║                                                             ║
-- ║ EYE COLORS BY STATE:                                        ║
-- ║   Wander = no eyes visible (faceless)                       ║
-- ║   Search = dim yellow eyes                                  ║
-- ║   Hunt   = bright red glowing eyes + mouth slit             ║
-- ╚══════════════════════════════════════════════════════════════╝
function drawEnemies()
    local z = charScale  -- camera zoom multiplier
    for _, e in ipairs(enemies.list) do
        local sx = e.x*tileSize; local sy = e.y*tileSize
        local alpha = 1.0
        -- shades become transparent in darkness (harder to spot)
        if e.name == "shade" then
            local sr, sg, sb = getLightAtWorld(e.x, e.y)
            alpha = math.max(0.08, math.max(sr, sg, sb))
        end
        local ec = e.color; local hit = e.hitFlash > 0
        -- direction toward player (for arm reaching animation)
        local pdx = player.x - e.x; local pdy = player.y - e.y
        local dd = math.sqrt(pdx*pdx+pdy*pdy); if dd > 0 then pdx,pdy = pdx/dd,pdy/dd end

        -- ═══ COMBINED SIZE: enemy type * camera zoom ═══
        local eMult = e.scale or 1.0
        local sc = (e.radius / 0.35) * z * eMult

        -- ═══ GRID SHEET PATH (spacing test) ═══
        if e.sheet and e.sheet.img and e.sheet.quads then
            local row = math.max(1, math.min((e.animRow or 1), e.sheet.rows or 3))
            local col = math.max(1, math.min((e.animCol or 1), e.sheet.cols or 8))
            local quad = e.sheet.quads[row] and e.sheet.quads[row][col]
            if quad then
                local frameW = e.sheet.frameW or 128
                local frameH = e.sheet.frameH or 128
                local spriteScale = (tileSize * sc * 2.2) / frameW
                -- flip horizontally when facing left (row 2 = side animation)
                local flipX = (e.facingLeft) and -spriteScale or spriteScale
                love.graphics.setColor(1, 1, 1, alpha)
                if hit then love.graphics.setColor(1, 0.7, 0.7, alpha) end
                love.graphics.draw(e.sheet.img, quad, sx, sy, 0, flipX, spriteScale, frameW/2, frameH/2)
            end
            -- no HP bar for test buddy
        else
            -- ═══ SPRITESHEET PATH: if loaded, draw sprite instead of procedural ═══
            local eSprite = enemySprites[e.name]
        if eSprite then
            -- pick frame based on movement direction toward target/player
            local moveAngle = math.atan2(pdy, pdx)
            if e.state == "wander" then
                local tdx = e.targetX - e.x; local tdy = e.targetY - e.y
                local td = math.sqrt(tdx*tdx + tdy*tdy)
                if td > 0.1 then moveAngle = math.atan2(tdy, tdx) end
            end
            local normalizedAngle = (moveAngle + ENEMY_SPRITE_ANGLE_OFFSET) % (2 * math.pi)
            if normalizedAngle < 0 then normalizedAngle = normalizedAngle + 2 * math.pi end
            local frameIdx = math.floor(normalizedAngle / (2 * math.pi) * eSprite.frames + 0.5) % eSprite.frames + 1
            local quad = eSprite.quads[frameIdx]
            if quad then
                local spriteScale = (tileSize * sc * 2.2) / eSprite.size
                -- shade transparency
                love.graphics.setColor(1, 1, 1, alpha)
                -- hit flash: tint white
                if hit then love.graphics.setColor(1, 0.7, 0.7, alpha) end
                love.graphics.draw(eSprite.img, quad,
                    sx, sy, 0,
                    spriteScale, spriteScale,
                    eSprite.size / 2, eSprite.size / 2)
            end
            -- hp bar (when damaged) - still draw over sprite
            if e.hp < e.maxHp then
                love.graphics.setColor(0,0,0,0.8); love.graphics.rectangle("fill",sx-12*sc,sy-23*sc,24*sc,3)
                local hpp = e.hp/e.maxHp; love.graphics.setColor(1-hpp,hpp,0); love.graphics.rectangle("fill",sx-12*sc,sy-23*sc,24*sc*hpp,3)
            end
        else
        -- ═══ PROCEDURAL PATH (original Slenderman drawing) ═══

        -- walk cycle
        local walk = math.sin(gameTime * e.speed * 2.5 + e.x * 3) * 3 * sc
        local breathe = math.sin(gameTime * 1.5 + e.y) * 0.5

        -- shadow on ground
        love.graphics.setColor(0,0,0,0.35*alpha)
        love.graphics.ellipse("fill", sx+2, sy+14*sc, 8*sc, 4*sc)

        -- determine facing direction for arms
        local ax, ay = pdx, pdy
        if e.state == "wander" then
            local tdx = e.targetX - e.x; local tdy = e.targetY - e.y
            local td = math.sqrt(tdx*tdx+tdy*tdy)
            if td > 0.1 then ax, ay = tdx/td, tdy/td else ax, ay = 0, 1 end
        end

        -- LEGS (elongated, thin, spidery)
        local legColor = hit and {1,1,1} or {ec[1]*0.15, ec[2]*0.15, ec[3]*0.15}
        love.graphics.setColor(legColor[1], legColor[2], legColor[3], alpha)
        love.graphics.setLineWidth(2)
        -- left leg
        local lkx = sx - 3*sc + walk*0.5
        local lky = sy + 6*sc
        local lfx = sx - 4*sc + walk
        local lfy = sy + 14*sc
        love.graphics.line(sx - 2*sc, sy + 2*sc, lkx, lky)
        love.graphics.line(lkx, lky, lfx, lfy)
        -- right leg
        local rkx = sx + 3*sc - walk*0.5
        local rky = sy + 6*sc
        local rfx = sx + 4*sc - walk
        local rfy = sy + 14*sc
        love.graphics.line(sx + 2*sc, sy + 2*sc, rkx, rky)
        love.graphics.line(rkx, rky, rfx, rfy)

        -- TORSO (tall, thin, suit-like)
        local bodyDark = hit and {1,0.9,0.9} or {ec[1]*0.2, ec[2]*0.2, ec[3]*0.2}
        local bodyMid = hit and {1,1,1} or {ec[1]*0.35, ec[2]*0.35, ec[3]*0.35}
        love.graphics.setColor(bodyDark[1], bodyDark[2], bodyDark[3], alpha)
        love.graphics.rectangle("fill", sx-4*sc, sy-12*sc+breathe, 8*sc, 16*sc, 1, 1)
        -- suit lapel / center line
        love.graphics.setColor(bodyMid[1], bodyMid[2], bodyMid[3], alpha*0.5)
        love.graphics.line(sx, sy-12*sc+breathe, sx, sy+3*sc)
        -- tie (color-coded to enemy type, the identifier)
        love.graphics.setColor(ec[1], ec[2], ec[3], alpha)
        love.graphics.polygon("fill", sx, sy-10*sc+breathe, sx-1.5*sc, sy-7*sc+breathe, sx, sy-3*sc+breathe, sx+1.5*sc, sy-7*sc+breathe)

        -- ARMS (unnaturally long, slender, reaching)
        love.graphics.setColor(legColor[1], legColor[2], legColor[3], alpha)
        local armSway = math.sin(gameTime*2+e.y*2)*2*sc
        -- left arm: long, drooping, with claw-like fingers
        local lsx = sx - 4*sc
        local lsy = sy - 9*sc + breathe
        local lex = sx - 7*sc + ax*8*sc + armSway
        local ley = sy + 2*sc + ay*8*sc + math.abs(armSway)*0.5
        love.graphics.line(lsx, lsy, lex, ley)
        -- fingers (3 long thin lines)
        love.graphics.setLineWidth(1)
        for f = -1, 1 do
            love.graphics.line(lex, ley, lex+f*2*sc-ax*3*sc, ley+3*sc-ay*3*sc)
        end
        -- right arm
        love.graphics.setLineWidth(2)
        local rsx = sx + 4*sc
        local rsy = sy - 9*sc + breathe
        local rex = sx + 7*sc + ax*8*sc - armSway
        local rey = sy + 2*sc + ay*8*sc + math.abs(armSway)*0.5
        love.graphics.line(rsx, rsy, rex, rey)
        love.graphics.setLineWidth(1)
        for f = -1, 1 do
            love.graphics.line(rex, rey, rex+f*2*sc-ax*3*sc, rey+3*sc-ay*3*sc)
        end

        -- HEAD (featureless white oval, Slenderman style)
        love.graphics.setColor(0.85, 0.82, 0.78, alpha)
        love.graphics.ellipse("fill", sx, sy-15*sc+breathe, 4.5*sc, 5.5*sc)
        -- face shadow (slightly darker oval)
        love.graphics.setColor(0.7, 0.67, 0.63, alpha*0.5)
        love.graphics.ellipse("fill", sx, sy-14*sc+breathe, 3*sc, 4*sc)

        -- state-based eye effects
        if e.state == "hunt" then
            -- red glowing eyes when hunting
            love.graphics.setColor(1, 0.05, 0.0, alpha*0.9)
            love.graphics.circle("fill", sx-1.8*sc, sy-15.5*sc+breathe, 1.2*sc)
            love.graphics.circle("fill", sx+1.8*sc, sy-15.5*sc+breathe, 1.2*sc)
            -- glow
            love.graphics.setColor(1, 0.1, 0.0, alpha*0.3)
            love.graphics.circle("fill", sx-1.8*sc, sy-15.5*sc+breathe, 2.5*sc)
            love.graphics.circle("fill", sx+1.8*sc, sy-15.5*sc+breathe, 2.5*sc)
            -- mouth slit
            love.graphics.setColor(0.15, 0, 0, alpha*0.8)
            love.graphics.line(sx-2*sc, sy-12.5*sc+breathe, sx+2*sc, sy-12.5*sc+breathe)
        elseif e.state == "search" then
            -- dim yellow eyes when searching
            love.graphics.setColor(1, 0.8, 0.1, alpha*0.6)
            love.graphics.circle("fill", sx-1.5*sc, sy-15.5*sc+breathe, 0.8*sc)
            love.graphics.circle("fill", sx+1.5*sc, sy-15.5*sc+breathe, 0.8*sc)
        end

        -- color-coded aura glow around feet for easy ID at a glance
        love.graphics.setColor(ec[1], ec[2], ec[3], alpha*0.15)
        love.graphics.circle("fill", sx, sy, 10*sc)

        love.graphics.setLineWidth(1)

        -- hp bar (when damaged)
        if e.hp < e.maxHp then
            love.graphics.setColor(0,0,0,0.8); love.graphics.rectangle("fill",sx-12*sc,sy-23*sc,24*sc,3)
            local hpp = e.hp/e.maxHp; love.graphics.setColor(1-hpp,hpp,0); love.graphics.rectangle("fill",sx-12*sc,sy-23*sc,24*sc*hpp,3)
        end
        end -- close sprite/procedural if-else
        end -- close sheet/sprite/procedural
    end
end

-- ═══ SEC 17: BULLET DRAWING — projectile trail + dot + highlight ═══
function drawBullets()
    local z = charScale * bulletScale
    for _, b in ipairs(weapons.bullets) do
        local sx = b.x * tileSize
        local sy = b.y * tileSize
        -- bullet travel direction
        local bAngle = math.atan2(b.dy, b.dx)
        local bfx = math.cos(bAngle)
        local bfy = math.sin(bAngle)
        local bpx = -bfy
        local bpy = bfx

        -- smoke trail (fading puffs behind bullet)
        love.graphics.setColor(0.6, 0.55, 0.45, 0.15)
        for i = 1, 3 do
            local tx = sx - bfx * (i * 4) * z
            local ty = sy - bfy * (i * 4) * z
            love.graphics.circle("fill", tx, ty, (1.5 - i * 0.3) * z)
        end

        -- bullet casing body (elongated, brass colored)
        love.graphics.setColor(0.75, 0.6, 0.25)
        local len = 3.5 * z  -- bullet length
        local wid = 1.2 * z  -- bullet width
        -- draw as rotated rectangle (4 corners)
        local c1x = sx - bfx*len + bpx*wid
        local c1y = sy - bfy*len + bpy*wid
        local c2x = sx - bfx*len - bpx*wid
        local c2y = sy - bfy*len - bpy*wid
        local c3x = sx + bfx*len*0.3 - bpx*wid
        local c3y = sy + bfy*len*0.3 - bpy*wid
        local c4x = sx + bfx*len*0.3 + bpx*wid
        local c4y = sy + bfy*len*0.3 + bpy*wid
        love.graphics.polygon("fill", c1x, c1y, c2x, c2y, c3x, c3y, c4x, c4y)

        -- bullet tip (pointed, copper/lead)
        love.graphics.setColor(0.85, 0.5, 0.2)
        local t1x = sx + bfx*len*0.3 + bpx*wid*0.9
        local t1y = sy + bfy*len*0.3 + bpy*wid*0.9
        local t2x = sx + bfx*len*0.3 - bpx*wid*0.9
        local t2y = sy + bfy*len*0.3 - bpy*wid*0.9
        local t3x = sx + bfx*len*1.2
        local t3y = sy + bfy*len*1.2
        love.graphics.polygon("fill", t1x, t1y, t2x, t2y, t3x, t3y)

        -- highlight streak (metallic reflection along top)
        love.graphics.setColor(1, 0.95, 0.7, 0.5)
        love.graphics.setLineWidth(0.6*z)
        local h1x = sx - bfx*len*0.8 + bpx*wid*0.5
        local h1y = sy - bfy*len*0.8 + bpy*wid*0.5
        local h2x = sx + bfx*len*0.8 + bpx*wid*0.3
        local h2y = sy + bfy*len*0.8 + bpy*wid*0.3
        love.graphics.line(h1x, h1y, h2x, h2y)
        love.graphics.setLineWidth(1)
    end
end

-- ╔══════════════════════════════════════════════════════════════╗
-- ║ SEC 18: PLAYER DRAWING — human in yellow biohazard suit     ║
-- ║                                                             ║
-- ║ Top-down view of a hazmat-suited figure with:               ║
-- ║   - Yellow Tyvek-style coverall                             ║
-- ║   - Gray SCBA backpack respirator with air cylinder         ║
-- ║   - Full-face gas mask with dual filter canisters           ║
-- ║   - Tinted green visor                                      ║
-- ║   - Headlamp mounted on forehead                            ║
-- ║   - Black rubber boots and gloves                           ║
-- ║   - Utility belt                                            ║
-- ║                                                             ║
-- ║ DRAW ORDER (back to front):                                 ║
-- ║   Shadow > Boots > Legs > Backpack/SCBA > Body/Torso >      ║
-- ║   Belt > Shoulder harness > Arms/Gloves > Head/Hood >        ║
-- ║   Gas mask > Filter canisters > Visor > Headlamp >          ║
-- ║   Light cone > Weapon > Muzzle flash                        ║
-- ║                                                             ║
-- ║ All sizes multiplied by z (charScale * playerScale).        ║
-- ║ Change charScale at top of file, or playerScale for just    ║
-- ║ the player.                                                 ║
-- ╚══════════════════════════════════════════════════════════════╝
-- ╔══════════════════════════════════════════════════════════════╗
-- ║ SEC 17B: WEAPON DRAWING — detailed in-hand weapon sprites   ║
-- ║                                                             ║
-- ║ Each weapon drawn relative to grip position, facing forward ║
-- ║ along the player's aim direction (fx,fy).                   ║
-- ║                                                             ║
-- ║ MELEE: machete, knife, pipe, axe                            ║
-- ║ RANGED: pistol, shotgun, smg, suppressed pistol             ║
-- ║                                                             ║
-- ║ wx,wy = hand position, fx,fy = forward, px,py = sideways   ║
-- ╚══════════════════════════════════════════════════════════════╝
function drawWeaponInHand(weaponIdx, wx, wy, fx, fy, px, py, z, a)
    -- ═══ SPRITE PATH: if weapon sprite loaded, draw rotated image ═══
    local wSprite = weaponSprites[weaponIdx]
    if wSprite then
        local sw = wSprite:getWidth()
        local sh = wSprite:getHeight()
        -- scale sprite to match weapon size (roughly 18*z pixels long)
        local targetLen = 18 * z
        local spriteScale = targetLen / sw
        -- draw centered on grip, rotated to aim angle
        local gx = wx - fx*3*z
        local gy = wy - fy*3*z
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(wSprite, gx, gy, a, spriteScale, spriteScale, sw*0.25, sh/2)
        return
    end

    -- ═══ PROCEDURAL PATH: draw weapon with geometry ═══
    -- grip point (where hand holds weapon)
    local gx = wx - fx*3*z
    local gy = wy - fy*3*z
    -- helper: convert local coords (fwd, side) to world
    local function wp(fwd, side)
        return gx + fx*fwd*z + px*side*z, gy + fy*fwd*z + py*side*z
    end

    if weaponIdx == 1 then
        -- ══════ MACHETE — long curved blade, dark handle ══════
        -- handle (dark brown, behind grip)
        love.graphics.setColor(0.25, 0.15, 0.08)
        love.graphics.setLineWidth(2.8*z)
        local h1x, h1y = wp(-3, 0)
        local h2x, h2y = wp(1, 0)
        love.graphics.line(h1x, h1y, h2x, h2y)
        -- pommel
        love.graphics.setColor(0.35, 0.35, 0.30)
        love.graphics.circle("fill", h1x, h1y, 1.5*z)
        -- guard (small crosspiece)
        love.graphics.setColor(0.5, 0.5, 0.45)
        love.graphics.setLineWidth(1.5*z)
        local g1x, g1y = wp(1, -2)
        local g2x, g2y = wp(1, 2)
        love.graphics.line(g1x, g1y, g2x, g2y)
        -- blade (long, slightly wide, tapers)
        love.graphics.setColor(0.75, 0.78, 0.82)
        love.graphics.setLineWidth(2.2*z)
        local b1x, b1y = wp(1, 0)
        local b2x, b2y = wp(10, -0.3)
        love.graphics.line(b1x, b1y, b2x, b2y)
        -- blade edge highlight (sharp side)
        love.graphics.setColor(0.9, 0.92, 0.95, 0.7)
        love.graphics.setLineWidth(0.8*z)
        local e1x, e1y = wp(2, -1)
        local e2x, e2y = wp(10, -0.8)
        love.graphics.line(e1x, e1y, e2x, e2y)
        -- tip
        love.graphics.setColor(0.85, 0.87, 0.9)
        local tx, ty = wp(11, -0.5)
        love.graphics.circle("fill", tx, ty, 0.8*z)

    elseif weaponIdx == 2 then
        -- ══════ KNIFE — short pointed blade, wrapped handle ══════
        -- handle (dark, wrapped texture)
        love.graphics.setColor(0.2, 0.2, 0.18)
        love.graphics.setLineWidth(2.5*z)
        local h1x, h1y = wp(-2, 0)
        local h2x, h2y = wp(1, 0)
        love.graphics.line(h1x, h1y, h2x, h2y)
        -- wrap marks
        love.graphics.setColor(0.3, 0.28, 0.22, 0.5)
        love.graphics.setLineWidth(0.5*z)
        for i = -1, 0 do
            local wx1, wy1 = wp(i, -1.2)
            local wx2, wy2 = wp(i+0.5, 1.2)
            love.graphics.line(wx1, wy1, wx2, wy2)
        end
        -- crossguard
        love.graphics.setColor(0.5, 0.5, 0.48)
        love.graphics.setLineWidth(1.5*z)
        local g1x, g1y = wp(1, -1.8)
        local g2x, g2y = wp(1, 1.8)
        love.graphics.line(g1x, g1y, g2x, g2y)
        -- blade (short, pointed)
        love.graphics.setColor(0.7, 0.72, 0.78)
        local t1x, t1y = wp(1, -1)
        local t2x, t2y = wp(1, 1)
        local t3x, t3y = wp(7, 0)
        love.graphics.polygon("fill", t1x, t1y, t2x, t2y, t3x, t3y)
        -- edge highlight
        love.graphics.setColor(0.88, 0.9, 0.95, 0.6)
        love.graphics.setLineWidth(0.5*z)
        love.graphics.line(t1x, t1y, t3x, t3y)

    elseif weaponIdx == 3 then
        -- ══════ PIPE — steel pipe, threaded ends ══════
        -- pipe body
        love.graphics.setColor(0.45, 0.45, 0.48)
        love.graphics.setLineWidth(3*z)
        local p1x, p1y = wp(-4, 0)
        local p2x, p2y = wp(9, 0)
        love.graphics.line(p1x, p1y, p2x, p2y)
        -- center highlight (round metal reflection)
        love.graphics.setColor(0.6, 0.6, 0.65, 0.4)
        love.graphics.setLineWidth(1*z)
        love.graphics.line(p1x, p1y, p2x, p2y)
        -- threaded ends (darker rings)
        love.graphics.setColor(0.3, 0.3, 0.32)
        love.graphics.setLineWidth(3.5*z)
        local te1x, te1y = wp(-4, 0)
        local te2x, te2y = wp(-3, 0)
        love.graphics.line(te1x, te1y, te2x, te2y)
        local te3x, te3y = wp(8, 0)
        local te4x, te4y = wp(9, 0)
        love.graphics.line(te3x, te3y, te4x, te4y)
        -- rust spots
        love.graphics.setColor(0.5, 0.35, 0.2, 0.3)
        local rx, ry = wp(3, 0.5)
        love.graphics.circle("fill", rx, ry, 1*z)

    elseif weaponIdx == 4 then
        -- ══════ AXE — wooden handle, steel head ══════
        -- handle (brown wood)
        love.graphics.setColor(0.4, 0.25, 0.12)
        love.graphics.setLineWidth(2.2*z)
        local h1x, h1y = wp(-4, 0)
        local h2x, h2y = wp(6, 0)
        love.graphics.line(h1x, h1y, h2x, h2y)
        -- handle end cap
        love.graphics.setColor(0.3, 0.18, 0.08)
        love.graphics.circle("fill", h1x, h1y, 1.2*z)
        -- axe head (steel wedge, perpendicular to handle)
        love.graphics.setColor(0.55, 0.55, 0.58)
        local a1x, a1y = wp(5, -3.5)
        local a2x, a2y = wp(5, 3.5)
        local a3x, a3y = wp(8, 2)
        local a4x, a4y = wp(8, -2)
        love.graphics.polygon("fill", a1x, a1y, a2x, a2y, a3x, a3y, a4x, a4y)
        -- blade edge (sharp side, lighter)
        love.graphics.setColor(0.8, 0.82, 0.85)
        love.graphics.setLineWidth(1*z)
        love.graphics.line(a3x, a3y, a4x, a4y)
        -- head outline
        love.graphics.setColor(0.35, 0.35, 0.38)
        love.graphics.setLineWidth(0.8*z)
        love.graphics.polygon("line", a1x, a1y, a2x, a2y, a3x, a3y, a4x, a4y)

    elseif weaponIdx == 5 then
        -- ══════ PISTOL — semi-auto, barrel forward ══════
        -- slide/body (dark gray)
        love.graphics.setColor(0.3, 0.3, 0.32)
        local s1x, s1y = wp(-1, -1.2)
        local s2x, s2y = wp(-1, 1.2)
        local s3x, s3y = wp(7, 1)
        local s4x, s4y = wp(7, -1)
        love.graphics.polygon("fill", s1x, s1y, s2x, s2y, s3x, s3y, s4x, s4y)
        -- barrel (extends forward, slightly narrower)
        love.graphics.setColor(0.25, 0.25, 0.27)
        love.graphics.setLineWidth(1.8*z)
        local b1x, b1y = wp(7, 0)
        local b2x, b2y = wp(9, 0)
        love.graphics.line(b1x, b1y, b2x, b2y)
        -- muzzle hole
        love.graphics.setColor(0.1, 0.1, 0.1)
        local mx, my = wp(9.2, 0)
        love.graphics.circle("fill", mx, my, 0.7*z)
        -- grip (hangs perpendicular to barrel)
        love.graphics.setColor(0.22, 0.22, 0.2)
        local g1x, g1y = wp(0, 1.2)
        local g2x, g2y = wp(0, 4.5)
        local g3x, g3y = wp(2.5, 4)
        local g4x, g4y = wp(2, 1.2)
        love.graphics.polygon("fill", g1x, g1y, g2x, g2y, g3x, g3y, g4x, g4y)
        -- trigger guard
        love.graphics.setColor(0.35, 0.35, 0.37)
        love.graphics.setLineWidth(0.7*z)
        local tg1x, tg1y = wp(2.5, 1.2)
        local tg2x, tg2y = wp(3, 2.5)
        local tg3x, tg3y = wp(1, 2.5)
        love.graphics.line(tg1x, tg1y, tg2x, tg2y)
        love.graphics.line(tg2x, tg2y, tg3x, tg3y)
        -- front sight
        love.graphics.setColor(0.9, 0.9, 0.85)
        local fsx, fsy = wp(8.5, -1.2)
        love.graphics.circle("fill", fsx, fsy, 0.5*z)
        -- slide serrations (detail lines)
        love.graphics.setColor(0.4, 0.4, 0.42, 0.4)
        love.graphics.setLineWidth(0.5*z)
        for i = 4, 6 do
            local sl1x, sl1y = wp(i, -1.1)
            local sl2x, sl2y = wp(i, 1.1)
            love.graphics.line(sl1x, sl1y, sl2x, sl2y)
        end

    elseif weaponIdx == 6 then
        -- ══════ SHOTGUN — long barrel, pump, stock ══════
        -- stock (extends backward)
        love.graphics.setColor(0.4, 0.25, 0.12)
        love.graphics.setLineWidth(2.5*z)
        local st1x, st1y = wp(-2, 0.5)
        local st2x, st2y = wp(-7, 1.5)
        love.graphics.line(st1x, st1y, st2x, st2y)
        -- stock butt
        love.graphics.setColor(0.35, 0.2, 0.1)
        love.graphics.setLineWidth(3*z)
        local sb1x, sb1y = wp(-7, 1)
        local sb2x, sb2y = wp(-7.5, 2)
        love.graphics.line(sb1x, sb1y, sb2x, sb2y)
        -- receiver (body)
        love.graphics.setColor(0.3, 0.3, 0.32)
        local r1x, r1y = wp(-2, -1.3)
        local r2x, r2y = wp(-2, 1.3)
        local r3x, r3y = wp(3, 1)
        local r4x, r4y = wp(3, -1)
        love.graphics.polygon("fill", r1x, r1y, r2x, r2y, r3x, r3y, r4x, r4y)
        -- barrel (long, forward)
        love.graphics.setColor(0.25, 0.25, 0.27)
        love.graphics.setLineWidth(2*z)
        local bb1x, bb1y = wp(3, 0)
        local bb2x, bb2y = wp(12, 0)
        love.graphics.line(bb1x, bb1y, bb2x, bb2y)
        -- magazine tube (underneath barrel)
        love.graphics.setColor(0.3, 0.3, 0.33)
        love.graphics.setLineWidth(1.3*z)
        local mt1x, mt1y = wp(3, 1)
        local mt2x, mt2y = wp(10, 1)
        love.graphics.line(mt1x, mt1y, mt2x, mt2y)
        -- pump/foregrip (darker)
        love.graphics.setColor(0.35, 0.22, 0.1)
        love.graphics.setLineWidth(2.5*z)
        local fg1x, fg1y = wp(6, 0.5)
        local fg2x, fg2y = wp(8, 0.5)
        love.graphics.line(fg1x, fg1y, fg2x, fg2y)
        -- muzzle
        love.graphics.setColor(0.1, 0.1, 0.1)
        local mmx, mmy = wp(12.2, 0)
        love.graphics.circle("fill", mmx, mmy, 0.9*z)
        -- front bead sight
        love.graphics.setColor(1, 0.3, 0.1)
        local bsx, bsy = wp(11.5, -1.2)
        love.graphics.circle("fill", bsx, bsy, 0.5*z)

    elseif weaponIdx == 7 then
        -- ══════ SMG — compact body, magazine, short barrel ══════
        -- body/receiver
        love.graphics.setColor(0.32, 0.32, 0.36)
        local b1x, b1y = wp(-2, -1.5)
        local b2x, b2y = wp(-2, 1.5)
        local b3x, b3y = wp(5, 1.2)
        local b4x, b4y = wp(5, -1.2)
        love.graphics.polygon("fill", b1x, b1y, b2x, b2y, b3x, b3y, b4x, b4y)
        -- barrel (short, extends forward)
        love.graphics.setColor(0.25, 0.25, 0.28)
        love.graphics.setLineWidth(1.5*z)
        local bb1x, bb1y = wp(5, 0)
        local bb2x, bb2y = wp(9, 0)
        love.graphics.line(bb1x, bb1y, bb2x, bb2y)
        -- barrel shroud (perforated)
        love.graphics.setColor(0.35, 0.35, 0.38)
        love.graphics.setLineWidth(2.2*z)
        local bs1x, bs1y = wp(5, 0)
        local bs2x, bs2y = wp(8, 0)
        love.graphics.line(bs1x, bs1y, bs2x, bs2y)
        -- shroud holes
        love.graphics.setColor(0.2, 0.2, 0.22)
        for i = 5, 7 do
            local hx, hy = wp(i+0.5, -1)
            love.graphics.circle("fill", hx, hy, 0.4*z)
        end
        -- magazine (hanging perpendicular)
        love.graphics.setColor(0.28, 0.28, 0.3)
        local m1x, m1y = wp(1, 1.5)
        local m2x, m2y = wp(1, 5)
        local m3x, m3y = wp(3, 5)
        local m4x, m4y = wp(3, 1.5)
        love.graphics.polygon("fill", m1x, m1y, m2x, m2y, m3x, m3y, m4x, m4y)
        -- charging handle
        love.graphics.setColor(0.4, 0.4, 0.42)
        local ch1x, ch1y = wp(3, -1.5)
        local ch2x, ch2y = wp(4, -2.2)
        love.graphics.setLineWidth(1*z)
        love.graphics.line(ch1x, ch1y, ch2x, ch2y)
        -- muzzle
        love.graphics.setColor(0.1, 0.1, 0.1)
        local mmx, mmy = wp(9.2, 0)
        love.graphics.circle("fill", mmx, mmy, 0.6*z)
        -- grip
        love.graphics.setColor(0.2, 0.2, 0.2)
        local g1x, g1y = wp(-1, 1.5)
        local g2x, g2y = wp(-1.5, 4)
        local g3x, g3y = wp(0.5, 3.5)
        local g4x, g4y = wp(0.5, 1.5)
        love.graphics.polygon("fill", g1x, g1y, g2x, g2y, g3x, g3y, g4x, g4y)

    elseif weaponIdx == 8 then
        -- ══════ SUPPRESSED PISTOL — pistol + long suppressor ══════
        -- pistol body (compact)
        love.graphics.setColor(0.22, 0.22, 0.24)
        local s1x, s1y = wp(-1, -1)
        local s2x, s2y = wp(-1, 1)
        local s3x, s3y = wp(4, 0.8)
        local s4x, s4y = wp(4, -0.8)
        love.graphics.polygon("fill", s1x, s1y, s2x, s2y, s3x, s3y, s4x, s4y)
        -- suppressor (long cylinder extending forward)
        love.graphics.setColor(0.18, 0.18, 0.2)
        love.graphics.setLineWidth(2.5*z)
        local sp1x, sp1y = wp(4, 0)
        local sp2x, sp2y = wp(12, 0)
        love.graphics.line(sp1x, sp1y, sp2x, sp2y)
        -- suppressor body rings (detail)
        love.graphics.setColor(0.25, 0.25, 0.28)
        love.graphics.setLineWidth(2.8*z)
        local sr1x, sr1y = wp(4.5, 0)
        local sr2x, sr2y = wp(5.5, 0)
        love.graphics.line(sr1x, sr1y, sr2x, sr2y)
        local sr3x, sr3y = wp(10.5, 0)
        local sr4x, sr4y = wp(11.5, 0)
        love.graphics.line(sr3x, sr3y, sr4x, sr4y)
        -- suppressor tip
        love.graphics.setColor(0.12, 0.12, 0.14)
        local tx, ty = wp(12.2, 0)
        love.graphics.circle("fill", tx, ty, 1*z)
        -- grip
        love.graphics.setColor(0.2, 0.2, 0.18)
        local g1x, g1y = wp(0, 1)
        local g2x, g2y = wp(-0.5, 4)
        local g3x, g3y = wp(2, 3.5)
        local g4x, g4y = wp(2, 1)
        love.graphics.polygon("fill", g1x, g1y, g2x, g2y, g3x, g3y, g4x, g4y)
        -- trigger guard
        love.graphics.setColor(0.28, 0.28, 0.3)
        love.graphics.setLineWidth(0.6*z)
        local tg1x, tg1y = wp(2.5, 1)
        local tg2x, tg2y = wp(2.5, 2.2)
        local tg3x, tg3y = wp(1, 2.2)
        love.graphics.line(tg1x, tg1y, tg2x, tg2y)
        love.graphics.line(tg2x, tg2y, tg3x, tg3y)
        -- rear sight
        love.graphics.setColor(0.35, 0.35, 0.37)
        local rsx, rsy = wp(0, -1.2)
        love.graphics.rectangle("fill", rsx - 0.5*z, rsy - 0.3*z, 1*z, 0.6*z)
    end

    love.graphics.setLineWidth(1)
end

function drawPlayer()
    local z = charScale * playerScale
    local pal = suitPalettes[suitColorIdx]  -- <<<< SUIT COLOR from character select
    local sx = player.x * tileSize
    local sy = player.y * tileSize
    local a = player.angle
    local fx, fy = player.fx, player.fy
    -- perpendicular direction (for left/right offsets)
    local px, py = -fy, fx

    -- invulnerability blink
    if player.invulnTime > 0 and math.floor(player.invulnTime * 10) % 2 == 0 then return end

    -- ═══ SPRITESHEET PATH: if loaded, draw sprite instead of procedural ═══
    if useSprite and playerSprite then
        -- pick frame based on player angle (0 = right, pi/2 = down, etc.)
        local normalizedAngle = (a + PLAYER_SPRITE_ANGLE_OFFSET) % (2 * math.pi)
        if normalizedAngle < 0 then normalizedAngle = normalizedAngle + 2 * math.pi end
        local frameIdx = math.floor(normalizedAngle / (2 * math.pi) * playerSpriteFrames + 0.5) % playerSpriteFrames + 1
        local quad = playerSpriteQuads[frameIdx]
        if quad then
            -- scale sprite to match tileSize (sprite drawn centered on player)
            local spriteScale = (tileSize * 1.2 * playerScale) / playerSpriteSize  -- <<<< SPRITE DRAW SIZE
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(playerSprite, quad,
                sx, sy,        -- position
                0,             -- no rotation (rotation baked into frames)
                spriteScale, spriteScale,  -- scale
                playerSpriteSize / 2, playerSpriteSize / 2)  -- center origin

            -- still draw weapon + muzzle flash over the sprite
            local wep = weapons:getCurrent()
            -- When melee swinging, rotate weapon through arc
            local wepAngle = a
            if weapons.swinging and wep.type == "melee" then
                local swingProg = weapons.swingTimer / (wep.rate * 0.6)
                local swingArc = math.pi * 0.65
                wepAngle = a - swingArc/2 + (1 - swingProg) * swingArc
            end
            local wfx = math.cos(wepAngle)
            local wfy = math.sin(wepAngle)
            local wpx = -wfy
            local wpy = wfx
            local sideOffset = (wep.type == "melee") and 3 or 0
            local wx = sx + wfx*13*z + px*sideOffset*z
            local wy = sy + wfy*13*z + py*sideOffset*z
            drawWeaponInHand(weapons.current, wx, wy, wfx, wfy, wpx, wpy, z, wepAngle)
            -- muzzle flash at barrel tip
            if weapons.fireTimer > wep.rate * 0.7 and wep.type == "ranged" then
                local barrelTip = ({[5]=9.2, [6]=12.2, [7]=9.2, [8]=12.2})[weapons.current] or 8
                local fmx = (wx - wfx*3*z) + wfx*(barrelTip + 3)*z
                local fmy = (wy - wfy*3*z) + wfy*(barrelTip + 3)*z
                love.graphics.setColor(1, 0.7, 0.2, 0.7)
                local flashSize = 6*z
                if weapons.current == 6 then flashSize = 9*z end
                for i = 0, 5 do
                    local ra = wepAngle + i * math.pi/3 + math.random()*0.3
                    local rLen = flashSize * (0.6 + math.random()*0.4)
                    love.graphics.setLineWidth(1.5*z)
                    love.graphics.line(fmx, fmy, fmx + math.cos(ra)*rLen, fmy + math.sin(ra)*rLen)
                end
                love.graphics.setColor(1, 0.95, 0.7, 0.9)
                love.graphics.circle("fill", fmx, fmy, 3*z)
                love.graphics.setColor(1, 1, 1, 0.6)
                love.graphics.circle("fill", fmx, fmy, 1.5*z)
                love.graphics.setLineWidth(1)
            end
            -- melee swing trail
            if weapons.swinging and wep.type == "melee" then
                local reach = weapons:getMeleeReach() * tileSize
                local prog = 1 - (weapons.swingTimer / (wep.rate * 0.6))
                love.graphics.setColor(0.9, 0.95, 1, 0.35 * (1 - prog))
                love.graphics.setLineWidth(2*z)
                love.graphics.arc("line", sx, sy, reach * 0.7,
                    wepAngle - math.pi*0.3, wepAngle)
                love.graphics.setLineWidth(1)
            end
        end
        return  -- skip procedural drawing
    end

    -- walk cycle animation
    local walkCycle = math.sin(gameTime * 8) * (player.moving and 1 or 0)
    local legSwing = walkCycle * 3 * z     -- leg forward/back distance
    local bodyBob = math.abs(walkCycle) * 0.5 * z  -- subtle up/down

    -- breathing animation
    local breathe = math.sin(gameTime * 2) * 0.3 * z

    -- ══════ SHADOW ══════
    love.graphics.setColor(0, 0, 0, 0.35)
    love.graphics.ellipse("fill", sx + 1*z, sy + 2*z, 11*z, 7*z)

    -- ══════ BOOTS (black rubber, thick) ══════
    love.graphics.setColor(0.12, 0.12, 0.10)
    -- left boot
    local lbx = sx + px*4*z - fx*legSwing
    local lby = sy + py*4*z - fy*legSwing
    love.graphics.ellipse("fill", lbx, lby, 3.5*z, 2.5*z)
    -- right boot
    local rbx = sx - px*4*z + fx*legSwing
    local rby = sy - py*4*z + fy*legSwing
    love.graphics.ellipse("fill", rbx, rby, 3.5*z, 2.5*z)
    -- boot soles (dark edge)
    love.graphics.setColor(0.06, 0.06, 0.05)
    love.graphics.setLineWidth(1.5*z)
    love.graphics.ellipse("line", lbx, lby, 3.5*z, 2.5*z)
    love.graphics.ellipse("line", rbx, rby, 3.5*z, 2.5*z)
    love.graphics.setLineWidth(1)

    -- ══════ LEGS (yellow coverall, visible between boots and body) ══════
    love.graphics.setColor(pal.suit[1]*0.94, pal.suit[2]*0.94, pal.suit[3]*0.80)  -- suit legs
    love.graphics.setLineWidth(4*z)
    love.graphics.line(sx + px*3*z, sy + py*3*z, lbx, lby)  -- left leg
    love.graphics.line(sx - px*3*z, sy - py*3*z, rbx, rby)  -- right leg
    love.graphics.setLineWidth(1)

    -- ══════ BACKPACK / SCBA RESPIRATOR UNIT ══════
    local bpx = sx - fx*10*z
    local bpy = sy - fy*10*z

    -- backpack frame (dark gray)
    love.graphics.setColor(0.25, 0.25, 0.27)
    love.graphics.rectangle("fill", bpx - 6*z, bpy - 5*z, 12*z, 10*z, 2*z, 2*z)

    -- SCBA air cylinder (lighter gray, rounded)
    love.graphics.setColor(0.55, 0.55, 0.58)
    love.graphics.ellipse("fill", bpx, bpy, 4.5*z, 6*z)  -- <<<< AIR TANK

    -- cylinder highlight (reflective stripe)
    love.graphics.setColor(0.70, 0.70, 0.73, 0.5)
    love.graphics.ellipse("fill", bpx - 1.5*z, bpy, 1.5*z, 5*z)

    -- valve/regulator on top of cylinder
    love.graphics.setColor(0.35, 0.35, 0.38)
    love.graphics.circle("fill", bpx + fx*5*z, bpy + fy*5*z, 2.5*z)
    love.graphics.setColor(0.8, 0.2, 0.2)  -- red valve handle
    love.graphics.circle("fill", bpx + fx*6*z, bpy + fy*6*z, 1.2*z)

    -- backpack straps (black)
    love.graphics.setColor(0.15, 0.15, 0.13)
    love.graphics.setLineWidth(2.5*z)
    love.graphics.line(bpx + px*4*z, bpy + py*4*z, sx + px*5*z - fx*2*z, sy + py*5*z - fy*2*z)
    love.graphics.line(bpx - px*4*z, bpy - py*4*z, sx - px*5*z - fx*2*z, sy - py*5*z - fy*2*z)
    love.graphics.setLineWidth(1)

    -- ══════ BODY / TORSO (yellow hazmat coverall, oval shape) ══════
    love.graphics.setColor(pal.suit[1], pal.suit[2], pal.suit[3])  -- suit body
    love.graphics.ellipse("fill", sx, sy, 7*z + breathe, 9*z)  -- <<<< TORSO SIZE

    -- coverall trim/seams (darker yellow lines)
    love.graphics.setColor(pal.suitDark[1], pal.suitDark[2], pal.suitDark[3], 0.6)  -- suit seams
    love.graphics.setLineWidth(1*z)
    -- center zipper line
    love.graphics.line(sx + fx*6*z, sy + fy*6*z, sx - fx*7*z, sy - fy*7*z)
    -- side seams
    love.graphics.line(sx + px*6*z, sy + py*6*z, sx + px*5*z - fx*6*z, sy + py*5*z - fy*6*z)
    love.graphics.line(sx - px*6*z, sy - py*6*z, sx - px*5*z - fx*6*z, sy - py*5*z - fy*6*z)
    love.graphics.setLineWidth(1)

    -- ══════ UTILITY BELT (black strip across waist) ══════
    love.graphics.setColor(pal.belt[1], pal.belt[2], pal.belt[3])  -- belt
    love.graphics.setLineWidth(2.5*z)
    love.graphics.line(sx + px*6*z - fx*1*z, sy + py*6*z - fy*1*z,
                       sx - px*6*z - fx*1*z, sy - py*6*z - fy*1*z)
    love.graphics.setLineWidth(1)
    -- belt buckle
    love.graphics.setColor(0.6, 0.6, 0.55)
    love.graphics.rectangle("fill", sx - fx*1*z - 1.5*z, sy - fy*1*z - 1.5*z, 3*z, 3*z, 0.5*z, 0.5*z)

    -- ══════ ARMS (yellow sleeves + black rubber gloves) ══════
    local wep = weapons:getCurrent()
    local weaponArmFx = fx  -- weapon arm aims forward

    -- LEFT ARM (non-weapon, swings with walk)
    local lax = sx + px*7*z + fx*legSwing*0.5  -- swings opposite to legs
    local lay = sy + py*7*z + fy*legSwing*0.5
    -- upper arm (yellow)
    love.graphics.setColor(pal.suit[1]*0.96, pal.suit[2]*0.96, pal.suit[3]*0.93)  -- sleeve
    love.graphics.setLineWidth(3.5*z)
    love.graphics.line(sx + px*6*z, sy + py*6*z, lax, lay)
    -- glove (black)
    love.graphics.setColor(pal.gloves[1], pal.gloves[2], pal.gloves[3])  -- glove
    love.graphics.circle("fill", lax, lay, 2.5*z)
    love.graphics.setLineWidth(1)

    -- RIGHT ARM (weapon arm, extends toward aim direction)
    -- When melee swinging, rotate weapon arm through an arc
    local wepAngle = a  -- effective weapon angle (aim direction)
    local swingProg = 0
    if weapons.swinging and wep.type == "melee" then
        swingProg = weapons.swingTimer / (wep.rate * 0.6)  -- 1.0 → 0.0
        local swingArc = math.pi * 0.65  -- total sweep angle (~120°)
        wepAngle = a - swingArc/2 + (1 - swingProg) * swingArc  -- sweep from left to right
    end
    local wfx = math.cos(wepAngle)  -- weapon forward vector
    local wfy = math.sin(wepAngle)
    local wpx = -wfy  -- weapon perpendicular vector
    local wpy = wfx
    -- ranged weapons: straight along aim line (no side offset, aligns with bullet path)
    -- melee weapons: offset to player's right side for natural grip look
    local sideOffset = (wep.type == "melee") and 3 or 0
    local wx = sx + wfx*13*z + px*sideOffset*z  -- weapon tip position
    local wy = sy + wfy*13*z + py*sideOffset*z
    -- upper arm (yellow)
    love.graphics.setColor(pal.suit[1]*0.96, pal.suit[2]*0.96, pal.suit[3]*0.93)  -- sleeve
    love.graphics.setLineWidth(3.5*z)
    love.graphics.line(sx - px*5*z + fx*2*z, sy - py*5*z + fy*2*z, wx - wfx*4*z, wy - wfy*4*z)
    love.graphics.setLineWidth(1)
    -- glove (black hand holding weapon)
    love.graphics.setColor(pal.gloves[1], pal.gloves[2], pal.gloves[3])
    love.graphics.circle("fill", wx - wfx*3*z, wy - wfy*3*z, 2.5*z)
    -- draw detailed weapon in hand (using weapon-rotated vectors)
    drawWeaponInHand(weapons.current, wx, wy, wfx, wfy, wpx, wpy, z, wepAngle)

    -- ══════ HEAD / HOOD (yellow hazmat hood over gas mask) ══════
    local hx = sx + fx*5*z  -- head center (forward of body)
    local hy = sy + fy*5*z
    -- hood (yellow, slightly lighter than body)
    love.graphics.setColor(pal.hood[1], pal.hood[2], pal.hood[3])  -- hood
    love.graphics.circle("fill", hx, hy, 6.5*z)  -- <<<< HEAD SIZE

    -- hood edge/rim (darker outline)
    love.graphics.setColor(pal.suitDark[1], pal.suitDark[2], pal.suitDark[3], 0.7)  -- hood edge
    love.graphics.setLineWidth(1.2*z)
    love.graphics.circle("line", hx, hy, 6.5*z)
    love.graphics.setLineWidth(1)

    -- ══════ GAS MASK (dark rubber facepiece) ══════
    local mx = hx + fx*2*z  -- mask slightly forward of head center
    local my = hy + fy*2*z
    -- mask body (dark charcoal rubber)
    love.graphics.setColor(0.18, 0.18, 0.16)
    love.graphics.ellipse("fill", mx, my, 4.5*z, 4*z)

    -- ══════ FILTER CANISTERS (two gray cylinders on cheeks) ══════
    local fc1x = mx + px*4.5*z  -- left filter
    local fc1y = my + py*4.5*z
    local fc2x = mx - px*4.5*z  -- right filter
    local fc2y = my - py*4.5*z
    -- canister bodies
    love.graphics.setColor(0.45, 0.45, 0.48)
    love.graphics.circle("fill", fc1x, fc1y, 2.8*z)
    love.graphics.circle("fill", fc2x, fc2y, 2.8*z)
    -- canister intake grilles (dark rings)
    love.graphics.setColor(0.25, 0.25, 0.27)
    love.graphics.setLineWidth(1*z)
    love.graphics.circle("line", fc1x, fc1y, 2.8*z)
    love.graphics.circle("line", fc2x, fc2y, 2.8*z)
    -- inner grille pattern
    love.graphics.setColor(0.30, 0.30, 0.32)
    love.graphics.circle("fill", fc1x, fc1y, 1.5*z)
    love.graphics.circle("fill", fc2x, fc2y, 1.5*z)
    love.graphics.setLineWidth(1)

    -- ══════ RESPIRATOR HOSE (black tube from mask to backpack) ══════
    love.graphics.setColor(0.12, 0.12, 0.10)
    love.graphics.setLineWidth(2*z)
    -- hose curves from mask down-right to backpack
    local hoseMidX = sx - fx*3*z + px*3*z
    local hoseMidY = sy - fy*3*z + py*3*z
    love.graphics.line(mx - px*2*z, my - py*2*z, hoseMidX, hoseMidY)
    love.graphics.line(hoseMidX, hoseMidY, bpx + fx*3*z, bpy + fy*3*z)
    love.graphics.setLineWidth(1)

    -- ══════ VISOR (tinted eye window on gas mask) ══════
    love.graphics.setColor(0.1, 0.45, 0.35, 0.85)  -- dark green tint
    -- wide rectangular visor across mask face
    local v1x = mx + px*3*z + fx*1.5*z
    local v1y = my + py*3*z + fy*1.5*z
    local v2x = mx - px*3*z + fx*1.5*z
    local v2y = my - py*3*z + fy*1.5*z
    love.graphics.setLineWidth(3*z)
    love.graphics.line(v1x, v1y, v2x, v2y)
    -- visor reflection highlight
    love.graphics.setColor(0.3, 0.8, 0.6, 0.3)
    love.graphics.setLineWidth(1.5*z)
    love.graphics.line(v1x + fx*0.5*z, v1y + fy*0.5*z, v2x + fx*0.5*z, v2y + fy*0.5*z)
    love.graphics.setLineWidth(1)

    -- ══════ HEADLAMP (mounted on forehead above visor) ══════
    local hlx = mx + fx*4*z  -- lamp position (front of head)
    local hly = my + fy*4*z
    -- lamp housing (dark gray box)
    love.graphics.setColor(0.30, 0.30, 0.32)
    love.graphics.rectangle("fill", hlx - 2.5*z, hly - 1.5*z, 5*z, 3*z, 1*z, 1*z)
    -- lamp lens (bright when on)
    if headlampOn then
        love.graphics.setColor(1, 0.95, 0.7, 0.9)
    else
        love.graphics.setColor(0.4, 0.38, 0.3, 0.5)
    end
    love.graphics.circle("fill", hlx + fx*2*z, hly + fy*2*z, 2*z)

    -- ══════ LIGHT CONE (visible beam from headlamp) ══════
    if headlampOn then
        love.graphics.setColor(1, 0.95, 0.7, 0.08)
        love.graphics.polygon("fill",
            hlx + fx*2*z, hly + fy*2*z,
            hlx + fx*2*z + math.cos((a + HEADLAMP_ANGLE_OFFSET) - 0.35)*35*z, hly + fy*2*z + math.sin((a + HEADLAMP_ANGLE_OFFSET) - 0.35)*35*z,
            hlx + fx*2*z + math.cos((a + HEADLAMP_ANGLE_OFFSET) + 0.35)*35*z, hly + fy*2*z + math.sin((a + HEADLAMP_ANGLE_OFFSET) + 0.35)*35*z)
    end

    -- ══════ MUZZLE FLASH (at barrel tip when firing ranged weapons) ══════
    if weapons.fireTimer > wep.rate * 0.7 and wep.type == "ranged" then
        -- barrel length varies per weapon (matches drawWeaponInHand forward distances)
        local barrelTip = ({[5]=9.2, [6]=12.2, [7]=9.2, [8]=12.2})[weapons.current] or 8
        local fmx = (wx - wfx*3*z) + wfx*(barrelTip + 3)*z  -- from grip + barrel length
        local fmy = (wy - wfy*3*z) + wfy*(barrelTip + 3)*z
        -- outer flash (orange starburst)
        love.graphics.setColor(1, 0.7, 0.2, 0.7)
        local flashSize = 6*z
        if weapons.current == 6 then flashSize = 9*z end  -- shotgun bigger flash
        for i = 0, 5 do
            local ra = wepAngle + i * math.pi/3 + math.random()*0.3
            local rLen = flashSize * (0.6 + math.random()*0.4)
            love.graphics.setLineWidth(1.5*z)
            love.graphics.line(fmx, fmy, fmx + math.cos(ra)*rLen, fmy + math.sin(ra)*rLen)
        end
        -- core glow
        love.graphics.setColor(1, 0.95, 0.7, 0.9)
        love.graphics.circle("fill", fmx, fmy, 3*z)
        love.graphics.setColor(1, 1, 1, 0.6)
        love.graphics.circle("fill", fmx, fmy, 1.5*z)
        love.graphics.setLineWidth(1)
    end

    -- ══════ MELEE SWING TRAIL (follows weapon tip during swing) ══════
    if weapons.swinging and wep.type == "melee" then
        local reach = weapons:getMeleeReach() * tileSize
        local prog = 1 - (weapons.swingTimer / (wep.rate * 0.6))
        -- swoosh trail (fades out as swing progresses)
        love.graphics.setColor(0.9, 0.95, 1, 0.35 * (1 - prog))
        love.graphics.setLineWidth(2*z)
        local trailArc = math.pi * 0.3
        love.graphics.arc("line", sx, sy, reach * 0.7,
            wepAngle - trailArc, wepAngle)
        love.graphics.setLineWidth(1)
    end
end

-- ═══ SEC 19: HUD — health/stamina/sanity bars, ammo, weapon, noise ═══
function drawHud(w, h)
    local s = 1
    if hudFont then love.graphics.setFont(hudFont) end
    if hudFont then love.graphics.setFont(hudFont) end

    local fontH = love.graphics.getFont():getHeight()
    local pad = math.floor(4 * s)
    local bx, by = math.floor(10 * s), math.floor(10 * s)
    local bw = math.floor(180 * s)
    local bh = math.max(math.floor(14 * s), fontH + math.floor(4 * s))

    -- background panel (auto-sized for the bars + spacing)
    local panelW = bw + math.floor(30 * s)
    local panelH = (bh + pad) * 6 + math.floor(18 * s)
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", bx - pad, by - pad, panelW, panelH, math.floor(4*s), math.floor(4*s))

    local function bar(x, y, pct, r, g, b, label)
        pct = math.max(0, math.min(1, pct or 0))
        love.graphics.setColor(0.2, 0.2, 0.2)
        love.graphics.rectangle("fill", x, y, bw, bh, math.floor(2*s), math.floor(2*s))
        love.graphics.setColor(r, g, b)
        love.graphics.rectangle("fill", x, y, math.floor(bw * pct), bh, math.floor(2*s), math.floor(2*s))

        love.graphics.setColor(1, 1, 1)
        local ty = y + math.floor((bh - fontH) / 2)
        love.graphics.print(label, x + pad, ty)
    end

    local hp=player.hp/player.maxHp
    bar(bx,by,hp,1-hp,hp,0.1,"HP "..math.floor(player.hp)); by = by + bh + pad
    bar(bx,by,player.stamina/player.maxStamina,0.2,0.4,0.9,"ST "..math.floor(player.stamina)); by = by + bh + pad
    bar(bx,by,player.sanity/player.maxSanity,0.6,0.2,0.8,"SANITY "..math.floor(player.sanity)); by = by + bh + pad
    bar(bx,by,player.hydration/player.maxHydration,0.2,0.7,0.9,"H2O "..math.floor(player.hydration)); by = by + bh + pad
    -- battery bar (prominent)
    local batPct = math.max(0, math.min(1, headlampBattery / headlampBatteryMax))
    local batR = batPct > 0.3 and 0.2 or 1; local batG = batPct > 0.3 and 1 or batPct * 3
    bar(bx,by,batPct,batR,batG,0.3,"LAMP "..math.floor(batPct*100).."%  "..(headlampOn and "ON" or "OFF")); by = by + bh + pad
    -- xp bar (make it match other bars better)
    local xpH = bh
    love.graphics.setColor(0.2,0.2,0.2); love.graphics.rectangle("fill", bx, by, bw, xpH, math.floor(2*s), math.floor(2*s))
    love.graphics.setColor(0.9,0.7,0.1); love.graphics.rectangle("fill", bx, by, math.floor(bw*(player.xp/player.xpNeed)), xpH, math.floor(2*s), math.floor(2*s))

    -- level label centered in the xp bar
    love.graphics.setColor(1,1,1)
    local lvlTxt = "LV "..player.level
    local lvlW = love.graphics.getFont():getWidth(lvlTxt)
    local lvlY = by + math.floor((xpH - fontH)/2)
    love.graphics.print(lvlTxt, bx + math.floor((bw - lvlW)/2), lvlY)

    by = by + xpH + pad

    -- quick items line (two columns with breathing room)
    local leftTxt = "[1] H2O: "..player.almondWater
    local rightTxt = "[2/LB] Med: "..player.bandages
    love.graphics.setColor(0.3,0.8,1); love.graphics.print(leftTxt, bx, by)
    love.graphics.setColor(0.3,1,0.3); love.graphics.print(rightTxt, bx + math.floor(bw*0.62), by)
    by = by + fontH + pad

    -- ammo count bottom left
-- ammo count bottom left
    love.graphics.setColor(0,0,0,0.7); love.graphics.rectangle("fill",5,h-55,130,30,4,4)
    love.graphics.setColor(0.9,0.7,0.1); love.graphics.print("AMMO: "..weapons.ammo, 12, h-50)
    love.graphics.setColor(0.2,1,0.6); love.graphics.print("BAT: "..player.batteries, 82, h-50)

    -- right HUD
    love.graphics.setColor(0,0,0,0.7); love.graphics.rectangle("fill",w-155,5,150,92,4,4)
    love.graphics.setColor(0.9,0.8,0.2); love.graphics.print("Day "..wave.."  "..formatTime(gameTime), w-150,10)
    local wep = weapons:getCurrent()
    love.graphics.setColor(wep.color[1],wep.color[2],wep.color[3]); love.graphics.print(wep.name:upper(), w-150,26)
    if wep.type == "ranged" then
        love.graphics.setColor(0.9,0.7,0.1); love.graphics.print("AMMO: "..weapons.ammo, w-150,40)
    else
        love.graphics.setColor(0.6,0.6,0.6); love.graphics.print("MELEE", w-150,40)
    end
    love.graphics.setColor(0.7,0.7,0.7); love.graphics.print("Kills "..kills, w-150,54)
    -- V2: streak display on same line (only shows when streak >= 3)
    if player.currentStreak >= 3 then
        local mult = player:getStreakMultiplier()
        if player.streakDisplayTimer > 0 then
            local flash = math.sin(love.timer.getTime() * 10) * 0.3 + 0.7
            love.graphics.setColor(1, 0.5 * flash, 0.1)
        else
            love.graphics.setColor(1, 0.7, 0.2, 0.9)
        end
        local streakTxt = "x"..player.currentStreak
        if mult > 1.0 then streakTxt = streakTxt..string.format(" %.1fx", mult) end
        love.graphics.print(streakTxt, w-90, 54)
    end
    love.graphics.setColor(0.2,0.2,0.2); love.graphics.rectangle("fill",w-150,70,70,8,2,2)
    local nP = player.noise/100; love.graphics.setColor(nP,1-nP,0.1); love.graphics.rectangle("fill",w-150,70,70*nP,8,2,2)
    love.graphics.setColor(0.7,0.7,0.7); love.graphics.print("NOISE",w-75,68)
    love.graphics.setColor(1,0.5,0.1); love.graphics.print("BOMB x"..bomb.count, w-150,84)
    -- difficulty indicator
    local dc = {[1]={0.3,1,0.3}, [2]={1,0.9,0.3}, [3]={1,0.5,0.2}, [4]={1,0.2,0.2}}
    love.graphics.setColor(dc[difficultyIdx]); love.graphics.print(difficulties[difficultyIdx], w-80,84)
end

-- ═══ SEC 20: STATUS HUD (hold Y) — full inventory + stats display ═══
function drawStatusHud(w, h)
    -- V3: expand panel if player has active perks
    local perkCount = #player.activeRunPerks
    local perkExtra = perkCount > 0 and (20 + perkCount * 14) or 0
    local pw = 320; local ph = 260 + perkExtra
    local px = (w - pw) / 2; local py = (h - ph) / 2

    -- dark background
    love.graphics.setColor(0, 0, 0, 0.88)
    love.graphics.rectangle("fill", px, py, pw, ph, 6, 6)
    love.graphics.setColor(0.9, 0.8, 0.2, 0.6)
    love.graphics.rectangle("line", px, py, pw, ph, 6, 6)

    local bx = px + 15; local by = py + 12; local bw = pw - 30; local bh = 14

    -- title
    love.graphics.setColor(0.9, 0.8, 0.2)
    love.graphics.printf(playerName ~= "" and playerName:upper() or "STATUS", px, by, pw, "center")
    by = by + 22

    local function statusBar(x, y, pct, r, g, b, label, val)
        love.graphics.setColor(0.15, 0.15, 0.15)
        love.graphics.rectangle("fill", x, y, bw, bh, 3, 3)
        love.graphics.setColor(r, g, b, 0.8)
        love.graphics.rectangle("fill", x, y, bw * math.max(0, math.min(1, pct)), bh, 3, 3)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(label, x + 4, y + 1)
        love.graphics.printf(val, x, y + 1, bw - 4, "right")
    end

    local hp = player.hp / player.maxHp
    statusBar(bx, by, hp, 1-hp, hp, 0.1, "HEALTH", math.floor(player.hp).."/"..player.maxHp)
    by = by + bh + 4
    statusBar(bx, by, player.stamina/player.maxStamina, 0.2, 0.4, 0.9, "STAMINA", math.floor(player.stamina).."/"..math.floor(player.maxStamina))
    by = by + bh + 4
    statusBar(bx, by, player.sanity/player.maxSanity, 0.6, 0.2, 0.8, "SANITY", math.floor(player.sanity).."/"..math.floor(player.maxSanity))
    by = by + bh + 4
    statusBar(bx, by, player.hydration/player.maxHydration, 0.2, 0.7, 0.9, "HYDRATION", math.floor(player.hydration).."/"..math.floor(player.maxHydration))
    by = by + bh + 4
    local batPct = headlampBattery / headlampBatteryMax
    local batR = batPct > 0.3 and 0.2 or 1; local batG = batPct > 0.3 and 1 or batPct * 3
    statusBar(bx, by, batPct, batR, batG, 0.3, "HEADLAMP", math.floor(batPct * 100).."%")
    by = by + bh + 8

    -- inventory line
    love.graphics.setColor(0.3, 0.8, 1); love.graphics.print("Water: "..player.almondWater, bx, by)
    love.graphics.setColor(0.3, 1, 0.3); love.graphics.print("Med: "..player.bandages, bx + 80, by)
    love.graphics.setColor(0.2, 1, 0.6); love.graphics.print("Bat: "..player.batteries, bx + 150, by)
    by = by + 18

    -- weapon + ammo
    local wep = weapons:getCurrent()
    love.graphics.setColor(wep.color[1], wep.color[2], wep.color[3])
    love.graphics.print("Weapon: "..wep.name:upper(), bx, by)
    if wep.type == "ranged" then
        love.graphics.setColor(0.9, 0.7, 0.1)
        love.graphics.print("Ammo: "..weapons.ammo, bx + 180, by)
    end
    by = by + 18

    -- bombs + batteries + level
    local maxBombs = math.max(2, 6 - difficultyIdx)
    local maxBat = math.max(0, 4 - difficultyIdx)
    love.graphics.setColor(1, 0.5, 0.1); love.graphics.print("Bombs: "..bomb.count.."/"..maxBombs, bx, by)
    love.graphics.setColor(0.2, 1, 0.6); love.graphics.print("Bat: "..player.batteries.."/"..maxBat, bx + 100, by)
    love.graphics.setColor(0.9, 0.8, 0.2); love.graphics.print("Level: "..player.level, bx + 190, by)
    by = by + 18

    -- day/time/kills
    love.graphics.setColor(0.7, 0.7, 0.7)
    love.graphics.print("Day "..wave.."  |  "..formatTime(gameTime).."  |  Kills: "..kills, bx, by)
    by = by + 16
    -- V2: streak display in status panel
    if player.currentStreak >= 3 or player.bestRunStreak >= 5 then
        love.graphics.setColor(1, 0.7, 0.2)
        love.graphics.print("Streak: "..player.currentStreak.."  (Best: "..player.bestRunStreak..")", bx, by)
        local mult = player:getStreakMultiplier()
        if mult > 1.0 then
            love.graphics.setColor(0.3, 1, 0.3)
            love.graphics.print(string.format("  XP: %.1fx", mult), bx + 190, by)
        end
        by = by + 16
    end

    -- V3: active run perks
    if #player.activeRunPerks > 0 then
        by = by + 4
        love.graphics.setColor(0.3, 0.9, 0.5, 0.8)
        love.graphics.print("PERKS:", bx, by)
        by = by + 14
        for _, p in ipairs(player.activeRunPerks) do
            love.graphics.setColor(0.5, 0.8, 0.4)
            love.graphics.print("  "..p.name, bx, by)
            by = by + 14
        end
    end
end

-- ═══ V5: RUN STATS POPUP — hold D-Pad Up / F2 for full run overview ═══
-- Centered popup showing comprehensive run stats (bigger than status HUD)
function drawRunStats(w, h)
    local s = uiScale
    local panelW = math.floor(380 * s)
    local panelH = math.floor(340 * s)
    local px = math.floor((w - panelW) / 2)
    local py = math.floor((h - panelH) / 2)

    -- dark panel with border
    love.graphics.setColor(0, 0, 0, 0.92)
    love.graphics.rectangle("fill", px, py, panelW, panelH, 8, 8)
    love.graphics.setColor(0.9, 0.8, 0.2, 0.6)
    love.graphics.rectangle("line", px, py, panelW, panelH, 8, 8)

    local lineH = math.floor(18 * s)
    local col1 = px + math.floor(20 * s)
    local col2 = px + math.floor(210 * s)
    local cy = py + math.floor(12 * s)

    -- title
    if menuFont then love.graphics.setFont(menuFont) end
    love.graphics.setColor(0.9, 0.8, 0.2)
    love.graphics.printf("RUN STATS", px, cy, panelW, "center")
    cy = cy + math.floor(30 * s)

    if defaultFont then love.graphics.setFont(defaultFont) end

    -- helper to draw a stat line
    local function statLine(label, value, labelColor, valueColor)
        love.graphics.setColor(labelColor or {0.6, 0.6, 0.6})
        love.graphics.print(label, col1, cy)
        love.graphics.setColor(valueColor or {1, 1, 1})
        love.graphics.print(tostring(value), col2, cy)
        cy = cy + lineH
    end

    -- player info
    statLine("Subject", playerName, {0.5, 0.5, 0.5}, {0.9, 0.8, 0.2})
    statLine("Difficulty", difficulties[difficultyIdx] or "?", {0.5, 0.5, 0.5}, ({[1]={0.3,1,0.3},[2]={1,0.9,0.3},[3]={1,0.5,0.2},[4]={1,0.2,0.2}})[difficultyIdx])
    cy = cy + math.floor(4 * s)

    -- survival stats
    statLine("Day", tostring(wave), nil, {1, 0.9, 0.3})
    statLine("Time", string.format("%d:%02d", math.floor(gameTime/60), math.floor(gameTime%60)))
    statLine("Level", tostring(player.level), nil, {0.9, 0.8, 0.2})
    local xpPct = player.xpNeed > 0 and math.floor(player.xp / player.xpNeed * 100) or 0
    statLine("XP", player.xp.."/"..player.xpNeed.." ("..xpPct.."%)", nil, {0.6, 0.8, 1})
    cy = cy + math.floor(4 * s)

    -- combat stats
    statLine("Kills", tostring(kills), nil, {1, 0.4, 0.3})
    local mult = player:getStreakMultiplier()
    local streakStr = tostring(player.currentStreak)
    if mult > 1.0 then streakStr = streakStr..string.format(" (%.1fx XP)", mult) end
    statLine("Streak", streakStr, nil, {1, 0.7, 0.2})
    statLine("Best Streak", tostring(player.bestRunStreak), nil, {1, 0.5, 0.1})
    cy = cy + math.floor(4 * s)

    -- resource status
    statLine("HP", player.hp.."/"..player.maxHp, nil, player.hp < player.maxHp * 0.3 and {1, 0.3, 0.3} or {0.3, 1, 0.3})
    statLine("Stamina", math.floor(player.stamina).."/"..math.floor(player.maxStamina))
    statLine("Sanity", math.floor(player.sanity).."/"..math.floor(player.maxSanity), nil, player.sanity < 40 and {0.8, 0.3, 1} or nil)
    statLine("Ammo", tostring(weapons.ammo), nil, {0.9, 0.7, 0.1})
    statLine("Bandages", tostring(player.bandages), nil, {0.3, 1, 0.3})
    statLine("Almond Water", tostring(player.almondWater), nil, {0.3, 0.8, 1})

    -- active perks
    if #player.activeRunPerks > 0 then
        cy = cy + math.floor(6 * s)
        love.graphics.setColor(0.3, 0.9, 0.5, 0.8)
        love.graphics.print("PERKS:", col1, cy)
        cy = cy + lineH
        for _, p in ipairs(player.activeRunPerks) do
            love.graphics.setColor(0.5, 0.8, 0.4)
            love.graphics.print("  "..p.name, col1, cy)
            cy = cy + math.floor(14 * s)
        end
    end

    -- portal status
    if FS.portalSpawned then
        cy = cy + math.floor(4 * s)
        local portal = map:getPortal()
        if portal and portal.active then
            local guardsLeft = enemies:countPortalGuards()
            if guardsLeft > 0 then
                statLine("Portal", guardsLeft.." guards remain", nil, {1, 0.4, 0.2})
            else
                statLine("Portal", "CLEAR - approach to escape", nil, {0.2, 1, 0.5})
            end
        else
            love.graphics.setColor(0.5, 0.5, 0.5)
            love.graphics.print("Portal: DECLINED (Living Legend)", col1, cy)
        end
    end

    -- hint at bottom
    local hintKey = input:getActiveMode() == "gamepad" and "Release D-Up" or "Release F2"
    love.graphics.setColor(0.4, 0.4, 0.4)
    love.graphics.printf(hintKey.." to close", px, py + panelH - math.floor(18 * s), panelW, "center")
end

-- ═══ CONTROLS HUD — hold D-Pad Down / F1 to show current control scheme ═══
function drawControlsHud(w, h)
    local mode = input:getActiveMode()
    local scheme = Input.schemes[mode]
    if not scheme then return end

    local controls = scheme.controls
    local rowH = 22
    local pw = 340; local ph = rowH * #controls + 60
    local px = (w - pw) / 2; local py = (h - ph) / 2

    -- dark background
    love.graphics.setColor(0, 0, 0, 0.92)
    love.graphics.rectangle("fill", px, py, pw, ph, 6, 6)
    love.graphics.setColor(0.9, 0.8, 0.2, 0.6)
    love.graphics.rectangle("line", px, py, pw, ph, 6, 6)

    -- title
    love.graphics.setColor(0.9, 0.8, 0.2)
    love.graphics.printf(scheme.name:upper(), px, py + 10, pw, "center")

    -- separator
    love.graphics.setColor(0.4, 0.35, 0.2, 0.5)
    love.graphics.line(px + 15, py + 32, px + pw - 15, py + 32)

    -- control rows
    local by = py + 40
    for _, ctrl in ipairs(controls) do
        -- key/button name
        love.graphics.setColor(1, 0.95, 0.7)
        love.graphics.print(ctrl[1], px + 20, by)
        -- action
        love.graphics.setColor(0.6, 0.6, 0.6)
        love.graphics.printf(ctrl[2], px, by, pw - 20, "right")
        by = by + rowH
    end
end

function drawActiveEffects(w, h)
    if #orbs.activeEffects == 0 then return end
    local ex = w-155; local ey = 102
    love.graphics.setColor(0,0,0,0.7); love.graphics.rectangle("fill",ex,ey,150,#orbs.activeEffects*16+8,4,4)
    for i, eff in ipairs(orbs.activeEffects) do
        local c = eff.isGood and {0.3,1,0.3} or {1,0.3,0.3}; local pct = math.min(1,eff.remaining/30)
        love.graphics.setColor(c[1]*0.3,c[2]*0.3,c[3]*0.3); love.graphics.rectangle("fill",ex+4,ey+i*16-8,90,10,2,2)
        love.graphics.setColor(c[1],c[2],c[3],0.7); love.graphics.rectangle("fill",ex+4,ey+i*16-8,90*pct,10,2,2)
        love.graphics.setColor(1,1,1); love.graphics.print(eff.text,ex+6,ey+i*16-8)
        love.graphics.setColor(0.7,0.7,0.7); love.graphics.print(math.floor(eff.remaining).."s",ex+100,ey+i*16-8)
        if eff.remaining < 5 and math.sin(gameTime*8)>0 then love.graphics.setColor(1,1,0,0.3); love.graphics.rectangle("fill",ex+4,ey+i*16-8,90,10,2,2) end
    end
end

function drawMessages(w, h)
    local y = h/2-20
    for i = #messages, math.max(1,#messages-5),-1 do
        local m = messages[i]; local al = math.min(1,m.life)
        love.graphics.setColor(0,0,0,al*0.7); love.graphics.printf(m.text,1,y+1,w,"center")
        love.graphics.setColor(m.color[1],m.color[2],m.color[3],al); love.graphics.printf(m.text,0,y,w,"center")
        y = y-18
    end
end

-- ═══ SEC 21: MINIMAP — bottom-right corner radar ═══
function drawMinimap(w, h)
    local ms=100; local mx0=w-ms-10; local my0=h-ms-10; local mr=20
    love.graphics.setColor(0,0,0,0.8); love.graphics.rectangle("fill",mx0-2,my0-2,ms+4,ms+4,3,3)
    for sy=0,ms-1,2 do for sx=0,ms-1,2 do
        local wx=player.x+(sx-ms/2)*mr*2/ms; local wy=player.y+(sy-ms/2)*mr*2/ms
        if map:get(math.floor(wx),math.floor(wy))==1 then love.graphics.setColor(0.45,0.38,0.2) else love.graphics.setColor(0.12,0.10,0.06) end
        love.graphics.rectangle("fill",mx0+sx,my0+sy,2,2)
    end end
    for _,item in ipairs(items.list) do
        local ix=mx0+ms/2+(item.x-player.x)/mr*ms/2; local iy=my0+ms/2+(item.y-player.y)/mr*ms/2
        if ix>=mx0 and ix<=mx0+ms and iy>=my0 and iy<=my0+ms then love.graphics.setColor(1,1,1); love.graphics.rectangle("fill",ix,iy,2,2) end
    end
    for _,orb in ipairs(orbs.list) do
        local ox=mx0+ms/2+(orb.x-player.x)/mr*ms/2; local oy=my0+ms/2+(orb.y-player.y)/mr*ms/2
        if ox>=mx0 and ox<=mx0+ms and oy>=my0 and oy<=my0+ms then
            love.graphics.setColor(orb.state=="chase" and {1,0.2,0.2} or {0.5,0.2,0.7}); love.graphics.rectangle("fill",ox,oy,3,3)
        end
    end
    for _,e in ipairs(enemies.list) do
        local ex=mx0+ms/2+(e.x-player.x)/mr*ms/2; local ey=my0+ms/2+(e.y-player.y)/mr*ms/2
        if ex>=mx0 and ex<=mx0+ms and ey>=my0 and ey<=my0+ms then love.graphics.setColor(e.color[1],e.color[2],e.color[3]); love.graphics.rectangle("fill",ex,ey,2,2) end
    end
    love.graphics.setColor(0.9,0.8,0.2); love.graphics.circle("fill",mx0+ms/2,my0+ms/2,2)
    love.graphics.setColor(1,0.95,0.7,0.5); love.graphics.line(mx0+ms/2,my0+ms/2,mx0+ms/2+player.fx*6,my0+ms/2+player.fy*6)
    love.graphics.setColor(0.4,0.35,0.2,0.8); love.graphics.rectangle("line",mx0-2,my0-2,ms+4,ms+4,3,3)
end

-- ═══ TACTICAL MAP — full overlay, hold Left Trigger / Right Click ═══
function drawTacticalMap(w, h)
    local s = uiScale
    -- dark overlay
    love.graphics.setColor(0, 0, 0, 0.85)
    love.graphics.rectangle("fill", 0, 0, w, h)

    -- difficulty-based map settings
    -- Easy=1: full map, enemies, weapon dir
    -- Normal=2: local area, enemies, weapon dir
    -- Getting Worse=3: local area, no enemies, no weapon dir
    -- Hell=4: local area, no enemies, no weapon dir
    local showEnemies = difficultyIdx <= 2
    local showWeaponDir = difficultyIdx <= 2
    local showItems = difficultyIdx <= 2
    local showOrbs = difficultyIdx <= 2
    local mr = (difficultyIdx == 1) and 60 or 10  -- Easy=full 60 tiles, others=local 10 tiles

    -- map dimensions: fill most of screen, centered
    local padding = math.floor(40 * s)
    local ms = math.min(w, h) - padding * 2  -- square map
    local mx0 = math.floor((w - ms) / 2)
    local my0 = math.floor((h - ms) / 2)
    local pixStep = 3  -- pixels per sample point

    -- background
    love.graphics.setColor(0.05, 0.04, 0.02, 0.95)
    love.graphics.rectangle("fill", mx0 - 4, my0 - 4, ms + 8, ms + 8, 6, 6)

    -- map tiles
    for sy = 0, ms - 1, pixStep do
        for sx = 0, ms - 1, pixStep do
            local wx = player.x + (sx - ms/2) * mr * 2 / ms
            local wy = player.y + (sy - ms/2) * mr * 2 / ms
            if map:get(math.floor(wx), math.floor(wy)) == 1 then
                love.graphics.setColor(0.45, 0.38, 0.2)
            else
                love.graphics.setColor(0.10, 0.08, 0.04)
            end
            love.graphics.rectangle("fill", mx0 + sx, my0 + sy, pixStep, pixStep)
        end
    end

    -- items (white dots) — Easy and Normal only
    if showItems then
        for _, item in ipairs(items.list) do
            local ix = mx0 + ms/2 + (item.x - player.x) / mr * ms/2
            local iy = my0 + ms/2 + (item.y - player.y) / mr * ms/2
            if ix >= mx0 and ix <= mx0 + ms and iy >= my0 and iy <= my0 + ms then
                love.graphics.setColor(item.color[1], item.color[2], item.color[3], 0.8)
                love.graphics.rectangle("fill", ix - 1, iy - 1, 3, 3)
            end
        end
    end

    -- orbs — Easy and Normal only
    if showOrbs then
        for _, orb in ipairs(orbs.list) do
            local ox = mx0 + ms/2 + (orb.x - player.x) / mr * ms/2
            local oy = my0 + ms/2 + (orb.y - player.y) / mr * ms/2
            if ox >= mx0 and ox <= mx0 + ms and oy >= my0 and oy <= my0 + ms then
                if orb.state == "chase" then
                    love.graphics.setColor(1, 0.2, 0.2, 0.9)
                else
                    love.graphics.setColor(0.5, 0.2, 0.7, 0.9)
                end
                love.graphics.circle("fill", ox, oy, 3)
            end
        end
    end

    -- enemies (colored dots with glow) — Easy and Normal only
    if showEnemies then
        for _, e in ipairs(enemies.list) do
            local ex = mx0 + ms/2 + (e.x - player.x) / mr * ms/2
            local ey = my0 + ms/2 + (e.y - player.y) / mr * ms/2
            if ex >= mx0 and ex <= mx0 + ms and ey >= my0 and ey <= my0 + ms then
                -- glow
                love.graphics.setColor(e.color[1], e.color[2], e.color[3], 0.3)
                love.graphics.circle("fill", ex, ey, 6)
                -- dot
                love.graphics.setColor(e.color[1], e.color[2], e.color[3], 0.9)
                love.graphics.circle("fill", ex, ey, 3)
            end
        end
    end

    -- player (center) — large pulsing marker, always visible
    local pulse = 0.7 + 0.3 * math.sin(love.timer.getTime() * 4)
    local pcx = mx0 + ms/2
    local pcy = my0 + ms/2
    -- outer glow
    love.graphics.setColor(0.9, 0.8, 0.2, 0.25 * pulse)
    love.graphics.circle("fill", pcx, pcy, 14)
    -- mid ring
    love.graphics.setColor(0.9, 0.8, 0.2, 0.5 * pulse)
    love.graphics.circle("fill", pcx, pcy, 9)
    -- bright center
    love.graphics.setColor(1, 0.95, 0.5, 1)
    love.graphics.circle("fill", pcx, pcy, 5)

    -- weapon direction line — Easy and Normal only
    if showWeaponDir then
        love.graphics.setColor(1, 0.95, 0.7, 0.7)
        love.graphics.setLineWidth(2)
        love.graphics.line(pcx, pcy, pcx + player.fx * 18, pcy + player.fy * 18)
        love.graphics.setLineWidth(1)
    end

    -- compass labels
    love.graphics.setColor(0.5, 0.45, 0.2, 0.6)
    love.graphics.printf("N", mx0, my0 - math.floor(18*s), ms, "center")
    love.graphics.printf("S", mx0, my0 + ms + math.floor(4*s), ms, "center")
    love.graphics.print("W", mx0 - math.floor(16*s), my0 + ms/2 - 6)
    love.graphics.print("E", mx0 + ms + math.floor(6*s), my0 + ms/2 - 6)

    -- border
    love.graphics.setColor(0.4, 0.35, 0.2, 0.8)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", mx0 - 4, my0 - 4, ms + 8, ms + 8, 6, 6)
    love.graphics.setLineWidth(1)

    -- label
    love.graphics.setColor(0.9, 0.8, 0.2, 0.8)
    love.graphics.printf("TACTICAL MAP  |  Day "..wave.."  |  "..difficulties[difficultyIdx], 0, my0 - math.floor(38*s), w, "center")

    -- hint
    love.graphics.setColor(0.5, 0.5, 0.5, 0.5)
    love.graphics.printf("Hold LT / Right Click to view", 0, my0 + ms + math.floor(20*s), w, "center")
end