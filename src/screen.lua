local Screen = {}

-- The game is authored at a fixed 960x540 (16:9) and stays that way forever:
-- every spawn bound, boss patrol amplitude, arena wall, blast radius and HUD
-- position in the project is tuned against these two numbers. The *window* is
-- a separate thing entirely -- it can be any size the user drags it to, and
-- love.draw scales the finished 960x540 frame up to fit, letterboxing to
-- preserve the 16:9 aspect ratio so nothing ever stretches or misaligns.
--
-- The rule that keeps this honest: game logic asks Screen for its dimensions,
-- never love.graphics. The only place that should call
-- love.graphics.getWidth/getHeight is this file -- and note it's asking a
-- genuinely different question there ("how big is the window?") than every
-- call site it replaced was ("how big is the play area?"). Those two used to
-- be the same number, which is exactly why they were easy to conflate.
Screen.WIDTH     = 960
Screen.HEIGHT    = 540

-- window -> game transform, recomputed on load and on every resize
Screen.scale     = 1
Screen.offset_x  = 0
Screen.offset_y  = 0

function Screen.load()
    Screen.update_scale()
end

function Screen.update_scale()
    local win_w, win_h = love.graphics.getDimensions()

    -- one uniform scale, the largest that fits both axes -- scaling each axis
    -- independently would fill the window but stretch the game out of shape
    Screen.scale = math.min(win_w / Screen.WIDTH, win_h / Screen.HEIGHT)

    -- center the result, so whatever space is left over becomes even bars on
    -- either the sides or the top/bottom rather than a lopsided margin
    Screen.offset_x = (win_w - Screen.WIDTH * Screen.scale) / 2
    Screen.offset_y = (win_h - Screen.HEIGHT * Screen.scale) / 2
end

-- The actual window size, as distinct from the game's fixed play area. Only
-- code that genuinely rasterizes per-pixel needs this -- Bloom's canvases and
-- font sizes below. Gameplay logic wants WIDTH/HEIGHT and nothing else.
function Screen.window_size()
    return love.graphics.getDimensions()
end

-- Fonts are the one thing the scale transform can't make crisp on its own:
-- a glyph is rasterized once at a fixed pixel size, so a 24pt font drawn
-- under a 2.4x transform is a 24px bitmap stretched -- exactly the blur that
-- rendering everything else at native resolution removes. Build fonts at the
-- size they'll actually occupy on screen instead, then counter-scale when
-- drawing (Screen.print/printf below) so call sites still position text in
-- game coordinates and layout code never has to know any of this happened.
function Screen.new_font(game_size)
    return love.graphics.newFont(math.max(1, math.floor(game_size * Screen.scale + 0.5)))
end

-- print/printf in game coordinates using a font built by Screen.new_font.
-- The 1/scale counter-scale exactly undoes the outer transform, so the glyphs
-- land on screen at their true pixel size -- rasterized, not resampled.
function Screen.print(text, x, y)
    local inv = 1 / Screen.scale
    love.graphics.print(text, x, y, 0, inv, inv)
end

function Screen.printf(text, x, y, limit, align)
    local inv = 1 / Screen.scale
    -- the wrap limit is given in game units but applies pre-counter-scale
    love.graphics.printf(text, x, y, limit * Screen.scale, align, 0, inv, inv)
end

-- measurements come back in game units, so centering math stays unchanged.
-- Consistent with what Screen.print actually draws even though new_font
-- rounds to a whole pixel size, since both divide by the same scale.
function Screen.text_width(font, text)
    return font:getWidth(text) / Screen.scale
end

-- horizontally centered text at a given y. "measure it, subtract from the
-- screen width, halve, print" was written out at 17 separate places in
-- ui.lua, which buried what each line was actually saying under the same
-- three lines of arithmetic every time.
function Screen.print_centered(font, text, y)
    Screen.print(text, (Screen.WIDTH - Screen.text_width(font, text)) / 2, y)
end

function Screen.text_height(font)
    return font:getHeight() / Screen.scale
end

-- wraps everything drawn in game coordinates (see love.draw)
function Screen.push()
    love.graphics.push()
    love.graphics.translate(Screen.offset_x, Screen.offset_y)
    love.graphics.scale(Screen.scale, Screen.scale)
end

function Screen.pop()
    love.graphics.pop()
end

-- window coordinates (as love.mousepressed reports them) -> game coordinates.
-- Without this, every menu and card click would be off by the letterbox
-- offset and wrong by the scale factor the moment the window isn't 800x600.
function Screen.to_game(x, y)
    return (x - Screen.offset_x) / Screen.scale, (y - Screen.offset_y) / Screen.scale
end

function Screen.toggle_fullscreen()
    love.window.setFullscreen(not love.window.getFullscreen(), "desktop")
    -- love.resize normally fires and handles this, but recomputing here too
    -- means the very next frame is correct regardless of event ordering
    Screen.update_scale()
end

return Screen
