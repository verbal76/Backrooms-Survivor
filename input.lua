-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║ INPUT.LUA — Unified input: keyboard+mouse, Xbox gamepad, touch      ║
-- ║                                                                     ║
-- ║ HOW TO MOD:                                                         ║
-- ║   Edit key bindings in updateKeyboard() (WASD section)              ║
-- ║   Adjust deadzone (0.2) for gamepad stick sensitivity               ║
-- ║   Change touch button positions/sizes in getTouchButtons()          ║
-- ║   Edit Input.schemes tables to change control help text             ║
-- ║                                                                     ║
-- ║ SECTIONS:                                                           ║
-- ║   CONTROL SCHEMES ..... help text shown in options screen           ║
-- ║   CONSTRUCTOR ......... initial input state + edge detection vars   ║
-- ║   AUTO-DETECT ......... picks keyboard/gamepad/touch automatically  ║
-- ║   KEYBOARD UPDATE ..... WASD movement + mouse aiming               ║
-- ║   GAMEPAD UPDATE ...... left/right sticks + triggers + d-pad        ║
-- ║   TOUCH UPDATE ........ virtual joysticks + auto-fire               ║
-- ║   TOUCH BUTTONS ....... on-screen button positions and labels       ║
-- ╚══════════════════════════════════════════════════════════════════════╝

-- input.lua
-- Unified: keyboard+mouse, Xbox gamepad, touch/mobile

local Input = {}
Input.__index = Input

Input.schemes = {
    keyboard = {
        name = "Keyboard + Mouse",
        controls = {
            {"W/A/S/D", "Move (aim-relative)"},
            {"Mouse", "Aim direction"},
            {"Left Click / Space", "Fire weapon"},
            {"Right Click", "Tactical Map"},
            {"Shift", "Sprint"},
            {"H", "Toggle Headlamp"},
            {"X", "Use Battery"},
            {"Q", "Use bomb"},
            {"E / Tab / Scroll", "Cycle weapons"},
            {"1", "Almond Water"},
            {"2", "Bandage"},
            {"3", "Food"},
            {"ESC", "Pause / Menu"},
            {"F1 (Hold)", "Show Controls"},
            {"F2 (Hold)", "Run Stats"},
        }
    },
    gamepad = {
        name = "Xbox Controller",
        controls = {
            {"Left Stick", "Move"},
            {"Right Stick", "Aim"},
            {"Right Trigger", "Fire weapon"},
            {"Left Trigger", "Tactical Map"},
            {"A Button (Hold)", "Sprint"},
            {"B Button", "Toggle Headlamp"},
            {"Left Stick Click (L3)", "Use Battery"},
            {"Y Button (Hold)", "Status HUD"},
            {"Right Bumper", "Use Bomb"},
            {"D-Pad Left/Right", "Cycle weapons"},
            {"D-Pad Up", "Almond Water / Hold: Run Stats"},
            {"Back/View", "Pause / Menu"},
            {"D-Pad Down (Hold)", "Show Controls"},
        }
    },
    touch = {
        name = "Touchscreen",
        controls = {
            {"Left Side Drag", "Move (virtual stick)"},
            {"Right Side Drag", "Aim (virtual stick)"},
            {"Right Stick Hold", "Auto-fire"},
            {"BOMB Button", "Use bomb"},
            {"WPN Button", "Cycle weapon"},
            {"H2O / MED / EAT", "Use items"},
            {"Double-Tap Center", "Pause / Menu"},
        }
    },
}

function Input.new()
    local self = setmetatable({}, Input)
    self.mode = "auto"
    self.detectedMode = nil
    self.gamepad = nil
-- UI navigation pulses (for menus/perk picker)
self.uiLeft = false; self.uiRight = false
self.uiUp = false; self.uiDown = false
self._uiHoldX = 0; self._uiHoldY = 0
self._uiRepeatT = 0
    self.deadzone = 0.2
    self.moveX = 0; self.moveY = 0
    self.aimX = 0; self.aimY = 0
    self.aimAngle = 0; self.aimActive = false
    self.fire = false; self.altFire = false
    self.sprint = false
    self.useBomb = false
    self.showStatusHud = false
    self.showControls = false
    self.showRunStats = false  -- V5: hold D-pad Up / Tab for run stats popup
    self.pause = false; self.restart = false
    -- gamepad edge detection
    self.prevDpadDown = false; self.prevDpadUp = false
    self.prevDpadLeft = false; self.prevDpadRight = false
    self.prevB = false; self.prevStart = false
    -- touch state
    self.leftStick = {active=false, ox=0, oy=0, cx=0, cy=0, id=nil}
    self.rightStick = {active=false, ox=0, oy=0, cx=0, cy=0, id=nil}
    self.doubleTapTimer = 0; self.doubleTapCount = 0
    return self
end

function Input:detectGamepad()
    local joysticks = love.joystick.getJoysticks()
    if #joysticks > 0 then self.gamepad = joysticks[1]; return true end
    return false
end

function Input:getActiveMode()
    if self.mode ~= "auto" then return self.mode end
    return self.detectedMode or "keyboard"
end

function Input:update(dt, playerX, playerY, playerAngle, cameraX, cameraY, tileSize)
    self.useBomb = false; self.showStatusHud = false
    self.showControls = false; self.showRunStats = false
    self.pause = false; self.restart = false

    if not self.gamepad then self:detectGamepad() end
    if self.gamepad and not self.gamepad:isConnected() then
        self.gamepad = nil
        if self.detectedMode == "gamepad" then self.detectedMode = nil end
    end

    -- auto-detect
    if self.mode == "auto" then
        if self.gamepad then
            local lx = self.gamepad:getGamepadAxis("leftx") or 0
            local ly = self.gamepad:getGamepadAxis("lefty") or 0
            local rx = self.gamepad:getGamepadAxis("rightx") or 0
            local ry = self.gamepad:getGamepadAxis("righty") or 0
            local rt = self.gamepad:getGamepadAxis("triggerright") or 0
            local lt = self.gamepad:getGamepadAxis("triggerleft") or 0
            local anyBtn = false
            for _, b in ipairs({"a","b","x","y","start","back","dpup","dpdown","dpleft","dpright","leftshoulder","rightshoulder"}) do
                if self.gamepad:isGamepadDown(b) then anyBtn = true break end
            end
            -- triggers may report 0..1 or -1..1 depending on controller; use abs > 0.3 to catch both
            if math.abs(lx)>0.5 or math.abs(ly)>0.5 or math.abs(rx)>0.5 or math.abs(ry)>0.5 or math.abs(rt)>0.3 or math.abs(lt)>0.3 or anyBtn then
                self.detectedMode = "gamepad"
            end
        end
        if not self.detectedMode then
            if love.keyboard.isDown("w","a","s","d","space","lshift","escape") then
                self.detectedMode = "keyboard"
            end
        end
    end

    local active = self:getActiveMode()
    if active == "gamepad" and self.gamepad then self:updateGamepad(dt, playerX, playerY)
    elseif active == "touch" then self:updateTouch(dt, playerX, playerY, cameraX, cameraY, tileSize)
    else self:updateKeyboard(dt, playerX, playerY, cameraX, cameraY, tileSize) end

    if self.doubleTapTimer > 0 then
        self.doubleTapTimer = self.doubleTapTimer - dt
        if self.doubleTapTimer <= 0 then self.doubleTapCount = 0 end
    end
end

function Input:updateKeyboard(dt, px, py, camX, camY, ts)
    self.moveX = 0; self.moveY = 0
    if love.keyboard.isDown("w","up") then self.moveY = -1 end
    if love.keyboard.isDown("s","down") then self.moveY = 1 end
    if love.keyboard.isDown("a","left") then self.moveX = -1 end
    if love.keyboard.isDown("d","right") then self.moveX = 1 end
    local mx, my = love.mouse.getPosition()
    self.aimX = mx / ts + camX; self.aimY = my / ts + camY
    local dx = self.aimX - px; local dy = self.aimY - py
    if dx ~= 0 or dy ~= 0 then self.aimAngle = math.atan2(dy, dx) end
    self.aimActive = true
    self.fire = love.mouse.isDown(1) or love.keyboard.isDown("space")
    self.altFire = love.mouse.isDown(2)
    self.sprint = love.keyboard.isDown("lshift","rshift")
    self.showControls = love.keyboard.isDown("f1")
    self.showRunStats = love.keyboard.isDown("f2")  -- V5: hold F2 for run stats
end

function Input:updateGamepad(dt, px, py)
    local gp = self.gamepad
    local lx = gp:getGamepadAxis("leftx") or 0
    local ly = gp:getGamepadAxis("lefty") or 0
    if math.abs(lx) < self.deadzone then lx = 0 
-- ============================================
-- Universal UI navigation (D-pad + Left Stick)
-- Produces pulses: uiLeft/uiRight/uiUp/uiDown
-- ============================================
self.uiLeft, self.uiRight, self.uiUp, self.uiDown = false, false, false, false

local dzUI = 0.35  -- UI deadzone (separate from movement deadzone is OK)

local uiL = gp:isGamepadDown("dpleft")  or (lx < -dzUI)
local uiR = gp:isGamepadDown("dpright") or (lx >  dzUI)
local uiU = gp:isGamepadDown("dpup")    or (ly < -dzUI)
local uiD = gp:isGamepadDown("dpdown")  or (ly >  dzUI)

local holdX = uiL and -1 or (uiR and 1 or 0)
local holdY = uiU and -1 or (uiD and 1 or 0)

-- Edge detect + optional repeat
local firstDelay = 0.22
local repeatRate = 0.10

local changed = (holdX ~= self._uiHoldX) or (holdY ~= self._uiHoldY)

if changed then
    self._uiHoldX, self._uiHoldY = holdX, holdY
    self._uiRepeatT = 0

    self.uiLeft  = (holdX == -1)
    self.uiRight = (holdX ==  1)
    self.uiUp    = (holdY == -1)
    self.uiDown  = (holdY ==  1)
else
    if holdX ~= 0 or holdY ~= 0 then
        self._uiRepeatT = self._uiRepeatT + (dt or 0)
        if self._uiRepeatT > firstDelay then
            if (self._uiRepeatT - firstDelay) % repeatRate < (dt or 0) then
                self.uiLeft  = (holdX == -1)
                self.uiRight = (holdX ==  1)
                self.uiUp    = (holdY == -1)
                self.uiDown  = (holdY ==  1)
            end
        end
    end
end
end
    if math.abs(ly) < self.deadzone then ly = 0 end
    self.moveX = lx; self.moveY = ly

    local rx = gp:getGamepadAxis("rightx") or 0
    local ry = gp:getGamepadAxis("righty") or 0
    if math.abs(rx) < self.deadzone then rx = 0 end
    if math.abs(ry) < self.deadzone then ry = 0 end
    self.aimActive = math.abs(rx) > self.deadzone or math.abs(ry) > self.deadzone
    if self.aimActive then
        self.aimAngle = math.atan2(ry, rx)
        self.aimX = px + math.cos(self.aimAngle) * 5
        self.aimY = py + math.sin(self.aimAngle) * 5
    end

    -- Right trigger: fire (0.2 threshold avoids accidental shots)
    local rtRaw = gp:getGamepadAxis("triggerright") or 0
    self.fire = rtRaw > 0.2

    -- Left trigger: tactical map
    -- Low threshold (0.15) handles both 0..1 and -1..1 trigger ranges
    local ltRaw = gp:getGamepadAxis("triggerleft") or 0
    self.altFire = ltRaw > 0.15
    self.sprint = gp:isGamepadDown("a")

    -- d-pad edges
    local du = gp:isGamepadDown("dpup")
    local dl = gp:isGamepadDown("dpleft")
    local dr = gp:isGamepadDown("dpright")
    self.prevDpadUp = du
    self.prevDpadLeft = dl; self.prevDpadRight = dr

    -- Y hold = status HUD
    self.showStatusHud = gp:isGamepadDown("dpup")

    -- D-pad down hold = controls overlay
    self.showControls = false

    -- V5: D-pad up hold = run stats popup (single press still uses health)
    self.showRunStats = gp:isGamepadDown("dpdown")

    -- B = headlamp, X = battery, RB = bomb handled in love.gamepadpressed
    self.prevB = gp:isGamepadDown("b")

    -- back/view is handled in love.gamepadpressed for pause
    self.prevStart = gp:isGamepadDown("back")

    -- start = restart on death only (handled in main)
    self.restart = gp:isGamepadDown("start")
end

function Input:updateTouch(dt, px, py, camX, camY, ts)
    if self.leftStick.active then
        local dx = self.leftStick.cx - self.leftStick.ox
        local dy = self.leftStick.cy - self.leftStick.oy
        local dist = math.sqrt(dx*dx + dy*dy)
        local maxR = 50
        if dist > 5 then
            self.moveX = math.max(-1, math.min(1, dx / maxR))
            self.moveY = math.max(-1, math.min(1, dy / maxR))
            self.sprint = dist > maxR * 0.8
        else self.moveX = 0; self.moveY = 0 end
    else self.moveX = 0; self.moveY = 0 end

    if self.rightStick.active then
        local dx = self.rightStick.cx - self.rightStick.ox
        local dy = self.rightStick.cy - self.rightStick.oy
        local dist = math.sqrt(dx*dx + dy*dy)
        if dist > 10 then
            self.aimAngle = math.atan2(dy, dx)
            self.aimX = px + math.cos(self.aimAngle) * 5
            self.aimY = py + math.sin(self.aimAngle) * 5
            self.aimActive = true; self.fire = true
        else self.fire = false; self.aimActive = false end
    else self.fire = false end
end

function Input:getTouchButtons(w, h)
    return {
        {x=w-80, y=h-80, r=30, action="bomb", label="BOMB", color={1,0.5,0.1}},
        {x=w-80, y=50, r=25, action="weapon", label="WPN", color={0.7,0.7,0.7}},
        {x=30, y=h-140, r=22, action="health", label="H2O", color={0.3,0.8,1}},
        {x=75, y=h-140, r=22, action="bandage", label="MED", color={0.3,1,0.3}},
        {x=120, y=h-140, r=22, action="food", label="EAT", color={0.8,0.6,0.2}},
    }
end

function Input:touchpressed(id, x, y, w, h)
    if self.mode == "auto" then self.detectedMode = "touch" end
    local cx, cy = w/2, h/2
    if math.abs(x-cx)<100 and math.abs(y-cy)<100 then
        if self.doubleTapTimer > 0 then
            self.doubleTapCount = self.doubleTapCount + 1
            if self.doubleTapCount >= 2 then
                self.pause = true; self.doubleTapCount = 0; self.doubleTapTimer = 0; return
            end
        else self.doubleTapCount = 1 end
        self.doubleTapTimer = 0.4
    end
    local buttons = self:getTouchButtons(w, h)
    for _, btn in ipairs(buttons) do
        local dx = x - btn.x; local dy = y - btn.y
        if dx*dx + dy*dy < btn.r * btn.r then
            if btn.action == "bomb" then self.useBomb = true
            elseif btn.action == "weapon" then self.cycleWeaponRight = true
            elseif btn.action == "health" then self.useHealth = true
            elseif btn.action == "bandage" then self.useBandage = true
            elseif btn.action == "food" then self.useFood = true end
            return
        end
    end
    if x < w/2 then
        self.leftStick = {active=true, ox=x, oy=y, cx=x, cy=y, id=id}
    else
        self.rightStick = {active=true, ox=x, oy=y, cx=x, cy=y, id=id}
    end
end

function Input:touchmoved(id, x, y)
    if self.leftStick.id == id then self.leftStick.cx = x; self.leftStick.cy = y end
    if self.rightStick.id == id then self.rightStick.cx = x; self.rightStick.cy = y end
end

function Input:touchreleased(id)
    if self.leftStick.id == id then self.leftStick.active = false; self.leftStick.id = nil end
    if self.rightStick.id == id then self.rightStick.active = false; self.rightStick.id = nil end
end

function Input:drawTouchControls(w, h)
    if self:getActiveMode() ~= "touch" then return end
    if self.leftStick.active then
        love.graphics.setColor(1,1,1,0.15); love.graphics.circle("fill",self.leftStick.ox,self.leftStick.oy,50)
        love.graphics.setColor(1,1,1,0.3); love.graphics.circle("fill",self.leftStick.cx,self.leftStick.cy,20)
        love.graphics.circle("line",self.leftStick.ox,self.leftStick.oy,50)
    end
    if self.rightStick.active then
        love.graphics.setColor(1,0.3,0.2,0.15); love.graphics.circle("fill",self.rightStick.ox,self.rightStick.oy,50)
        love.graphics.setColor(1,0.3,0.2,0.3); love.graphics.circle("fill",self.rightStick.cx,self.rightStick.cy,20)
        love.graphics.circle("line",self.rightStick.ox,self.rightStick.oy,50)
    end
    local buttons = self:getTouchButtons(w, h)
    for _, btn in ipairs(buttons) do
        love.graphics.setColor(btn.color[1],btn.color[2],btn.color[3],0.3); love.graphics.circle("fill",btn.x,btn.y,btn.r)
        love.graphics.setColor(btn.color[1],btn.color[2],btn.color[3],0.6); love.graphics.circle("line",btn.x,btn.y,btn.r)
        love.graphics.setColor(1,1,1,0.7); love.graphics.printf(btn.label,btn.x-btn.r,btn.y-6,btn.r*2,"center")
    end
end

return Input
