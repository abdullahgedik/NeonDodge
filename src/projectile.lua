local Pool = require("src/pool")

local Projectile = {}

function Projectile.load()
    Projectile.pool = Pool.new(function() return {} end)
    Projectile.speed = 260
    Projectile.radius = 8
    Projectile.is_paused = false
end

function Projectile.update(dt, game_over, player, on_collision)
    if game_over or Projectile.is_paused then return end
    Projectile.move_and_process(dt, player, on_collision)
end

function Projectile.draw()
    love.graphics.setColor(1, 0.2, 0.6)
    for _, p in ipairs(Projectile.pool.active) do
        love.graphics.circle("fill", p.x, p.y, p.radius)
    end
end

function Projectile.spawn(x, y, dir_x, dir_y)
    Projectile.pool:spawn(function(p)
        p.x = x
        p.y = y
        p.dir_x = dir_x
        p.dir_y = dir_y
        p.radius = Projectile.radius
    end)
end

function Projectile.move_and_process(dt, player, on_collision)
    local active = Projectile.pool.active
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()

    for i = #active, 1, -1 do
        local p = active[i]
        p.x = p.x + p.dir_x * Projectile.speed * dt
        p.y = p.y + p.dir_y * Projectile.speed * dt

        local player_cx = player.x + player.size / 2
        local player_cy = player.y + player.size / 2
        local distance = math.sqrt((player_cx - p.x) ^ 2 + (player_cy - p.y) ^ 2)

        if distance < (player.size / 2 + p.radius) then
            on_collision(i)
            goto continue
        end

        if p.y > h + p.radius or p.y < -p.radius or p.x < -p.radius or p.x > w + p.radius then
            Projectile.remove(i)
        end

        ::continue::
    end
end

function Projectile.remove(index)
    Projectile.pool:release(index)
end

function Projectile.pause() Projectile.is_paused = true end

function Projectile.resume() Projectile.is_paused = false end

function Projectile.reset()
    Projectile.pool:clear()
end

return Projectile
