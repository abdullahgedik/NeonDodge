local Pool = require("src/pool")
local Cards = require("src/cards")

local ZigzagEnemy = {}

function ZigzagEnemy.load()
    ZigzagEnemy.pool = Pool.new(function() return {} end)
    ZigzagEnemy.speed = 175
    ZigzagEnemy.max_speed = 300
    ZigzagEnemy.spawn_timer = 0
    ZigzagEnemy.size = 28
    ZigzagEnemy.amplitude = 80
    ZigzagEnemy.is_paused = false
end

function ZigzagEnemy.update(dt, game_over, player, on_collision, spawn_rate)
    if game_over then return end
    if ZigzagEnemy.is_paused then return end

    ZigzagEnemy.spawn(dt, spawn_rate)
    ZigzagEnemy.move_and_process(dt, player, on_collision)
end

function ZigzagEnemy.draw()
    for _, e in ipairs(ZigzagEnemy.pool.active) do
        local points = {
            e.x + e.size / 2, e.y,
            e.x + e.size, e.y + e.size / 2,
            e.x + e.size / 2, e.y + e.size,
            e.x, e.y + e.size / 2
        }

        love.graphics.setColor(1, 0.4, 0.05)
        love.graphics.polygon("fill", points)

        love.graphics.setColor(0.7, 0, 0, 0.9)
        love.graphics.setLineWidth(2)
        love.graphics.polygon("line", points)
        love.graphics.setLineWidth(1)
    end
end

function ZigzagEnemy.spawn(dt, spawn_rate)
    ZigzagEnemy.spawn_timer = ZigzagEnemy.spawn_timer + dt
    if ZigzagEnemy.spawn_timer > spawn_rate then
        ZigzagEnemy.spawn_timer = 0

        local amplitude = ZigzagEnemy.amplitude
        local min_x = amplitude
        local max_x = love.graphics.getWidth() - ZigzagEnemy.size - amplitude
        local base_x = love.math.random(min_x, max_x)

        ZigzagEnemy.pool:spawn(function(e)
            e.base_x = base_x
            e.x = base_x
            e.y = -ZigzagEnemy.size
            e.size = ZigzagEnemy.size
            e.age = 0
            e.frequency = love.math.random(150, 250) / 100
            e.phase = love.math.random() * math.pi * 2
        end)
    end
end

function ZigzagEnemy.move_and_process(dt, player, on_collision)
    local FXManager = require("src/fx_manager")
    local active = ZigzagEnemy.pool.active

    for i = #active, 1, -1 do
        local e = active[i]
        e.age = e.age + dt
        e.y = e.y + ZigzagEnemy.speed * Cards.get("hazard_speed_mult", 1) * dt
        e.x = e.base_x + math.sin(e.age * e.frequency + e.phase) * ZigzagEnemy.amplitude

        local padding = e.size * 0.2

        if not player.is_dashing and player.x < (e.x + e.size - padding) and (e.x + padding) < player.x + player.size and
            player.y < e.y + e.size and e.y < player.y + player.size then
            FXManager.spawn("zigzag_explosion", e.x + e.size / 2, e.y + e.size / 2, 30)

            on_collision(i)
            goto continue
        end

        if e.y > love.graphics.getHeight() then
            ZigzagEnemy.remove(i)
            ZigzagEnemy.speed = math.min(ZigzagEnemy.speed + 5 * Cards.get("enemy_ramp_mult", 1), ZigzagEnemy.max_speed)
        end

        ::continue::
    end
end

function ZigzagEnemy.remove(index)
    ZigzagEnemy.pool:release(index)
end

function ZigzagEnemy.pause() ZigzagEnemy.is_paused = true end

function ZigzagEnemy.resume() ZigzagEnemy.is_paused = false end

function ZigzagEnemy.reset()
    ZigzagEnemy.pool:clear()
    ZigzagEnemy.speed = 175
    ZigzagEnemy.spawn_timer = 0
end

return ZigzagEnemy
