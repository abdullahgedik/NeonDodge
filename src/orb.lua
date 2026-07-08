local Orb = {}

function Orb.load()
    Orb.list = {}
    Orb.speed = 175
    Orb.spawn_timer = 0
    Orb.radius = 12
    Orb.is_paused = false
end

function Orb.update(dt, game_over, player, on_collision, spawn_rate)
    if game_over then return end

    if Orb.is_paused then return end

    Orb.spawn(dt, spawn_rate)
    Orb.move_and_process(dt, player, on_collision)
end

function Orb.draw()
    love.graphics.setColor(1, 0.9, 0.2)
    for _, o in ipairs(Orb.list) do
        love.graphics.circle("fill", o.x, o.y, o.radius)
    end
end

function Orb.spawn(dt, spawn_rate)
    Orb.spawn_timer = Orb.spawn_timer + dt
    if Orb.spawn_timer > spawn_rate then
        Orb.spawn_timer = 0
        local random_x = love.math.random(Orb.radius, love.graphics.getWidth() - Orb.radius)
        table.insert(Orb.list, { x = random_x, y = -20, radius = Orb.radius })
    end
end

function Orb.move_and_process(dt, player, on_collision)
    local FXManager = require("src/fx_manager")

    for i = #Orb.list, 1, -1 do
        local o = Orb.list[i]
        o.y = o.y + Orb.speed * dt

        local player_cx = player.x + player.size / 2
        local player_cy = player.y + player.size / 2
        local distance = math.sqrt((player_cx - o.x) ^ 2 + (player_cy - o.y) ^ 2)

        if distance < (player.size / 2 + o.radius) then
            FXManager.spawn_ring(o.x, o.y, 1, 0.9, 0.2, 12, 65, 180)

            on_collision(i)
            goto continue
        end

        if o.y > love.graphics.getHeight() + o.radius then
            table.remove(Orb.list, i)
        end

        ::continue::
    end
end

function Orb.remove(index)
    table.remove(Orb.list, index)
end

function Orb.pause()
    Orb.is_paused = true
end

function Orb.resume()
    Orb.is_paused = false
end

function Orb.reset()
    Orb.list = {}
    Orb.speed = 175
    Orb.spawn_timer = 0
end

return Orb
