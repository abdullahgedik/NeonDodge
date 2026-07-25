local Pool = require("src/pool")
local FXManager = require("src/fx_manager")
local Collision = require("src/collision")
local Screen = require("src/screen")

local Projectile = {}

-- A homing shot that runs out its lifetime detonates instead of just
-- vanishing, which turns the homing boss from "outrun the chasers" into
-- "outrun them AND don't be where they die". Deliberately smaller than a
-- Mine's 90 (that one is the dedicated zone-denial hazard and should stay the
-- biggest), and telegraphed by a ring over the last stretch of its life for
-- the same reason a Mine telegraphs: a blast with no warning isn't a dodge,
-- it's a coin flip.
local HOMING_BLAST_RADIUS   = 52
local HOMING_BLAST_WARNING  = 1.0

-- math.atan2 works on LOVE's LuaJIT runtime but is deprecated/removed in
-- standard Lua 5.3+, and it's unclear whether a two-arg math.atan(y, x) is
-- safe to assume either -- so build atan2 from single-arg math.atan, which
-- is guaranteed correct on every Lua version.
local function atan2(y, x)
    if x > 0 then
        return math.atan(y / x)
    elseif x < 0 then
        if y >= 0 then
            return math.atan(y / x) + math.pi
        else
            return math.atan(y / x) - math.pi
        end
    elseif y > 0 then
        return math.pi / 2
    elseif y < 0 then
        return -math.pi / 2
    else
        return 0
    end
end

local function steer_towards(dir_x, dir_y, to_x, to_y, max_turn)
    local cur_angle = atan2(dir_y, dir_x)
    local target_angle = atan2(to_y, to_x)

    local diff = target_angle - cur_angle
    while diff > math.pi do diff = diff - 2 * math.pi end
    while diff < -math.pi do diff = diff + 2 * math.pi end

    if diff > max_turn then diff = max_turn end
    if diff < -max_turn then diff = -max_turn end

    local new_angle = cur_angle + diff
    return math.cos(new_angle), math.sin(new_angle)
end

function Projectile.load()
    Projectile.pool = Pool.new(function() return {} end)
    Projectile.speed = 260
    Projectile.homing_speed = 180
    Projectile.homing_turn_rate = 2.2
    Projectile.homing_lifetime = 6
    Projectile.radius = 8
    Projectile.is_paused = false
end

function Projectile.update(dt, game_over, player, on_collision)
    if game_over or Projectile.is_paused then return end
    Projectile.move_and_process(dt, player, on_collision)
end

function Projectile.draw()
    for _, p in ipairs(Projectile.pool.active) do
        if p.homing then
            -- warning ring over the last HOMING_BLAST_WARNING seconds of its
            -- life, growing more solid as the detonation approaches -- the
            -- same telegraph language the Mine already taught the player
            local remaining = Projectile.homing_lifetime - p.age
            if remaining <= HOMING_BLAST_WARNING then
                local t = 1 - remaining / HOMING_BLAST_WARNING
                love.graphics.setLineWidth(2)
                love.graphics.setColor(0.3, 1, 0.5, 0.15 + 0.5 * t)
                love.graphics.circle("line", p.x, p.y, HOMING_BLAST_RADIUS)
                love.graphics.setLineWidth(1)
            end

            love.graphics.setColor(0.15, 0.9, 0.45)
        else
            love.graphics.setColor(1, 0.2, 0.6)
        end
        love.graphics.circle("fill", p.x, p.y, p.radius)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

function Projectile.spawn(x, y, dir_x, dir_y, homing)
    Projectile.pool:spawn(function(p)
        p.x = x
        p.y = y
        p.dir_x = dir_x
        p.dir_y = dir_y
        p.radius = Projectile.radius
        p.homing = homing or false
        p.age = 0
    end)
end

function Projectile.move_and_process(dt, player, on_collision)
    local active = Projectile.pool.active
    local w, h = Screen.WIDTH, Screen.HEIGHT

    for i = #active, 1, -1 do
        local p = active[i]

        local player_cx, player_cy = player.center()

        local speed = Projectile.speed
        if p.homing then
            speed = Projectile.homing_speed
            p.age = p.age + dt
            if p.age >= Projectile.homing_lifetime then
                FXManager.spawn("homing_expire", p.x, p.y, 30)
                FXManager.spawn_ring(p.x, p.y, 0.2, 1, 0.5, 14, HOMING_BLAST_RADIUS + 18, 240)

                -- same shape as Mine's detonation: the blast happens either
                -- way, and only a player still inside it (and not dashing)
                -- takes the hit -- the caller removes it in that case, so it
                -- isn't released twice
                if Collision.hazard_circle_hits_player(player, p.x, p.y, HOMING_BLAST_RADIUS) then
                    on_collision(i)
                else
                    Projectile.remove(i)
                end
                goto continue
            end
            p.dir_x, p.dir_y = steer_towards(p.dir_x, p.dir_y, player_cx - p.x, player_cy - p.y,
                Projectile.homing_turn_rate * dt)
        end

        p.x = p.x + p.dir_x * speed * dt
        p.y = p.y + p.dir_y * speed * dt

        if Collision.hazard_circle_hits_player(player, p.x, p.y, p.radius) then
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

-- called when the homing boss leaves, so its shots don't keep chasing the
-- player around the arena after the threat that fired them is already gone.
-- Deliberately does NOT detonate them the way running out of lifetime does:
-- the encounter is over at this point, and killing the player with the debris
-- of a boss that already left is exactly the "threat outliving the boss"
-- problem this function exists to solve.
function Projectile.clear_homing()
    local active = Projectile.pool.active

    for i = #active, 1, -1 do
        local p = active[i]
        if p.homing then
            FXManager.spawn("homing_expire", p.x, p.y, 20)
            Projectile.remove(i)
        end
    end
end

function Projectile.pause() Projectile.is_paused = true end

function Projectile.resume() Projectile.is_paused = false end

function Projectile.reset()
    Projectile.pool:clear()
end

return Projectile
