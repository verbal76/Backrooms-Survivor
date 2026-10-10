-- render.lua
-- AAA-ish canvas pipeline: scene -> light mask -> composite -> (haze + dust) -> post FX
--
-- Designed to "play nice" together:
--  - Lighting is a light mask canvas (0..1) multiplied into the scene.
--  - Haze is a subtle shader overlay (screen-space with camera-parallax).
--  - Dust is drawn additively but masked by the light canvas (only shows in headlamp).

local Render = {}

Render.cfg = {
  -- Post FX
  grainAmount = 0.020,
  vignetteStrength = 0.20,
  desat = 0.08,
  contrast = 1.05,
  exposure = 1.12,

  -- Lighting
  ambient = 0.22,     -- base light level (0 = pitch black)

  -- Haze
  hazeAlpha = 0.025,   -- 0.03 - 0.10
  hazeParallax = 0.14,
  hazeStrength = 0.10,

  -- Dust (headlamp)
  dustCount = 70,
  dustAlpha = 0.07,
  dustRadiusPx = 1.4,
  dustSpeed = 8,
  dustJitter = 0.25,
  dustIntensity = 0.55, -- final multiplier inside dustMask shader
}

function Render.load(shaders)
  Render.shaders = shaders
  Render.dust = { list = {}, seeded = false }
  Render:resize(love.graphics.getWidth(), love.graphics.getHeight())
end

function Render:resize(w, h)
  Render.w, Render.h = w, h

  Render.scene = love.graphics.newCanvas(w, h, { msaa = 0 })
  Render.light = love.graphics.newCanvas(w, h, { msaa = 0 })
  Render.composite = love.graphics.newCanvas(w, h, { msaa = 0 })
  Render.dustCanvas = love.graphics.newCanvas(w, h, { msaa = 0 })
end

-- Call once per frame
function Render.beginScene()
  love.graphics.setCanvas(Render.scene)
  love.graphics.clear(0, 0, 0, 1)
end

function Render.endScene()
  love.graphics.setCanvas()
end

-- Build the light mask. Draw your flashlight cone / light mask in the callback.
function Render.buildLight(drawLightsFn)
  love.graphics.setCanvas(Render.light)

  local a = Render.cfg.ambient
  love.graphics.clear(a, a, a, 1)

  love.graphics.setBlendMode("add", "alphamultiply")
  if drawLightsFn then drawLightsFn() end
  love.graphics.setBlendMode("alpha")

  love.graphics.setCanvas()
end

-- ─────────────────────────────────────────────────────────────
-- Dust system (screen-space particles, masked by light in present())
-- ─────────────────────────────────────────────────────────────
local function seedDust()
  if Render.dust.seeded then return end
  Render.dust.seeded = true
  Render.dust.list = {}

  local count = Render.cfg.dustCount or 90
  for i = 1, count do
    Render.dust.list[i] = {
      x = math.random() * Render.w,
      y = math.random() * Render.h,
      vx = (math.random() * 2 - 1) * 0.35,
      vy = (math.random() * 2 - 1) * 0.35,
      phase = math.random() * 10,
    }
  end
end

function Render.update(dt)
  if not Render.dust then return end
  seedDust()

  local speed = Render.cfg.dustSpeed or 10
  local jitter = Render.cfg.dustJitter or 0.25

  for _, p in ipairs(Render.dust.list) do
    p.phase = p.phase + dt
    p.x = p.x + (p.vx * speed * dt) + math.sin(p.phase * 0.9) * jitter
    p.y = p.y + (p.vy * speed * dt) + math.cos(p.phase * 1.1) * jitter

    -- wrap
    if p.x < -10 then p.x = Render.w + 10 end
    if p.x > Render.w + 10 then p.x = -10 end
    if p.y < -10 then p.y = Render.h + 10 end
    if p.y > Render.h + 10 then p.y = -10 end
  end
end

local function drawDustToCanvas()
  love.graphics.setCanvas(Render.dustCanvas)
  love.graphics.clear(0, 0, 0, 0)

  local a = Render.cfg.dustAlpha or 0.10
  local r = Render.cfg.dustRadiusPx or 1.6

  -- draw simple circles as white alpha
  love.graphics.setBlendMode("alpha")
  love.graphics.setColor(1, 1, 1, a)
  for _, p in ipairs(Render.dust.list) do
    love.graphics.circle("fill", p.x, p.y, r)
  end
  love.graphics.setColor(1, 1, 1, 1)

  love.graphics.setCanvas()
end

-- ─────────────────────────────────────────────────────────────
-- Present: scene * light, then haze + dust, then post FX to screen
-- camPxX/camPxY are camera position in pixels (for haze parallax)
-- ─────────────────────────────────────────────────────────────
function Render.present(timeSeconds, camPxX, camPxY)
  local t = timeSeconds or 0

  -- (1) Composite: scene * light
  love.graphics.setCanvas(Render.composite)
  love.graphics.clear(0, 0, 0, 1)

  love.graphics.setBlendMode("alpha")
  love.graphics.setColor(1,1,1,1)
  love.graphics.draw(Render.scene, 0, 0)

  love.graphics.setBlendMode("multiply", "premultiplied")
  love.graphics.draw(Render.light, 0, 0)
  love.graphics.setBlendMode("alpha")

  -- (2) Haze (subtle, screen-space)
  if Render.shaders and Render.shaders.haze and (Render.cfg.hazeAlpha or 0) > 0 then
    Render.shaders.setHazeUniforms(t, camPxX or 0, camPxY or 0, Render.cfg)
    love.graphics.setShader(Render.shaders.haze)
    love.graphics.setColor(1, 1, 1, Render.cfg.hazeAlpha)
    love.graphics.rectangle("fill", 0, 0, Render.w, Render.h)
    love.graphics.setShader(nil)
    love.graphics.setColor(1, 1, 1, 1)
  end

  -- (3) Dust (masked by light)
  if Render.shaders and Render.shaders.dustMask then
    drawDustToCanvas()
    Render.shaders.setDustUniforms(Render.light, Render.cfg)
    love.graphics.setBlendMode("add", "alphamultiply")
    love.graphics.setShader(Render.shaders.dustMask)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(Render.dustCanvas, 0, 0)
    love.graphics.setShader()
    love.graphics.setBlendMode("alpha")
  end

  love.graphics.setCanvas()

  -- (4) Post FX on screen
  if Render.shaders and Render.shaders.post then
    Render.shaders.setPostUniforms(t, Render.cfg)
    love.graphics.setShader(Render.shaders.post)
  end

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(Render.composite, 0, 0)
  love.graphics.setShader()
end

return Render