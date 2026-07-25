local Screen = {}

-- The game is authored at a fixed 800x600 and stays that way forever: every
-- spawn bound, boss patrol amplitude, arena wall, blast radius and HUD
-- position in the project is tuned against these two numbers. The *window* is
-- a separate thing entirely -- it can be any size the user drags it to, and
-- love.draw scales the finished 800x600 frame up to fit, letterboxing to
-- preserve the 4:3 aspect ratio so nothing ever stretches or misaligns.
--
-- The rule that keeps this honest: game logic asks Screen for its dimensions,
-- never love.graphics. The only place that should call
-- love.graphics.getWidth/getHeight is this file -- and note it's asking a
-- genuinely different question there ("how big is the window?") than every
-- call site it replaced was ("how big is the play area?"). Those two used to
-- be the same number, which is exactly why they were easy to conflate.
Screen.WIDTH     = 800
Screen.HEIGHT    = 600

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
