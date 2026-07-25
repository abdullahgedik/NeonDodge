local Pool               = require("src/pool")
local Cards              = require("src/cards")

local Mine               = {}

-- unlike every other hazard, the body itself is harmless -- only the
-- shockwave at the end of the telegraph deals damage, so this is a "read
-- the danger zone and be clear of it by the deadline" hazard rather than a
-- "dodge the moving shape" one
local TELEGRAPH_DURATION = 1.3
local BLAST_RADIUS       = 90
local ANCHOR_MIN_Y       = 150
local ANCHOR_MAX_Y       = 420

local function octagon_points(cx, cy, radius)
    local points = {}
    for i = 1, 8 do
        local angle = (i - 1) / 8 * math.pi * 2 + math.pi / 8
        table.insert(points, cx + math.cos(angle) * radius)
        table.insert(points, cy + math.sin(angle) * radius)
    end
    return points
end

function Mine.load()
    Mine.pool = Pool.new(function() return {} end)
    Mine.fall_speed = 90
    Mine.size = 26
    Mine.spawn_timer = 0
    Mine.is_paused = false
end

function Mine.update(dt, game_over, player, on_collision, spawn_rate)
    if game_over or Mine.is_paused then return end

    Mine.spawn(dt, spawn_rate)
    Mine.move_and_process(dt, player, on_collision)
end

function Mine.draw()
    for _, m in ipairs(Mine.pool.active) do
        local core_r, core_g, core_b = 0.68, 0.5, 0.28

        if m.phase == "armed" then
            local t = m.arm_timer / TELEGRAPH_DURATION

            -- warning ring shows the blast radius from the moment it arms,
            -- growing more solid as the deadline approaches
            love.graphics.setLineWidth(3)
            love.graphics.setColor(1, 0.25, 0.05, 0.2 + 0.5 * t)
            love.graphics.circle("line", m.x, m.y, BLAST_RADIUS)
            love.graphics.setLineWidth(1)

            -- core flashes toward hot orange-red, faster as t -> 1 (a
            -- "beeping faster" telegraph cue)
            local flash = math.abs(math.sin(t * math.pi * (2 + t * 8)))
            core_r = core_r + (1 - core_r) * flash * t
            core_g = core_g + (0.15 - core_g) * flash * t
            core_b = core_b + (0.05 - core_b) * flash * t
        end

        love.graphics.setLineWidth(2)
        love.graphics.setColor(0.2, 0.12, 0.05, 0.9)
        love.graphics.polygon("line", octagon_points(m.x, m.y, m.size))
        love.graphics.setLineWidth(1)

        love.graphics.setColor(0.45, 0.32, 0.15)
        love.graphics.polygon("fill", octagon_points(m.x, m.y, m.size))

        love.graphics.setColor(core_r, core_g, core_b)
        love.graphics.polygon("fill", octagon_points(m.x, m.y, m.size * 0.5))
    end

    love.graphics.setColor(1, 1, 1, 1)
end

function Mine.spawn(dt, spawn_rate)
    Mine.spawn_timer = Mine.spawn_timer + dt
    if Mine.spawn_timer > spawn_rate then
        Mine.spawn_timer = 0
        local random_x = love.math.random(Mine.size, love.graphics.getWidth() - Mine.size)
        local anchor_y = love.math.random(ANCHOR_MIN_Y, ANCHOR_MAX_Y)

        Mine.pool:spawn(function(m)
            m.x = random_x
            m.y = -Mine.size
            m.size = Mine.size
            m.anchor_y = anchor_y
            m.phase = "falling"
            m.arm_timer = 0
        end)
    end
end

function Mine.move_and_process(dt, player, on_collision)
    local FXManager = require("src/fx_manager")
    local active = Mine.pool.active

    for i = #active, 1, -1 do
        local m = active[i]

        if m.phase == "falling" then
            m.y = m.y + Mine.fall_speed * Cards.get("hazard_speed_mult", 1) * dt
            if m.y >= m.anchor_y then
                m.y = m.anchor_y
                m.phase = "armed"
            end
        elseif m.phase == "armed" then
            m.arm_timer = m.arm_timer + dt

            if m.arm_timer >= TELEGRAPH_DURATION then
                local player_cx = player.x + player.size / 2
                local player_cy = player.y + player.size / 2
                local distance = math.sqrt((player_cx - m.x) ^ 2 + (player_cy - m.y) ^ 2)

                FXManager.spawn("mine_explosion", m.x, m.y, 45)
                FXManager.spawn_ring(m.x, m.y, 1, 0.4, 0.1, 20, BLAST_RADIUS + 20, 260)

                if not player.is_dashing and distance < (BLAST_RADIUS + player.size / 2) then
                    on_collision(i)
                else
                    Mine.remove(i)
                end
            end
        end
    end
end

function Mine.remove(index)
    Mine.pool:release(index)
end

function Mine.pause() Mine.is_paused = true end

function Mine.resume() Mine.is_paused = false end

function Mine.reset()
    Mine.pool:clear()
    Mine.spawn_timer = 0
end

return Mine
