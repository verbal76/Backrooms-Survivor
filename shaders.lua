-- shaders.lua
-- Post FX + haze + dust mask helpers (Darkwood-ish)

local Shaders = {}

local function clamp(x,a,b)
  if x<a then return a elseif x>b then return b else return x end
end

function Shaders.load()
  -- Post FX
  Shaders.post = love.graphics.newShader([[
    extern number time;
    extern number grainAmount;
    extern number vignetteStrength;
    extern number desat;
    extern number contrast;
    extern number exposure;

    float hash(vec2 p) {
      p = fract(p * vec2(123.34, 456.21));
      p += dot(p, p + 45.32);
      return fract(p.x * p.y);
    }

    vec4 effect(vec4 color, Image tex, vec2 uv, vec2 px) {
      vec4 c = Texel(tex, uv);
      c.rgb *= exposure;

      float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
      c.rgb = mix(c.rgb, vec3(l), desat);
      c.rgb = (c.rgb - 0.5) * contrast + 0.5;

      vec2 d = uv - vec2(0.5);
      float v = smoothstep(0.85, 0.25, dot(d,d) * 1.5);
      c.rgb *= mix(1.0 - vignetteStrength, 1.0, v);

      float n = hash(uv * (px * 0.15) + time * 60.0);
      c.rgb += (n - 0.5) * grainAmount;

      return c * color;
    }
  ]])

  -- Procedural haze (screen-space, subtle)
  Shaders.haze = love.graphics.newShader([[
    extern number time;
    extern vec2 camPx;
    extern number parallax;
    extern number strength;

    float hash(vec2 p){
      p = fract(p * vec2(123.34, 345.45));
      p += dot(p, p + 34.345);
      return fract(p.x * p.y);
    }

    float noise(vec2 p){
      vec2 i = floor(p);
      vec2 f = fract(p);
      float a = hash(i);
      float b = hash(i + vec2(1.0, 0.0));
      float c = hash(i + vec2(0.0, 1.0));
      float d = hash(i + vec2(1.0, 1.0));
      vec2 u = f*f*(3.0-2.0*f);
      return mix(a,b,u.x) + (c-a)*u.y*(1.0-u.x) + (d-b)*u.x*u.y;
    }

    vec4 effect(vec4 color, Image tex, vec2 uv, vec2 px){
      // move noise opposite camera a bit for parallax feel
      vec2 p = (uv * vec2(3.0, 3.0)) + (camPx * parallax) / 600.0 + vec2(time*0.01, -time*0.008);
      float n = noise(p * 6.0);
      float m = (n - 0.5) * strength;
      // haze is near-white so it doesn't crush blacks
      return vec4(vec3(1.0 + m), 1.0) * color;
    }
  ]])

  -- Dust mask shader: multiplies dust by light intensity so it only appears in lit areas
  Shaders.dustMask = love.graphics.newShader([[
    extern Image lightTex;
    extern number intensity;

    vec4 effect(vec4 color, Image tex, vec2 uv, vec2 px){
      vec4 d = Texel(tex, uv) * color;
      float l = Texel(lightTex, uv).r; // light is grayscale
      float a = d.a * l * intensity;
      return vec4(d.rgb * a, a);
    }
  ]])
end

function Shaders.setPostUniforms(t, cfg)
  local s = Shaders.post; if not s then return end
  s:send("time", t or 0)
  s:send("grainAmount", clamp(cfg.grainAmount or 0.0, 0.0, 0.20))
  s:send("vignetteStrength", clamp(cfg.vignetteStrength or 0.0, 0.0, 1.0))
  s:send("desat", clamp(cfg.desat or 0.0, 0.0, 1.0))
  s:send("contrast", clamp(cfg.contrast or 1.00, 0.70, 1.40))
  s:send("exposure", clamp(cfg.exposure or 1.00, 0.60, 1.60))
end

function Shaders.setHazeUniforms(t, camPxX, camPxY, cfg)
  local s = Shaders.haze; if not s then return end
  s:send("time", t or 0)
  s:send("camPx", {camPxX or 0, camPxY or 0})
  s:send("parallax", clamp(cfg.hazeParallax or 0.16, 0.0, 1.0))
  s:send("strength", clamp(cfg.hazeStrength or 0.35, 0.0, 1.0))
end

function Shaders.setDustMaskUniforms(lightCanvas, cfg)
  local s = Shaders.dustMask; if not s then return end
  s:send("lightTex", lightCanvas)
  s:send("intensity", clamp(cfg.dustIntensity or 0.65, 0.0, 2.0))
end

-- backwards compat
Shaders.setDustUniforms = Shaders.setDustMaskUniforms

return Shaders
