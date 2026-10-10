-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║ CONF.LUA — LÖVE2D startup config (runs before love.load)           ║
-- ║                                                                     ║
-- ║ HOW TO MOD:                                                         ║
-- ║   window.width/height = default window size                         ║
-- ║   fullscreen = true for fullscreen by default                       ║
-- ║   t.title = window title bar text                                   ║
-- ╚══════════════════════════════════════════════════════════════════════╝

function love.conf(t)
    t.title = "Backrooms Survivor"
    t.identity = "backrooms_survivor"
    t.version = "11.4"
    t.window.width = 960
    t.window.height = 720
    t.window.resizable = true
    t.window.vsync = 1
    t.window.minwidth = 640
    t.window.minheight = 480
    t.window.highdpi = false    -- disable DPI scaling so coords = pixels
    t.modules.joystick = true
    t.modules.audio = true
end
