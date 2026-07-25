local FXManager                = require("src/fx_manager")

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

-- Movement modes. Each type_def picks one via `movement` (defaulting to the
-- sine patrol); the function owns where the boss is on every hover frame.
-- This started as an if/elseif chain on is_orbiter/is_bouncer, which stopped
-- scaling once charger/phantom needed their own multi-phase motion -- the
-- flags themselves are still around because spawn placement, the edge clamp
-- and clone-vs-clone collision key off them, which isn't movement.
local patrol_movement, orbit_movement, bounce_movement, charge_movement, blink_movement

-- sine sweep across patrol_amplitude -- amplitude 0 gives "stationary" free
function patrol_movement(instance, type_def)
    instance.x = instance.base_x + math.sin(instance.age * type_def.patrol_speed) * type_def.patrol_amplitude
end

function orbit_movement(instance, type_def)
    local center_x = love.graphics.getWidth() / 2
    instance.x = center_x + math.cos(instance.age * type_def.orbit_speed) * type_def.orbit_radius -
        type_def.width / 2
    instance.y = type_def.orbit_center_y + math.sin(instance.age * type_def.orbit_speed) * type_def.orbit_radius -
        type_def.height / 2
end

-- straight line at a constant speed; the edge clamp in update_instance and
-- resolve_bouncer_collisions are what actually reverse bounce_dir
function bounce_movement(instance, type_def, dt)
    instance.x = instance.x + instance.bounce_dir * type_def.bounce_speed * dt
end

-- charger: line up over the player, telegraph the column it's about to fall
-- through, slam to the floor, climb back up, repeat. The body is the whole
-- attack -- it fires nothing -- so this is the one encounter where standing
-- still is what kills you and dash-phasing through the boss is the answer.
function charge_movement(instance, type_def, dt, player)
    instance.charge_timer = instance.charge_timer + dt

    if instance.charge_state == "aim" then
        -- track the player's column, but capped -- it closes the gap rather
        -- than teleporting onto them, so running is a real option
        local target_x = player.x + player.size / 2 - type_def.width / 2
        local delta = target_x - instance.x
        local step = type_def.track_speed * dt
        if math.abs(delta) <= step then
            instance.x = target_x
        else
            instance.x = instance.x + (delta > 0 and step or -step)
        end

        if instance.charge_timer >= type_def.aim_duration then
            instance.charge_state = "telegraph"
            instance.charge_timer = 0
        end
    elseif instance.charge_state == "telegraph" then
        -- deliberately motionless: the warning column below it is only
        -- honest if the boss can't still be sliding sideways as it fires
        if instance.charge_timer >= type_def.telegraph_duration then
            instance.charge_state = "slam"
            instance.charge_timer = 0
        end
    elseif instance.charge_state == "slam" then
        instance.y = instance.y + type_def.slam_speed * dt
        local floor_y = love.graphics.getHeight() - type_def.height - 10
        if instance.y >= floor_y then
            instance.y = floor_y
            instance.charge_state = "retreat"
            instance.charge_timer = 0
        end
    elseif instance.charge_state == "retreat" then
        instance.y = instance.y - type_def.retreat_speed * dt
        if instance.y <= HOVER_Y then
            instance.y = HOVER_Y
            instance.charge_state = "aim"
            instance.charge_timer = 0
        end
    end
end

-- phantom: fade out, reappear somewhere else, fire on arrival. While it's
-- anything but fully visible it sets `intangible`, which switches off both
-- its collision and its firing -- a half-faded boss you can still walk into
-- (or that shoots you from nowhere) reads as a bug, not a mechanic.
function blink_movement(instance, type_def, dt, player)
    instance.blink_timer = instance.blink_timer + dt

    if instance.blink_state == "visible" then
        instance.alpha = 1
        instance.intangible = false
        if instance.blink_timer >= type_def.visible_duration then
            instance.blink_state = "fading"
            instance.blink_timer = 0
        end
    elseif instance.blink_state == "fading" then
        instance.intangible = true
        instance.alpha = 1 - math.min(instance.blink_timer / type_def.fade_duration, 1)
        if instance.blink_timer >= type_def.fade_duration then
            instance.blink_state = "appearing"
            instance.blink_timer = 0
            instance.x, instance.y = Boss.pick_blink_position(type_def, player)
        end
    elseif instance.blink_state == "appearing" then
        instance.intangible = true
        instance.alpha = math.min(instance.blink_timer / type_def.fade_duration, 1)
        if instance.blink_timer >= type_def.fade_duration then
            instance.blink_state = "visible"
            instance.blink_timer = 0
            -- cleared here rather than waiting for the "visible" branch next
            -- frame: for that one frame it would be drawn fully solid while
            -- still passing through the player and holding its fire
            instance.intangible = false
            instance.fire_timer = type_def.fire_interval -- fires immediately on arrival
        end
    end
end

-- somewhere in the upper arena, at least BLINK_MIN_PLAYER_DISTANCE from the
-- player -- materializing on top of them would be an unreactable hit
local BLINK_MIN_PLAYER_DISTANCE = 150
local BLINK_EDGE_MARGIN = 40
local BLINK_MIN_Y = 60
local BLINK_MAX_Y = 330

function Boss.pick_blink_position(type_def, player)
    local width = love.graphics.getWidth()
    local max_x = width - type_def.width - BLINK_EDGE_MARGIN
    local player_cx = player.x + player.size / 2
    local player_cy = player.y + player.size / 2
    local x, y

    for _ = 1, 8 do
        x = love.math.random(BLINK_EDGE_MARGIN, max_x)
        y = love.math.random(BLINK_MIN_Y, BLINK_MAX_Y)
        local dx = (x + type_def.width / 2) - player_cx
        local dy = (y + type_def.height / 2) - player_cy
        if math.sqrt(dx * dx + dy * dy) >= BLINK_MIN_PLAYER_DISTANCE then
            return x, y
        end
    end

    -- every try landed too close (player is mid-arena) -- take the last roll
    -- rather than looping forever
    return x, y
end

-- shared fire behavior: a burst of projectiles either fanned across an angle
-- or spaced evenly around a full circle, plus a matching ring-shockwave FX
local function fire_spread(instance, type_def, spawn_projectile, opts)
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

-- a single shot aimed at wherever the player currently is (computed once at
-- fire time, not steering afterward like homing does) -- unlike any fixed
-- angle or fan, this can't have a geometric blind spot: a fan wide enough to
-- cover every camping spot (including corners) stops looking like a fan, so
-- tracking the player's actual position is the only fix that generalizes
local function fire_aimed_shot(instance, type_def, player, spawn_projectile, opts)
    local cx = instance.x + type_def.width / 2
    local cy = instance.y + type_def.height
    local player_cx = player.x + player.size / 2
    local player_cy = player.y + player.size / 2
    local dx, dy = player_cx - cx, player_cy - cy
    local len = math.sqrt(dx * dx + dy * dy)
    if len > 0 then
        spawn_projectile(cx, cy, dx / len, dy / len, false)
    end
    local c = (opts and opts.ring_color) or { 1, 1, 1 }
    FXManager.spawn_ring(cx, cy, c[1], c[2], c[3], 8, 35, 190)
end

local BOSS_TYPES = {
    sentinel = {
        width = 125,
        height = 75,
        color_fill = { 1, 0.1, 0.6 },
        color_core = { 1, 0.6, 0.85 },
        -- patrol_amplitude must reach both screen edges from a centered
        -- base_x (337.5px away each side at this width) -- it used to fall
        -- well short (240), leaving the far left/right permanently unvisited
        -- by the boss's own body regardless of the player_min_y wall below
        patrol_amplitude = 350,
        patrol_speed = 0.8,
        fire_interval = 1.4,
        -- walls off the top of the screen (see Boss.get_player_bounds): a
        -- single tracked shot every couple seconds was still trivially
        -- dodgeable from a static camping spot, so this pairs a bigger body
        -- (harder to squeeze past during patrol) with denying the player the
        -- "stand above the boss and ignore everything" position outright
        player_min_y = 155,
        fire = function(instance, type_def, spawn_projectile)
            fire_spread(instance, type_def, spawn_projectile,
                { count = 7, spread_angle = math.rad(50), ring_color = { 1, 0.2, 0.6 } })
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
        -- same top-of-screen wall as sentinel/splitter (see
        -- Boss.get_player_bounds) -- homing's own shots already steer
        -- continuously so they don't need this to stay threatening, but a
        -- player parked far enough above still had time to read and juke
        -- each shot before it curved into range
        player_min_y = 135,
        fire = function(instance, type_def, spawn_projectile)
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
        draw_extra = function(instance)
            if instance.phase == "hover" then Boss.draw_laser(instance) end
        end,
        -- sweep count matters as much as the beam state here: it's what the
        -- encounter actually exits on (LASER_MAX_SWEEPS), not the timer
        debug_state = function(instance)
            return string.format("%s %d/%d", instance.laser_state, instance.laser_sweep_count, LASER_MAX_SWEEPS)
        end,
    },
    splitter = {
        width = 85,
        height = 55,
        color_fill = { 0.75, 1, 0.2 },
        color_core = { 0.9, 1, 0.6 },
        -- must reach both screen edges from a centered base_x (357.5px away
        -- each side at this width) -- 200 fell well short, leaving both the
        -- far left and far right permanently unvisited by the boss's body
        patrol_amplitude = 370,
        patrol_speed = 0.85,
        fire_interval = 1.0,
        player_min_y = 135,
        fire = function(instance, type_def, spawn_projectile)
            fire_spread(instance, type_def, spawn_projectile,
                { count = 8, spread_angle = math.rad(45), ring_color = { 0.75, 1, 0.2 } })
        end,
        is_splitter = true,
        split_time = 6,
    },
    -- spawned by splitter's split, not part of the normal boss sequence.
    -- unlike every other type, clones don't sine-patrol -- they ping-pong in
    -- a straight line, reversing off the screen's left/right edges and off
    -- each other (see resolve_bouncer_collisions below). Sine-patrolling
    -- both clones off a shared formula made them drift side-by-side in near
    -- lockstep instead of actually splitting up to cover the arena, and a
    -- sine amplitude wide enough to reach both edges from any split position
    -- gave them an absurd peak velocity (amplitude * speed) on top of that.
    splitter_clone = {
        width = 42,
        height = 30,
        color_fill = { 0.75, 1, 0.2 },
        color_core = { 0.9, 1, 0.6 },
        is_bouncer = true,
        movement = bounce_movement,
        bounce_speed = 230,
        fire_interval = 1.3,
        player_min_y = 110,
        fire = function(instance, type_def, spawn_projectile)
            fire_spread(instance, type_def, spawn_projectile,
                { count = 6, spread_angle = math.rad(35), ring_color = { 0.75, 1, 0.2 } })
        end,
    },
    turret = {
        width = 110,
        height = 70,
        color_fill = { 0.15, 0.35, 0.95 },
        color_core = { 0.5, 0.65, 1 },
        is_orbiter = true,
        movement = orbit_movement,
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
    -- the only boss that fires nothing at all: it lines up over the player,
    -- telegraphs the column it's about to fall through, and slams. Every
    -- other encounter is "dodge what it shoots"; this one is "don't be where
    -- it's going", which makes standing still the failure state
    charger = {
        width = 90,
        height = 70,
        color_fill = { 0.55, 0.8, 1 },
        color_core = { 0.9, 0.97, 1 },
        movement = charge_movement,
        -- without this the whole encounter is dodgeable by standing above it:
        -- it only ever slams *downward*, so anything higher than its hover
        -- line is a position it structurally cannot threaten
        player_min_y = 175,
        track_speed = 250,
        aim_duration = 1.1,
        telegraph_duration = 0.55,
        slam_speed = 1250,
        retreat_speed = 430,
        draw_extra = function(instance, type_def)
            if instance.phase ~= "hover" or instance.charge_state ~= "telegraph" then return end

            -- the column it's committed to falling through, from its own
            -- bottom edge all the way to the floor
            local height = love.graphics.getHeight()
            local top = instance.y + type_def.height
            local pulse = 0.16 + 0.3 * math.abs(math.sin(love.timer.getTime() * 16))

            love.graphics.setColor(0.6, 0.85, 1, pulse)
            love.graphics.rectangle("fill", instance.x, top, type_def.width, height - top)

            love.graphics.setLineWidth(2)
            love.graphics.setColor(0.8, 0.95, 1, 0.5)
            love.graphics.line(instance.x, top, instance.x, height)
            love.graphics.line(instance.x + type_def.width, top, instance.x + type_def.width, height)
            love.graphics.setLineWidth(1)
            love.graphics.setColor(1, 1, 1, 1)
        end,
        debug_state = function(instance) return instance.charge_state end,
    },
    -- boss-scale zone denial: instead of shooting, it seeds the arena with
    -- real Mine hazards (same telegraph language the player already knows
    -- from the wave hazard, just at a rhythm that keeps them moving). One
    -- bomb per volley targets where the player is standing, so camping is
    -- punished; the other is scattered so the whole arena stays live
    bomber = {
        width = 105,
        height = 60,
        color_fill = { 0.8, 0.65, 0.1 },
        color_core = { 1, 0.9, 0.45 },
        -- reaches both screen edges from a centered base_x (347.5px away at
        -- this width) -- see the sentinel/splitter note above
        patrol_amplitude = 348,
        patrol_speed = 0.55,
        fire_interval = 1.5,
        -- bombs can't be seeded right at the top of the screen without
        -- overlapping the boss's own body, so the same wall the other types
        -- use closes that strip off instead -- otherwise it'd be a region
        -- bombs never cover and the encounter could be sat out up there
        player_min_y = 130,
        bomb_edge_margin = 45,
        bomb_min_y = 160,
        bomb_max_y = 520,
        fire = function(instance, type_def, spawn_projectile, player, spawn_mine)
            if not spawn_mine then return end

            local width = love.graphics.getWidth()
            local min_x, max_x = type_def.bomb_edge_margin, width - type_def.bomb_edge_margin

            local aimed_x = math.max(min_x, math.min(player.x + player.size / 2, max_x))
            spawn_mine(aimed_x, math.max(type_def.bomb_min_y, math.min(player.y + player.size / 2, type_def.bomb_max_y)))
            spawn_mine(love.math.random(min_x, max_x), love.math.random(type_def.bomb_min_y, type_def.bomb_max_y))

            local cx = instance.x + type_def.width / 2
            local cy = instance.y + type_def.height
            FXManager.spawn_ring(cx, cy, 1, 0.75, 0.2, 10, 45, 200)
        end,
    },
    -- squeezes the legal play area inward over the encounter (see
    -- update_warden_arena) while lobbing a slow spread. Generalizes the
    -- existing Player.min_y wall from one edge to all four -- the shots
    -- barely matter on their own, the point is that the room to dodge them
    -- keeps shrinking
    warden = {
        width = 115,
        height = 65,
        color_fill = { 0.5, 0.45, 0.75 },
        color_core = { 0.8, 0.75, 1 },
        patrol_amplitude = 130,
        patrol_speed = 0.4,
        fire_interval = 1.7,
        is_warden = true,
        -- the arena it closes down to, and how much of the encounter it
        -- takes to get there (held at full squeeze for the remainder)
        arena_final_width = 380,
        arena_final_min_y = 215,
        arena_close_ratio = 0.8,
        fire = function(instance, type_def, spawn_projectile)
            fire_spread(instance, type_def, spawn_projectile,
                { count = 5, spread_angle = math.rad(55), ring_color = { 0.6, 0.5, 0.9 } })
        end,
        -- the arena it's currently enforcing, which is the whole threat --
        -- worth seeing as a number while tuning the squeeze
        -- hover-only and rounded to 10s: the arena is only actually enforced
        -- while hovering (so reporting the stale value on the way out would
        -- describe a wall that isn't there), and the raw number changes every
        -- frame, which flickers instead of reading as a settling value
        debug_state = function(instance)
            if instance.phase ~= "hover" or not instance.arena_min_x then return nil end
            local function round10(n) return math.floor(n / 10 + 0.5) * 10 end
            return string.format("arena %dx%d", round10(instance.arena_max_x - instance.arena_min_x),
                round10(love.graphics.getHeight() - instance.arena_min_y))
        end,
    },
    -- no readable patrol at all: it blinks around the arena and fires the
    -- instant it lands, so there's no corner you can pre-plan as safe
    phantom = {
        width = 85,
        height = 55,
        color_fill = { 0.75, 0.75, 0.82 },
        color_core = { 1, 1, 1 },
        movement = blink_movement,
        visible_duration = 1.5,
        fade_duration = 0.35,
        fire_interval = 0.8,
        -- fires a full ring rather than a downward fan: it materializes at an
        -- unpredictable spot, so a directional attack would be dodgeable just
        -- by staying above wherever it happened to land. A ring makes its
        -- position the threat, which is the whole point of the type, and
        -- means it needs no player_min_y wall to stay honest
        fire = function(instance, type_def, spawn_projectile)
            fire_spread(instance, type_def, spawn_projectile,
                { count = 9, full_circle = true, ring_color = { 0.85, 0.85, 0.95 } })
        end,
        -- intangible is the non-obvious half of a blink (collision AND firing
        -- both off), so surface it rather than just the visual state
        debug_state = function(instance)
            return instance.blink_state .. (instance.intangible and " (intangible)" or "")
        end,
    },
}

-- The fixed cycle order encounters run in, repeating once exhausted. Lives
-- here rather than in main.lua because it's a property of the boss roster,
-- not of wave scheduling -- main.lua reads it for the cadence and Debug reads
-- it for its spawn hotkeys, so adding a type means touching only this file.
-- The four newer types are interleaved rather than appended: on the end
-- they'd sit behind five encounters (wave 36+) and never be seen in a run.
Boss.SEQUENCE = {
    "sentinel", "charger", "homing", "bomber", "laser", "phantom", "splitter", "warden", "turret"
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
        bounce_dir = 1,
        split_done = false,
        laser_state = "cooldown",
        laser_timer = 0,
        laser_axis = "horizontal",
        laser_row_y = 0,
        laser_row_start = 0,
        laser_row_end = 0,
        laser_sweep_count = 0,
        shot_timer = 0,
        charge_state = "aim",
        charge_timer = 0,
        blink_state = "visible",
        blink_timer = 0,
        -- phantom fades via alpha and switches off both its collision and
        -- its firing while intangible; every other type leaves these alone
        alpha = 1,
        intangible = false,
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
    local buffer = 40 -- guaranteed room to move outward before either could reach a wall
    local width = love.graphics.getWidth()
    local clone_width = BOSS_TYPES.splitter_clone.width

    -- clamp the split's reference point (not just each clone's final
    -- position) so BOTH clones always spawn with genuine clearance to move
    -- outward -- clamping only the final position still let one land exactly
    -- on a wall, and its very first movement frame (trying to go further
    -- outward) would immediately bounce it back inward, same direction as
    -- its sibling, before it ever visibly moved the "right" way
    local min_center = offset + buffer
    local max_center = width - clone_width - offset - buffer
    local center_x = math.max(min_center, math.min(instance.x, max_center))

    local clone_a = new_instance("splitter_clone", center_x - offset, instance.y)
    local clone_b = new_instance("splitter_clone", center_x + offset, instance.y)

    -- send them apart from the start, not toward each other
    clone_a.bounce_dir = -1
    clone_b.bounce_dir = 1

    for _, clone in ipairs({ clone_a, clone_b }) do
        clone.phase = "hover"
        clone.hover_timer = instance.hover_timer
        table.insert(Boss.instances, clone)
    end
end

function Boss.update_laser(instance, type_def, dt, player, spawn_projectile)
    instance.laser_timer = instance.laser_timer + dt

    -- aimed shots fire on their own steady cadence, independent of the beam cycle
    instance.shot_timer = instance.shot_timer + dt
    if instance.shot_timer >= LASER_SHOT_INTERVAL then
        instance.shot_timer = 0
        fire_aimed_shot(instance, type_def, player, spawn_projectile, { ring_color = { 1, 0.7, 0.2 } })
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
    -- intangible covers the phantom mid-blink: it's drawn faded but isn't
    -- really there, so walking through it must be free
    if instance.hit_cooldown > 0 or player.is_dashing or instance.intangible then return end

    local padding = type_def.width * COLLISION_PADDING_RATIO

    if player.x < (instance.x + type_def.width - padding) and (instance.x + padding) < player.x + player.size and
        player.y < instance.y + type_def.height and instance.y < player.y + player.size then
        instance.hit_cooldown = HIT_COOLDOWN
        on_player_hit()
    end
end

-- warden only: eases the legal play area from the full screen down to a
-- centered arena_final_width column whose top edge sits below the boss, over
-- arena_close_ratio of the encounter, then holds. Written onto the instance
-- (not the type_def) because Boss.get_player_bounds reads whatever the live
-- instances currently want, and two wardens would each have their own.
local function update_warden_arena(instance, type_def)
    local width = love.graphics.getWidth()
    local t = math.min(instance.hover_timer / (ENCOUNTER_DURATION * type_def.arena_close_ratio), 1)
    -- ease-out so most of the squeeze lands early and the last stretch is a
    -- slow tighten rather than a sudden clamp
    local eased = 1 - (1 - t) * (1 - t)

    local half = (width - (width - type_def.arena_final_width) * eased) / 2
    instance.arena_min_x = width / 2 - half
    instance.arena_max_x = width / 2 + half
    instance.arena_min_y = type_def.arena_final_min_y * eased
end

function Boss.update_instance(instance, type_def, dt, player, on_player_hit, spawn_projectile, on_type_exit, spawn_mine)
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

        local movement = type_def.movement or patrol_movement
        movement(instance, type_def, dt, player)

        if type_def.is_warden then
            update_warden_arena(instance, type_def)
        end

        if type_def.is_laser then
            Boss.update_laser(instance, type_def, dt, player, spawn_projectile)
        elseif type_def.fire and not instance.intangible then
            -- `fire` is optional (charger attacks with its body alone), and a
            -- half-faded phantom doesn't shoot -- see blink_movement
            instance.fire_timer = instance.fire_timer + dt
            if instance.fire_timer >= type_def.fire_interval then
                instance.fire_timer = 0
                type_def.fire(instance, type_def, spawn_projectile, player, spawn_mine)
            end
        end

        if instance.pending_second_burst then
            instance.pending_second_burst = instance.pending_second_burst - dt
            if instance.pending_second_burst <= 0 then
                instance.pending_second_burst = nil
                if type_def.fire_second then
                    type_def.fire_second(instance, type_def, spawn_projectile, player, spawn_mine)
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
    if instance.x < 0 then
        instance.x = 0
        if type_def.is_bouncer then instance.bounce_dir = 1 end
    end
    if instance.x > width - type_def.width then
        instance.x = width - type_def.width
        if type_def.is_bouncer then instance.bounce_dir = -1 end
    end

    if type_def.is_laser then
        Boss.check_laser_collision(instance, player, on_player_hit)
    end

    Boss.check_instance_collision(instance, type_def, player, on_player_hit)
end

-- bouncer types (currently only splitter_clone) reverse off each other, not
-- just the screen edges -- pushes direction explicitly away from the other
-- clone (rather than toggling) so re-triggering every frame while still
-- overlapping can't cause flip-flip jitter, it just keeps asserting "apart"
-- until they've actually separated
local function resolve_bouncer_collisions(instances)
    for i = 1, #instances do
        local a = instances[i]
        local a_def = BOSS_TYPES[a.type_id]
        if a_def.is_bouncer and a.phase == "hover" then
            for j = i + 1, #instances do
                local b = instances[j]
                local b_def = BOSS_TYPES[b.type_id]
                if b_def.is_bouncer and b.phase == "hover" then
                    local overlapping = a.x < b.x + b_def.width and b.x < a.x + a_def.width
                    if overlapping then
                        if a.x <= b.x then
                            a.bounce_dir, b.bounce_dir = -1, 1
                        else
                            a.bounce_dir, b.bounce_dir = 1, -1
                        end
                    end
                end
            end
        end
    end
end

function Boss.update(dt, game_over, player, on_player_hit, spawn_projectile, on_encounter_end, on_type_exit, spawn_mine)
    if not Boss.active or game_over or Boss.is_paused then return end

    local instances = Boss.instances

    for i = #instances, 1, -1 do
        local instance = instances[i]
        local type_def = BOSS_TYPES[instance.type_id]

        Boss.update_instance(instance, type_def, dt, player, on_player_hit, spawn_projectile, on_type_exit, spawn_mine)

        if instance.remove then
            table.remove(instances, i)
        end
    end

    resolve_bouncer_collisions(instances)

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
        -- 1 for every type except the phantom mid-blink
        local alpha = instance.alpha or 1

        love.graphics.setColor(type_def.color_fill[1], type_def.color_fill[2], type_def.color_fill[3], alpha)
        love.graphics.rectangle("fill", instance.x, instance.y, type_def.width, type_def.height, 10, 10)

        love.graphics.setColor(type_def.color_core[1], type_def.color_core[2], type_def.color_core[3], alpha)
        love.graphics.rectangle("fill",
            instance.x + type_def.width * 0.16, instance.y + type_def.height * 0.25,
            type_def.width * 0.68, type_def.height * 0.5, 6, 6)

        -- per-type overlay (laser beam, charger warning column) -- each type
        -- decides for itself whether its own phase warrants drawing anything
        if type_def.draw_extra then
            type_def.draw_extra(instance, type_def)
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
end

-- returns the rect the player is confined to this frame as min_x, min_y,
-- max_x, max_y -- the full screen unless a live encounter narrows it. Two
-- kinds of restriction feed in: a static `player_min_y` on the type_def
-- (sentinel/homing/splitter/splitter_clone, walling off the top of the
-- screen so they can't be camped above) and the warden's arena_* fields,
-- which shrink all the way in over its encounter.
--
-- Only counts instances in "hover" -- during enter/exit the boss isn't
-- actually threatening that space yet/anymore, so there's no reason to keep
-- the walls up for those brief transitions. Restrictions from multiple
-- instances combine to the tightest of each edge rather than first-wins.
function Boss.get_player_bounds()
    local min_x, min_y = 0, 0
    local max_x, max_y = love.graphics.getWidth(), love.graphics.getHeight()

    for _, instance in ipairs(Boss.instances) do
        if instance.phase == "hover" then
            local type_def = BOSS_TYPES[instance.type_id]

            if type_def.player_min_y then
                min_y = math.max(min_y, type_def.player_min_y)
            end

            if instance.arena_min_x then
                min_x = math.max(min_x, instance.arena_min_x)
                max_x = math.min(max_x, instance.arena_max_x)
                min_y = math.max(min_y, instance.arena_min_y)
            end
        end
    end

    return min_x, min_y, max_x, max_y
end

-- "type:phase" per live instance, plus whatever sub-state that type reports
-- via its optional `debug_state` -- the generic phase sits at "hover" for a
-- whole encounter, which hides the state machine most types actually run on
function Boss.debug_summary()
    if #Boss.instances == 0 then return "(none)" end

    local parts = {}
    for _, instance in ipairs(Boss.instances) do
        local type_def = BOSS_TYPES[instance.type_id]
        local part = instance.type_id .. ":" .. instance.phase

        if type_def.debug_state then
            local detail = type_def.debug_state(instance)
            if detail then part = part .. "/" .. detail end
        end

        table.insert(parts, part)
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
