local Pool = require("src/pool")
local Cards = require("src/cards")
local FXManager = require("src/fx_manager")
local Collision = require("src/collision")
local Screen = require("src/screen")

local ZigzagEnemy = {}

-- shared by load() and reset() so a run always starts at the same speed
local BASE_SPEED = 158
local COLLISION_PADDING_RATIO = 0.2

function ZigzagEnemy.load()
    ZigzagEnemy.pool = Pool.new(function() return {} end)
    ZigzagEnemy.speed = BASE_SPEED
    ZigzagEnemy.max_speed = 270
    ZigzagEnemy.spawn_timer = 0
    ZigzagEnemy.size = 28
    ZigzagEnemy.amplitude = 96
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
        local max_x = Screen.WIDTH - ZigzagEnemy.size - amplitude
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
    local active = ZigzagEnemy.pool.active

    for i = #active, 1, -1 do
        local e = active[i]
        e.age = e.age + dt
        e.y = e.y + ZigzagEnemy.speed * Cards.get("hazard_speed_mult", 1) * dt
        e.x = e.base_x + math.sin(e.age * e.frequency + e.phase) * ZigzagEnemy.amplitude

        if Collision.hazard_rect_hits_player(player, e.x, e.y, e.size, e.size, e.size * COLLISION_PADDING_RATIO) then
            FXManager.spawn("zigzag_explosion", e.x + e.size / 2, e.y + e.size / 2, 30)

            on_collision(i)
            goto continue
        end

        if e.y > Screen.HEIGHT then
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
    ZigzagEnemy.speed = BASE_SPEED
    ZigzagEnemy.spawn_timer = 0
end

return ZigzagEnemy
