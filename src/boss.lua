local Boss = {}

local WIDTH, HEIGHT       = 90, 60
local ENTER_SPEED         = 120
local HOVER_Y             = 90
local PATROL_AMPLITUDE    = 240
local PATROL_SPEED        = 0.8
local ENCOUNTER_DURATION  = 14
local EXIT_SPEED          = 160
local FIRE_INTERVAL       = 1.4
local FIRE_COUNT          = 5
local FIRE_SPREAD_ANGLE   = math.rad(50)
local HIT_COOLDOWN        = 0.6

function Boss.load()
    Boss.active = false
    Boss.is_paused = false
end

function Boss.spawn()
    local width = love.graphics.getWidth()

    Boss.active = true
    Boss.phase = "enter"
    Boss.base_x = width / 2 - WIDTH / 2
    Boss.x = Boss.base_x
    Boss.y = -HEIGHT
    Boss.age = 0
    Boss.hover_timer = 0
    Boss.fire_timer = 0
    Boss.hit_cooldown = 0
end

function Boss.update(dt, game_over, player, on_player_hit, spawn_projectile, on_encounter_end)
    if not Boss.active or game_over or Boss.is_paused then return end

    Boss.age = Boss.age + dt
    if Boss.hit_cooldown > 0 then
        Boss.hit_cooldown = Boss.hit_cooldown - dt
    end

    if Boss.phase == "enter" then
        Boss.y = Boss.y + ENTER_SPEED * dt
        if Boss.y >= HOVER_Y then
            Boss.y = HOVER_Y
            Boss.phase = "hover"
            Boss.age = 0
            Boss.fire_timer = 0
        end
    elseif Boss.phase == "hover" then
        Boss.hover_timer = Boss.hover_timer + dt
        Boss.x = Boss.base_x + math.sin(Boss.age * PATROL_SPEED) * PATROL_AMPLITUDE

        Boss.fire_timer = Boss.fire_timer + dt
        if Boss.fire_timer >= FIRE_INTERVAL then
            Boss.fire_timer = 0
            Boss.fire_spread(spawn_projectile)
        end

        if Boss.hover_timer >= ENCOUNTER_DURATION then
            Boss.phase = "exit"
        end
    elseif Boss.phase == "exit" then
        Boss.y = Boss.y - EXIT_SPEED * dt
        if Boss.y < -HEIGHT then
            Boss.active = false
            if on_encounter_end then on_encounter_end() end
            return
        end
    end

    local width = love.graphics.getWidth()
    if Boss.x < 0 then Boss.x = 0 end
    if Boss.x > width - WIDTH then Boss.x = width - WIDTH end

    Boss.check_player_collision(player, on_player_hit)
end

function Boss.fire_spread(spawn_projectile)
    local FXManager = require("src/fx_manager")
    local cx = Boss.x + WIDTH / 2
    local cy = Boss.y + HEIGHT

    for i = 1, FIRE_COUNT do
        local t = (i - 1) / (FIRE_COUNT - 1)
        local angle = -FIRE_SPREAD_ANGLE + t * (2 * FIRE_SPREAD_ANGLE)
        spawn_projectile(cx, cy, math.sin(angle), math.cos(angle))
    end

    FXManager.spawn_ring(cx, cy, 1, 0.2, 0.6, 10, 55, 220)
end

function Boss.check_player_collision(player, on_player_hit)
    if Boss.hit_cooldown > 0 then return end

    local padding = WIDTH * 0.15

    if player.x < (Boss.x + WIDTH - padding) and (Boss.x + padding) < player.x + player.size and
        player.y < Boss.y + HEIGHT and Boss.y < player.y + player.size then
        Boss.hit_cooldown = HIT_COOLDOWN
        on_player_hit()
    end
end

function Boss.draw()
    if not Boss.active then return end

    love.graphics.setColor(1, 0.1, 0.6)
    love.graphics.rectangle("fill", Boss.x, Boss.y, WIDTH, HEIGHT, 10, 10)

    love.graphics.setColor(1, 0.6, 0.85)
    love.graphics.rectangle("fill", Boss.x + 15, Boss.y + 15, WIDTH - 30, HEIGHT - 30, 6, 6)
end

function Boss.pause() Boss.is_paused = true end

function Boss.resume() Boss.is_paused = false end

function Boss.reset()
    Boss.active = false
end

return Boss
