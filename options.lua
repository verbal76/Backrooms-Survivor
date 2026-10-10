-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║ OPTIONS.LUA — Settings menu: volume, brightness, resolution, etc    ║
-- ║                                                                     ║
-- ║ HOW TO MOD:                                                         ║
-- ║   Add/remove resolutions in Options.resolutions table               ║
-- ║   Change default values in Options.new() (musicVolume, sfxVolume)   ║
-- ║   Add new settings by extending self.items list                     ║
-- ║   Slider step = 0.05 per left/right press (5% increments)          ║
-- ╚══════════════════════════════════════════════════════════════════════╝

-- options.lua
-- Settings with headlamp brightness, volume, resolution

local Input = require("input")

local Options = {}
Options.__index = Options

Options.resolutions = {
    {w=640,h=480,label="640x480"}, {w=800,h=600,label="800x600"},
    {w=960,h=720,label="960x720"}, {w=1280,h=720,label="1280x720"},
    {w=1280,h=960,label="1280x960"}, {w=1920,h=1080,label="1920x1080"},
}
Options.controlModes = {"auto", "keyboard", "gamepad", "touch"}

function Options.new()
    local self = setmetatable({}, Options)
    self.musicVolume = .75       -- <<<< starts 3/4
    self.sfxVolume = .75         -- <<<< starts 3/4
    self.brightness = 1.0        -- <<<< starts maxed
    self.headlampBrightness = 1.0 -- <<<< starts maxed
    self.controlMode = 1
    self.resIndex = 3
    self.fullscreen = false
    self.visible = false
    self.showControls = false
    self.selectedItem = 1
    self.items = {"Music Volume","SFX Volume","Brightness","Headlamp","Controller","View Controls","Resolution","Fullscreen","Back"}
    return self
end

function Options:toggle() self.visible = not self.visible; self.showControls = false; self.selectedItem = 1 end

function Options:handleInput(key)
    if not self.visible then return false end
    if self.showControls then
        if key == "escape" or key == "return" or key == "space" or key == "b" then self.showControls = false end
        return true
    end
    if key == "up" then self.selectedItem = self.selectedItem - 1; if self.selectedItem < 1 then self.selectedItem = #self.items end
    elseif key == "down" then self.selectedItem = self.selectedItem + 1; if self.selectedItem > #self.items then self.selectedItem = 1 end
    elseif key == "left" or key == "a" then self:adjustItem(-1)
    elseif key == "right" or key == "d" then self:adjustItem(1)
    elseif key == "return" or key == "space" then
        local item = self.items[self.selectedItem]
        if item == "Back" then self.visible = false return true
        elseif item == "Fullscreen" then self.fullscreen = not self.fullscreen; self:applyResolution()
        elseif item == "View Controls" then self.showControls = true end
    elseif key == "escape" then self.visible = false return true end
    return true
end

function Options:handleGamepadInput(button)
    if not self.visible then return false end
    if self.showControls then
        if button == "b" or button == "a" or button == "start" or button == "back" then self.showControls = false end
        return true
    end
    if button == "dpup" then return self:handleInput("up") end
    if button == "dpdown" then return self:handleInput("down") end
    if button == "dpleft" then return self:handleInput("left") end
    if button == "dpright" then return self:handleInput("right") end
    if button == "a" then return self:handleInput("return") end
    if button == "b" or button == "start" or button == "back" then self.visible = false return true end
    return true
end

function Options:adjustItem(dir)
    local item = self.items[self.selectedItem]
    if item == "Music Volume" then self.musicVolume = math.max(0, math.min(1, self.musicVolume + dir * 0.05))
    elseif item == "SFX Volume" then self.sfxVolume = math.max(0, math.min(1, self.sfxVolume + dir * 0.05))
    elseif item == "Brightness" then self.brightness = math.max(0, math.min(1, self.brightness + dir * 0.05))
    elseif item == "Headlamp" then self.headlampBrightness = math.max(0.1, math.min(1, self.headlampBrightness + dir * 0.05))
    elseif item == "Controller" then
        self.controlMode = self.controlMode + dir
        if self.controlMode < 1 then self.controlMode = #Options.controlModes end
        if self.controlMode > #Options.controlModes then self.controlMode = 1 end
    elseif item == "Resolution" then
        self.resIndex = self.resIndex + dir
        if self.resIndex < 1 then self.resIndex = #Options.resolutions end
        if self.resIndex > #Options.resolutions then self.resIndex = 1 end
        self:applyResolution()
    elseif item == "Fullscreen" then self.fullscreen = not self.fullscreen; self:applyResolution() end
end

function Options:applyResolution()
    local res = Options.resolutions[self.resIndex]
    love.window.setMode(res.w, res.h, {fullscreen=self.fullscreen, fullscreentype="desktop", resizable=not self.fullscreen})
end

function Options:getControlMode() return Options.controlModes[self.controlMode] end
function Options:getAmbientBoost() return self.brightness * 0.08 end

function Options:draw(w, h)
    if not self.visible then return end

    love.graphics.setColor(0,0,0,0.9)
    love.graphics.rectangle("fill",0,0,w,h)

    if self.showControls then
        self:drawControlScheme(w, h)
        return
    end

    local cx = w/2
    local font = love.graphics.getFont()
    local lineH = math.max(36, (font and font:getHeight() or 24) + 12)

    -- Two-column layout with a hard gap so labels never collide with values/sliders
    local gap = 40
    local labelW = math.min(240, math.floor(w * 0.26))
    local sliderW = math.min(220, math.floor(w * 0.22))
    local percentW = 70

    local labelX = cx - gap - labelW
    local valueX = cx + gap

    local panelLeft = labelX - 20
    local panelRight = valueX + sliderW + percentW + 20
    local panelW = panelRight - panelLeft

    local menuH = (#self.items * lineH)
    local startY = (h/2) - (menuH/2)

    -- Title
    love.graphics.setColor(0.9,0.8,0.2)
    love.graphics.printf("OPTIONS", 0, startY - (lineH*1.4), w, "center")

    for i, item in ipairs(self.items) do
        local y = startY + (i-1) * lineH
        local sel = (i == self.selectedItem)

        if sel then
            love.graphics.setColor(0.4,0.35,0.15,0.5)
            love.graphics.rectangle("fill", panelLeft, y-6, panelW, lineH-2, 4, 4)
            love.graphics.setColor(1,0.9,0.3)
        else
            love.graphics.setColor(0.7,0.7,0.7)
        end

        -- Label (right-aligned)
        love.graphics.printf(item, labelX, y, labelW, "right")

        -- Value / control (left-aligned)
        if item == "Music Volume" then
            self:drawSlider(valueX, y, sliderW, self.musicVolume, sel)
        elseif item == "SFX Volume" then
            self:drawSlider(valueX, y, sliderW, self.sfxVolume, sel)
        elseif item == "Brightness" then
            self:drawSlider(valueX, y, sliderW, self.brightness, sel)
        elseif item == "Headlamp" then
            self:drawSlider(valueX, y, sliderW, self.headlampBrightness, sel)
        elseif item == "Controller" then
            love.graphics.print("< "..Options.controlModes[self.controlMode]:upper().." >", valueX, y)
        elseif item == "View Controls" then
            love.graphics.print("[ENTER to view]", valueX, y)
        elseif item == "Resolution" then
            love.graphics.print("< "..Options.resolutions[self.resIndex].label.." >", valueX, y)
        elseif item == "Fullscreen" then
            love.graphics.print(self.fullscreen and "ON" or "OFF", valueX, y)
        end
    end
end
function Options:drawSlider(x, y, sw, value, sel)
    love.graphics.setColor(0.2,0.2,0.2); love.graphics.rectangle("fill",x,y+5,sw,8,3,3)
    love.graphics.setColor(sel and {0.9,0.8,0.2} or {0.5,0.45,0.2}); love.graphics.rectangle("fill",x,y+5,sw*value,8,3,3)
    love.graphics.setColor(1,1,1); love.graphics.print(math.floor(value*100).."%",x+sw+8,y)
end

function Options:drawControlScheme(w, h)
    local mode = Options.controlModes[self.controlMode]
    if mode == "auto" then mode = "keyboard" end
    local scheme = Input.schemes[mode] or Input.schemes.keyboard
    local s = uiScale or 1
    local cx = w/2

    -- Use the active font height so rows never overlap when resolution/fonts change
    local font = love.graphics.getFont()
    local rowH = math.floor(font:getHeight() + 6 * s)

    -- Panel sizing
    local panelW = math.min(w - math.floor(80*s), math.floor(560*s))
    local panelL = cx - panelW/2
    local panelR = cx + panelW/2
    local padX = math.floor(14*s)

    -- Columns
    local keyColW = math.floor(panelW * 0.42)
    local gap = math.floor(18*s)
    local keyX = panelL + padX
    local descX = panelL + padX + keyColW + gap
    local descW = panelR - descX - padX

    -- Compute total height for vertical centering
    local headerH = math.floor(56*s)
    local sepH = math.floor(18*s)
    local listH = #scheme.controls * rowH
    local footerH = math.floor(70*s)
    local totalH = headerH + sepH + listH + sepH + footerH

    local y = math.floor((h - totalH)/2)
    y = math.max(y, math.floor(40*s))

    -- Title
    love.graphics.setColor(0.9,0.8,0.2)
    love.graphics.printf("CONTROLS: "..scheme.name, 0, y, w, "center")
    y = y + math.floor(40*s)

    -- Separator
    love.graphics.setColor(0.5,0.45,0.2)
    love.graphics.line(panelL + math.floor(30*s), y, panelR - math.floor(30*s), y)
    y = y + math.floor(12*s)

    -- Rows
    for _, ctrl in ipairs(scheme.controls) do
        love.graphics.setColor(1,0.9,0.3)
        love.graphics.printf(ctrl[1], keyX, y, keyColW, "right")
        love.graphics.setColor(0.8,0.8,0.8)
        love.graphics.printf(ctrl[2], descX, y, descW, "left")
        y = y + rowH
    end

    y = y + math.floor(10*s)
    love.graphics.setColor(0.5,0.45,0.2)
    love.graphics.line(panelL + math.floor(30*s), y, panelR - math.floor(30*s), y)
    y = y + math.floor(14*s)

    love.graphics.setColor(0.7,0.7,0.7)
    love.graphics.printf("ONE LIFE SURVIVAL - No saves, no loads", 0, y, w, "center")
    y = y + rowH
    love.graphics.printf("1 Day = 5 minutes - Survive as long as you can", 0, y, w, "center")
    -- controller hint removed
end

return Options
