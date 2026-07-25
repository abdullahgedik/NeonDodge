local Pool = require("src/pool")
local Cards = require("src/cards")
local FXManager = require("src/fx_manager")
local Collision = require("src/collision")
local Screen = require("src/screen")

local VoidOrb = {}

function VoidOrb.load()
    VoidOrb.pool = Pool.new(function() return {} end)
    VoidOrb.speed = 200
    VoidOrb.spawn_timer = 0
    VoidOrb.radius = 14
    VoidOrb.is_paused = false
end

function VoidOrb.update(dt, game_over, player, on_collision, on_miss, spawn_rate)
    if game_over or VoidOrb.is_paused then return end

    VoidOrb.spawn(dt, spawn_rate)
    VoidOrb.move_and_process(dt, player, on_collision, on_miss)
end

function VoidOrb.draw()
    for _, o in ipairs(VoidOrb.pool.active) do
        love.graphics.setColor(0.6, 0, 1, 0.4)
        love.graphics.circle("fill", o.x, o.y, o.radius + 4)
        love.graphics.setColor(0.7, 0.2, 1)
        love.graphics.circle("fill", o.x, o.y, o.radius)
    end
end

function VoidOrb.spawn(dt, spawn_rate)
    VoidOrb.spawn_timer = VoidOrb.spawn_timer + dt
    if VoidOrb.spawn_timer > spawn_rate then
        VoidOrb.spawn_timer = 0
        local random_x = love.math.random(VoidOrb.radius, Screen.WIDTH - VoidOrb.radius)
        VoidOrb.pool:spawn(function(o)
            o.x = random_x
            o.y = -20
            o.radius = VoidOrb.radius
        end)
    end
end

function VoidOrb.move_and_process(dt, player, on_collision, on_miss)
    local active = VoidOrb.pool.active

    for i = #active, 1, -1 do
        local o = active[i]
        -- missing one costs HP just like touching a hazard does, so "Slow
        -- Fall" eases it the same way it eases Enemy/ZigzagEnemy (unlike
        -- Orb, a pure pickup with no downside, which stays unaffected)
        o.y = o.y + VoidOrb.speed * Cards.get("hazard_speed_mult", 1) * dt

        -- catching one is the reward, so this uses the plain overlap test --
        -- dashing through it still collects it (only *missing* one hurts)
        if Collision.circle_overlaps_player(player, o.x, o.y, o.radius) then
            FXManager.spawn_ring(o.x, o.y, 0.7, 0.2, 1, 14, 80, 200)

            on_collision(i)
            goto continue
        end

        if o.y > Screen.HEIGHT + o.radius then
            FXManager.spawn("void_explosion", o.x, Screen.HEIGHT - 5, 45)
            on_miss(i)
            goto continue
        end

        ::continue::
    end
end

function VoidOrb.remove(index)
    VoidOrb.pool:release(index)
end

function VoidOrb.pause() VoidOrb.is_paused = true end

function VoidOrb.resume() VoidOrb.is_paused = false end

function VoidOrb.reset()
    VoidOrb.pool:clear()
    VoidOrb.spawn_timer = 0
end

return VoidOrb
