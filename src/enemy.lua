local Pool = require("src/pool")
local Cards = require("src/cards")
local FXManager = require("src/fx_manager")
local Collision = require("src/collision")
local Screen = require("src/screen")

local Enemy = {}

-- the speed a run starts at, before the per-miss ramp -- named so load() and
-- reset() can't drift to different values
local BASE_SPEED = 225
-- fraction of the width shaved off each side of the hitbox, so a near-miss
-- along the edge reads as a miss
local COLLISION_PADDING_RATIO = 0.2

function Enemy.load()
    Enemy.pool = Pool.new(function() return {} end)
    Enemy.speed = BASE_SPEED
    Enemy.max_speed = 375
    Enemy.spawn_timer = 0
    Enemy.size = 30
    Enemy.is_paused = false
end

function Enemy.update(dt, game_over, player, on_collision, spawn_rate)
    if game_over then return end
    if Enemy.is_paused then return end

    Enemy.spawn(dt, spawn_rate)
    Enemy.move_and_process(dt, player, on_collision)
end

function Enemy.draw()
    love.graphics.setColor(1, 0, 0.2)
    for _, e in ipairs(Enemy.pool.active) do
        love.graphics.polygon("fill",
            e.x, e.y,
            e.x + e.size, e.y,
            e.x + e.size / 2, e.y + e.size
        )
    end
end

function Enemy.spawn(dt, spawn_rate)
    Enemy.spawn_timer = Enemy.spawn_timer + dt
    if Enemy.spawn_timer > spawn_rate then
        Enemy.spawn_timer = 0
        local random_x = love.math.random(0, Screen.WIDTH - Enemy.size)
        Enemy.pool:spawn(function(e)
            e.x = random_x
            e.y = -25
            e.size = Enemy.size
        end)
    end
end

function Enemy.move_and_process(dt, player, on_collision)
    local active = Enemy.pool.active

    for i = #active, 1, -1 do
        local e = active[i]
        e.y = e.y + Enemy.speed * Cards.get("hazard_speed_mult", 1) * dt

        if Collision.hazard_rect_hits_player(player, e.x, e.y, e.size, e.size, e.size * COLLISION_PADDING_RATIO) then
            FXManager.spawn("enemy_explosion", e.x + e.size / 2, e.y + e.size / 2, 30)

            on_collision(i)
            goto continue
        end

        if e.y > Screen.HEIGHT then
            Enemy.remove(i)
            Enemy.speed = math.min(Enemy.speed + 5 * Cards.get("enemy_ramp_mult", 1), Enemy.max_speed)
        end

        ::continue::
    end
end

function Enemy.remove(index)
    Enemy.pool:release(index)
end

function Enemy.pause() Enemy.is_paused = true end

function Enemy.resume() Enemy.is_paused = false end

function Enemy.reset()
    Enemy.pool:clear()
    Enemy.speed = BASE_SPEED
    Enemy.spawn_timer = 0
end

return Enemy
