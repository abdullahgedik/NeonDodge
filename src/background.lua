local Screen = require("src/screen")

local Background = {}

function Background.load()
    Background.stars = {}
    Background.max_stars = 40

    for i = 1, Background.max_stars do
        table.insert(Background.stars, {
            x = love.math.random(0, Screen.WIDTH),
            y = love.math.random(0, Screen.HEIGHT),
            length = love.math.random(12, 38),
            speed = love.math.random(90, 260),
            width = love.math.random(1, 2),
            alpha = love.math.random(1, 2) / 10
        })
    end
end

function Background.update(dt)
    for _, s in ipairs(Background.stars) do
        s.y = s.y + s.speed * dt

        if s.y > Screen.HEIGHT then
            s.y = -s.length
            s.x = love.math.random(0, Screen.WIDTH)
        end
    end
end

function Background.draw()
    -- a filled rect over the play area, NOT love.graphics.clear: clear ignores
    -- the current transform and would paint the whole canvas, which is now the
    -- whole window -- flooding the letterbox bars with this color instead of
    -- leaving them the black that reads as a frame around the game
    love.graphics.setColor(0.05, 0.05, 0.1)
    love.graphics.rectangle("fill", 0, 0, Screen.WIDTH, Screen.HEIGHT)

    for _, s in ipairs(Background.stars) do
        love.graphics.setColor(1, 1, 1, s.alpha)
        love.graphics.setLineWidth(s.width)
        love.graphics.line(s.x, s.y, s.x, s.y + s.length)
    end

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
end

function Background.reset()
    for _, s in ipairs(Background.stars) do
        s.y = love.math.random(0, Screen.HEIGHT)
        s.x = love.math.random(0, Screen.WIDTH)
    end
end

return Background
