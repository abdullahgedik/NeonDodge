local Boss                     = {}

local ENTER_SPEED              = 120
local HOVER_Y                  = 90
local EXIT_SPEED               = 160
local HIT_COOLDOWN             = 0.6
local ENCOUNTER_DURATION       = 14
local COLLISION_PADDING_RATIO  = 0.15

-- laser timing/geometry (only the "laser" type uses these) -- a full-width or
-- full-height band that sweeps edge-to-edge across the WHOLE screen each cycle
-- (horizontal band top<->bottom, or vertical band left<->right, picked randomly),
-- so no row/column and no direction is ever permanently safe
local LASER_TELEGRAPH_DURATION = 0.9
local LASER_FIRE_DURATION      = 2.8
local LASER_COOLDOWN_DURATION  = 1.0
local LASER_THICKNESS          = 18
local LASER_EDGE_MARGIN        = 30 -- keep the sweep just inside the absolute screen edges
local LASER_SHOT_INTERVAL      = 1.0 -- independent of the beam cycle, fires more often
local LASER_MAX_SWEEPS         = 4   -- the encounter ends once exactly this many sweeps finish

-- shared fire behavior: a burst of projectiles either fanned across an angle
-- or spaced evenly around a full circle, plus a matching ring-shockwave FX
local function fire_spread(instance, type_def, spawn_projectile, opts)
    local FXManager = require("src/fx_manager")
    local cx = instance.x + type_def.width / 2
    local cy = instance.y + type_def.height
    local count = opts.count

    if opts.full_circle then
        local rotation_offset = opts.rotation_offset or 0
        for i = 1, count do
            local angle = (i - 1) / count * math.pi * 2 + rotation_offset
            spawn_projectile(cx, cy, math.sin(angle), math.cos(angle))
        end
    else
        local spread_angle = opts.spread_angle
        for i = 1, count do
            local t = (count == 1) and 0.5 or (i - 1) / (count - 1)
            local angle = -spread_angle + t * (2 * spread_angle)
            spawn_projectile(cx, cy, math.sin(angle), math.cos(angle))
        end
    end

    local c = opts.ring_color or { 1, 1, 1 }
    FXManager.spawn_ring(cx, cy, c[1], c[2], c[3], 10, 55, 220)
end

local BOSS_TYPES = {
    sentinel = {
        width = 90,
        height = 60,
        color_fill = { 1, 0.1, 0.6 },
        color_core = { 1, 0.6, 0.85 },
        patrol_amplitude = 240,
        patrol_speed = 0.8,
        fire_interval = 1.4,
        fire = function(instance, type_def, spawn_projectile)
            fire_spread(instance, type_def, spawn_projectile,
                { count = 5, spread_angle = math.rad(50), ring_color = { 1, 0.2, 0.6 } })
        end,
    },
    homing = {
        width = 80,
        height = 55,
        color_fill = { 0.15, 0.9, 0.45 },
        color_core = { 0.6, 1, 0.75 },
        patrol_amplitude = 150,
        patrol_speed = 0.5,
        fire_interval = 2.2,
        fire = function(instance, type_def, spawn_projectile)
            local FXManager = require("src/fx_manager")
            local cx = instance.x + type_def.width / 2
            local cy = instance.y + type_def.height
            spawn_projectile(cx, cy, 0, 1, true)
            FXManager.spawn_ring(cx, cy, 0.15, 0.9, 0.45, 10, 45, 180)
        end,
    },
    laser = {
        width = 100,
        height = 50,
        color_fill = { 1, 0.55, 0.05 },
        color_core = { 1, 0.8, 0.4 },
        patrol_amplitude = 40,
        patrol_speed = 0.3,
        is_laser = true,
    },
    splitter = {
        width = 65,
        height = 45,
        color_fill = { 0.75, 1, 0.2 },
        color_core = { 0.9, 1, 0.6 },
        patrol_amplitude = 200,
        patrol_speed = 1.3,
        fire_interval = 1.0,
        fire = function(instance, type_def, spawn_projectile)
            fire_spread(instance, type_def, spawn_projectile,
                { count = 6, spread_angle = math.rad(45), ring_color = { 0.75, 1, 0.2 } })
        end,
        is_splitter = true,
        split_time = 6,
    },
    -- spawned by splitter's split, not part of the normal boss sequence
    splitter_clone = {
        width = 42,
        height = 30,
        color_fill = { 0.75, 1, 0.2 },
        color_core = { 0.9, 1, 0.6 },
        patrol_amplitude = 160,
        patrol_speed = 1.6,
        fire_interval = 1.3,
        fire = function(instance, type_def, spawn_projectile)
            fire_spread(instance, type_def, spawn_projectile,
                { count = 4, spread_angle = math.rad(35), ring_color = { 0.75, 1, 0.2 } })
        end,
    },
    turret = {
        width = 110,
        height = 70,
        color_fill = { 0.15, 0.35, 0.95 },
        color_core = { 0.5, 0.65, 1 },
        is_orbiter = true,
        orbit_radius = 170,
        orbit_center_y = 260,
        orbit_speed = 0.6,
        fire_interval = 1.5,
        -- two rings per volley, the second interleaved into the first's gaps
        -- (half the 36-degree spacing of a 10-shot ring = 18 degrees) and
        -- fired ~0.18s later, so dodging one ring isn't enough to be safe
        fire = function(instance, type_def, spawn_projectile)
            instance.turret_rotation = (instance.turret_rotation or 0) + math.rad(18)
            fire_spread(instance, type_def, spawn_projectile,
                { count = 10, full_circle = true, ring_color = { 0.4, 0.6, 1 }, rotation_offset = instance.turret_rotation })

            instance.pending_second_burst = 0.18
            instance.pending_second_offset = instance.turret_rotation + math.rad(18)
        end,
        fire_second = function(instance, type_def, spawn_projectile)
            fire_spread(instance, type_def, spawn_projectile,
                { count = 10, full_circle = true, ring_color = { 0.4, 0.6, 1 }, rotation_offset = instance.pending_second_offset })
        end,
    },
}

local function new_instance(type_id, x, y)
    return {
        type_id = type_id,
        phase = "enter",
        x = x,
        base_x = x,
        y = y,
        age = 0,
        hover_timer = 0,
        fire_timer = 0,
        hit_cooldown = 0,
        split_done = false,
        laser_state = "cooldown",
        laser_timer = 0,
        laser_axis = "horizontal",
        laser_row_y = 0,
        laser_row_start = 0,
        laser_row_end = 0,
        laser_sweep_count = 0,
        shot_timer = 0,
    }
end

function Boss.load()
    Boss.instances = {}
    Boss.active = false
    Boss.is_paused = false
end

function Boss.spawn(type_id)
    local type_def = BOSS_TYPES[type_id]
    local width = love.graphics.getWidth()
    local x

    if type_def.is_orbiter then
        -- land exactly where the orbit formula (age=0) will place it, so hover
        -- doesn't start with an instant jump from the generic entry point
        x = width / 2 + type_def.orbit_radius - type_def.width / 2
    else
        x = width / 2 - type_def.width / 2
    end

    Boss.instances = { new_instance(type_id, x, -type_def.height) }
    Boss.active = true
end

function Boss.spawn_split_clones(instance)
    local offset = 50
    local clone_a = new_instance("splitter_clone", instance.x - offset, instance.y)
    local clone_b = new_instance("splitter_clone", instance.x + offset, instance.y)

    for _, clone in ipairs({ clone_a, clone_b }) do
        clone.phase = "hover"
        clone.hover_timer = instance.hover_timer
        clone.base_x = clone.x
        table.insert(Boss.instances, clone)
    end
end

local function laser_fire_aimed_shot(instance, type_def, player, spawn_projectile)
    local FXManager = require("src/fx_manager")
    local cx = instance.x + type_def.width / 2
    local cy = instance.y + type_def.height
    local player_cx = player.x + player.size / 2
    local player_cy = player.y + player.size / 2
    local dx, dy = player_cx - cx, player_cy - cy
    local len = math.sqrt(dx * dx + dy * dy)
    if len > 0 then
        spawn_projectile(cx, cy, dx / len, dy / len, false)
    end
    FXManager.spawn_ring(cx, cy, 1, 0.7, 0.2, 8, 35, 190)
end

function Boss.update_laser(instance, type_def, dt, player, spawn_projectile)
    instance.laser_timer = instance.laser_timer + dt

    -- aimed shots fire on their own steady cadence, independent of the beam cycle
    instance.shot_timer = instance.shot_timer + dt
    if instance.shot_timer >= LASER_SHOT_INTERVAL then
        instance.shot_timer = 0
        laser_fire_aimed_shot(instance, type_def, player, spawn_projectile)
    end

    if instance.laser_state == "cooldown" then
        if instance.laser_timer >= LASER_COOLDOWN_DURATION then
            instance.laser_state = "telegraph"
            instance.laser_timer = 0

            instance.laser_axis = (love.math.random() < 0.5) and "horizontal" or "vertical"
            local span = (instance.laser_axis == "horizontal") and love.graphics.getHeight() or
                love.graphics.getWidth()

            if love.math.random() < 0.5 then
                instance.laser_row_start = LASER_EDGE_MARGIN
                instance.laser_row_end = span - LASER_EDGE_MARGIN
            else
                instance.laser_row_start = span - LASER_EDGE_MARGIN
                instance.laser_row_end = LASER_EDGE_MARGIN
            end

            instance.laser_row_y = instance.laser_row_start
        end
    elseif instance.laser_state == "telegraph" then
        if instance.laser_timer >= LASER_TELEGRAPH_DURATION then
            instance.laser_state = "firing"
            instance.laser_timer = 0
        end
    elseif instance.laser_state == "firing" then
        local t = math.min(instance.laser_timer / LASER_FIRE_DURATION, 1)
        instance.laser_row_y = instance.laser_row_start + (instance.laser_row_end - instance.laser_row_start) * t

        if instance.laser_timer >= LASER_FIRE_DURATION then
            instance.laser_state = "cooldown"
            instance.laser_timer = 0
            instance.laser_sweep_count = instance.laser_sweep_count + 1
        end
    end
end

function Boss.check_laser_collision(instance, player, on_player_hit)
    if instance.laser_state ~= "firing" or instance.hit_cooldown > 0 or player.is_dashing then return end

    local half_band = LASER_THICKNESS / 2 + player.size / 2
    local player_pos

    if instance.laser_axis == "horizontal" then
        player_pos = player.y + player.size / 2
    else
        player_pos = player.x + player.size / 2
    end

    if math.abs(player_pos - instance.laser_row_y) < half_band then
        instance.hit_cooldown = HIT_COOLDOWN
        on_player_hit()
    end
end

function Boss.check_instance_collision(instance, type_def, player, on_player_hit)
    if instance.hit_cooldown > 0 or player.is_dashing then return end

    local padding = type_def.width * COLLISION_PADDING_RATIO

    if player.x < (instance.x + type_def.width - padding) and (instance.x + padding) < player.x + player.size and
        player.y < instance.y + type_def.height and instance.y < player.y + player.size then
        instance.hit_cooldown = HIT_COOLDOWN
        on_player_hit()
    end
end

function Boss.update_instance(instance, type_def, dt, player, on_player_hit, spawn_projectile, on_type_exit)
    instance.age = instance.age + dt
    if instance.hit_cooldown > 0 then
        instance.hit_cooldown = instance.hit_cooldown - dt
    end

    if instance.phase == "enter" then
        instance.y = instance.y + ENTER_SPEED * dt
        -- orbiters must land exactly where their orbit formula starts (age=0),
        -- otherwise hover begins with an instant jump to the orbit's position
        local target_y = type_def.is_orbiter and (type_def.orbit_center_y - type_def.height / 2) or HOVER_Y
        if instance.y >= target_y then
            instance.y = target_y
            instance.phase = "hover"
            instance.age = 0
            instance.fire_timer = 0
        end
    elseif instance.phase == "hover" then
        instance.hover_timer = instance.hover_timer + dt

        if type_def.is_orbiter then
            local width = love.graphics.getWidth()
            local center_x = width / 2
            instance.x = center_x + math.cos(instance.age * type_def.orbit_speed) * type_def.orbit_radius -
                type_def.width / 2
            instance.y = type_def.orbit_center_y + math.sin(instance.age * type_def.orbit_speed) * type_def.orbit_radius -
                type_def.height / 2
        else
            instance.x = instance.base_x + math.sin(instance.age * type_def.patrol_speed) * type_def.patrol_amplitude
        end

        if type_def.is_laser then
            Boss.update_laser(instance, type_def, dt, player, spawn_projectile)
        else
            instance.fire_timer = instance.fire_timer + dt
            if instance.fire_timer >= type_def.fire_interval then
                instance.fire_timer = 0
                type_def.fire(instance, type_def, spawn_projectile)
            end
        end

        if instance.pending_second_burst then
            instance.pending_second_burst = instance.pending_second_burst - dt
            if instance.pending_second_burst <= 0 then
                instance.pending_second_burst = nil
                if type_def.fire_second then
                    type_def.fire_second(instance, type_def, spawn_projectile)
                end
            end
        end

        if type_def.is_splitter and not instance.split_done and instance.hover_timer >= type_def.split_time then
            instance.split_done = true
            Boss.spawn_split_clones(instance)
            instance.remove = true
            return
        end

        -- laser exits once it's completed a fixed sweep count instead of the
        -- generic time budget, so it never leaves mid-telegraph/mid-sweep and
        -- always shows exactly LASER_MAX_SWEEPS sweeps, no more, no fewer
        local encounter_done
        if type_def.is_laser then
            encounter_done = instance.laser_sweep_count >= LASER_MAX_SWEEPS
        else
            encounter_done = instance.hover_timer >= ENCOUNTER_DURATION
        end

        if encounter_done then
            instance.phase = "exit"
            -- lets main.lua react to a specific type leaving (e.g. clearing
            -- the homing boss's still-active shots so they don't keep
            -- chasing the player once the boss itself is already gone)
            if on_type_exit then
                on_type_exit(instance.type_id)
            end
        end
    elseif instance.phase == "exit" then
        instance.y = instance.y - EXIT_SPEED * dt
        if instance.y < -type_def.height then
            instance.remove = true
            return
        end
    end

    local width = love.graphics.getWidth()
    if instance.x < 0 then instance.x = 0 end
    if instance.x > width - type_def.width then instance.x = width - type_def.width end

    if type_def.is_laser then
        Boss.check_laser_collision(instance, player, on_player_hit)
    end

    Boss.check_instance_collision(instance, type_def, player, on_player_hit)
end

function Boss.update(dt, game_over, player, on_player_hit, spawn_projectile, on_encounter_end, on_type_exit)
    if not Boss.active or game_over or Boss.is_paused then return end

    local instances = Boss.instances

    for i = #instances, 1, -1 do
        local instance = instances[i]
        local type_def = BOSS_TYPES[instance.type_id]

        Boss.update_instance(instance, type_def, dt, player, on_player_hit, spawn_projectile, on_type_exit)

        if instance.remove then
            table.remove(instances, i)
        end
    end

    if #instances == 0 then
        Boss.active = false
        if on_encounter_end then on_encounter_end() end
    end
end

function Boss.draw_laser(instance)
    local width = love.graphics.getWidth()
    local height = love.graphics.getHeight()
    local horizontal = instance.laser_axis == "horizontal"

    if instance.laser_state == "telegraph" then
        -- only the start line is shown -- it's a full edge-to-edge sweep now,
        -- so a second line for the far end just added visual noise
        love.graphics.setLineWidth(2)
        love.graphics.setColor(1, 0.85, 0.5, 0.45)
        if horizontal then
            love.graphics.line(0, instance.laser_row_start, width, instance.laser_row_start)
        else
            love.graphics.line(instance.laser_row_start, 0, instance.laser_row_start, height)
        end
        love.graphics.setLineWidth(1)
    elseif instance.laser_state == "firing" then
        love.graphics.setColor(1, 0.95, 0.6, 0.92)
        if horizontal then
            love.graphics.rectangle("fill", 0, instance.laser_row_y - LASER_THICKNESS / 2, width, LASER_THICKNESS)
        else
            love.graphics.rectangle("fill", instance.laser_row_y - LASER_THICKNESS / 2, 0, LASER_THICKNESS, height)
        end
    end
end

function Boss.draw()
    for _, instance in ipairs(Boss.instances) do
        local type_def = BOSS_TYPES[instance.type_id]

        love.graphics.setColor(type_def.color_fill[1], type_def.color_fill[2], type_def.color_fill[3])
        love.graphics.rectangle("fill", instance.x, instance.y, type_def.width, type_def.height, 10, 10)

        love.graphics.setColor(type_def.color_core[1], type_def.color_core[2], type_def.color_core[3])
        love.graphics.rectangle("fill",
            instance.x + type_def.width * 0.16, instance.y + type_def.height * 0.25,
            type_def.width * 0.68, type_def.height * 0.5, 6, 6)

        if type_def.is_laser and instance.phase == "hover" then
            Boss.draw_laser(instance)
        end
    end
end

function Boss.debug_summary()
    if #Boss.instances == 0 then return "(none)" end

    local parts = {}
    for _, instance in ipairs(Boss.instances) do
        table.insert(parts, instance.type_id .. ":" .. instance.phase)
    end
    return table.concat(parts, ", ")
end

function Boss.pause() Boss.is_paused = true end

function Boss.resume() Boss.is_paused = false end

function Boss.reset()
    Boss.instances = {}
    Boss.active = false
end

return Boss
