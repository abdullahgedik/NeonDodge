function love.conf(t)
    t.window.title = "Neon Dodge"
    -- The window is only a viewport now: the game itself is always drawn at
    -- Screen.WIDTH x Screen.HEIGHT (960x540) and scaled up to fit whatever
    -- size this is, so these are a comfort default rather than a constraint.
    -- Kept at 16:9 to match the game's own ratio, so a fresh window has no
    -- letterbox bars at all -- 1024x576 is a 1.07x view: readable on a 1440p
    -- display where the original 960x540 was tiny, while still leaving the
    -- title bar reachable on a 1080p one (1200x900 ate almost the full
    -- vertical height there, with no way to grab the bar to resize/move it).
    t.window.width = 1024
    t.window.height = 576
    t.window.resizable = true
    -- below this the HUD text stops being legible; the scaling itself would
    -- happily go smaller
    t.window.minwidth = 640
    t.window.minheight = 360
    -- VSync açık olsun ki iş bilgisayarında ekran kartını gereksiz yormasın
    t.window.vsync = 1
end
