-- The boss ENGINE: the part that's the same for all nine types. It runs the
-- enter -> hover -> exit lifecycle, calls whatever hooks a type provides, does
-- body collision, and reports what the player's bounds should be.
--
-- Nothing type-specific lives here. That's the whole point of the split:
--
--   src/boss/config.lua     timings and geometry shared by all of the below
--   src/boss/types.lua      the roster -- every per-type number and behavior
--   src/boss/movement.lua   the movement modes
--   src/boss/attacks.lua    how bosses shoot
--   src/boss/laser.lua      the laser's beam, as a self-contained subsystem
--
-- To tune or add a boss you want src/boss/types.lua, not this file.
--
-- Called from outside:
--   Boss.SEQUENCE            read by main.lua (cadence) and Debug (hotkeys)
--   Boss.load / reset / pause / resume    lifecycle, from main.lua's lists
--   Boss.spawn(type_id)      start an encounter
--   Boss.update(dt, game_over, player, hooks)
--   Boss.draw()
--   Boss.active              boolean, true while an encounter is running
--   Boss.get_player_bounds() the rect the player is confined to right now
--   Boss.debug_summary()     one line for the F1 overlay
local Collision  = require("src/collision")
local FXManager  = require("src/fx_manager")
local Screen     = require("src/screen")
local Config     = require("src/boss/config")
local Movement   = require("src/boss/movement")
local Shapes     = require("src/boss/shapes")
local Types      = require("src/boss/types")

local Boss       = {}

local BOSS_TYPES = Types.BOSS_TYPES

-- re-exported so main.lua and Debug don't need to know about the subfolder
Boss.SEQUENCE    = Types.SEQUENCE

-- A fresh instance carries the state fields for *every* type, not just its own
-- (a sentinel has laser_state, charge_state and blink_state sitting unused).
-- That's deliberate: one flat shape means the engine never has to ask "does
-- this instance have that field" before touching it, and at one or two live
-- instances the waste is irrelevant. The grouping below is the map of which
-- type actually reads which.
local function new_instance(type_id, x, y)
    return {
        -- shared by every type
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

        -- laser
        laser_state = "cooldown",
        laser_timer = 0,
        laser_axis = "horizontal",
        laser_row_y = 0,
        laser_row_start = 0,
        laser_row_end = 0,
        laser_sweep_count = 0,
        shot_timer = 0,

        -- charger
        charge_state = "aim",
        charge_timer = 0,

        -- bouncer
        bouncer_state = "locking",
        bouncer_lock_timer = 0,
        bouncer_launched = false,
        bouncer_dir_x = 0,
        bouncer_dir_y = 0,
        bouncer_speed = 0,
        bouncer_bounces = 0,
        bouncer_target_x = x,
        bouncer_target_y = y,

        -- phantom: fades via alpha and switches off both its collision and its
        -- firing while intangible; every other type leaves these two alone
        blink_state = "visible",
        blink_timer = 0,
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
    local width = Screen.WIDTH
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
    local offset = 60
    local buffer = 30 -- keep both split points comfortably clear of the screen edges
    local width = Screen.WIDTH
    -- hunter and sentry share the same footprint (see BOSS_TYPES) -- same
    -- threat size at the moment of the split, different tactics after it
    local clone_width = BOSS_TYPES.splitter_hunter.width

    local min_center = offset + buffer
    local max_center = width - clone_width - offset - buffer
    local center_x = math.max(min_center, math.min(instance.x, max_center))

    -- which side gets which role is random every split, so the pairing can't
    -- be memorized from one encounter to the next
    local roles = (love.math.random() < 0.5)
        and { "splitter_hunter", "splitter_sentry" }
        or { "splitter_sentry", "splitter_hunter" }

    local clone_a = new_instance(roles[1], center_x - offset, instance.y)
    local clone_b = new_instance(roles[2], center_x + offset, instance.y)

    for _, clone in ipairs({ clone_a, clone_b }) do
        clone.phase = "hover"
        clone.hover_timer = instance.hover_timer
        table.insert(Boss.instances, clone)
    end

    -- a burst at the moment it happens, so the split reads as an event
    -- rather than a silent substitution (one body gone, two smaller ones
    -- just there)
    local parent_def = BOSS_TYPES[instance.type_id]
    local cx = instance.x + parent_def.width / 2
    local cy = instance.y + parent_def.height / 2
    local c = parent_def.color_fill
    FXManager.spawn_ring(cx, cy, c[1], c[2], c[3], 16, 90, 260)
end

function Boss.check_instance_collision(instance, type_def, player, on_player_hit)
    -- intangible covers the phantom mid-blink: it's drawn faded but isn't
    -- really there, so walking through it must be free
    if instance.hit_cooldown > 0 or instance.intangible then return end

    -- hazard_* rather than the plain overlap test: dash phase-through applies
    -- to a boss body exactly like any other hazard
    if Collision.hazard_rect_hits_player(player, instance.x, instance.y, type_def.width, type_def.height,
            type_def.width * Config.COLLISION_PADDING_RATIO) then
        instance.hit_cooldown = Config.HIT_COOLDOWN
        on_player_hit()
    end
end

-- ---------------------------------------------------------------------------
-- One instance, one frame. The three phases are: slide in from off the top
-- (enter), do the whole encounter (hover), slide back out (exit).
-- ---------------------------------------------------------------------------
function Boss.update_instance(instance, type_def, dt, player, hooks)
    local spawn_projectile = hooks.spawn_projectile
    local spawn_mine       = hooks.spawn_mine

    instance.age = instance.age + dt
    if instance.hit_cooldown > 0 then
        instance.hit_cooldown = instance.hit_cooldown - dt
    end

    if instance.phase == "enter" then
        instance.y = instance.y + Config.ENTER_SPEED * dt
        -- orbiters must land exactly where their orbit formula starts (age=0),
        -- otherwise hover begins with an instant jump to the orbit's position
        local target_y = type_def.is_orbiter and (type_def.orbit_center_y - type_def.height / 2) or Config.HOVER_Y
        if instance.y >= target_y then
            instance.y = target_y
            instance.phase = "hover"
            instance.age = 0
            instance.fire_timer = 0
        end
    elseif instance.phase == "hover" then
        instance.hover_timer = instance.hover_timer + dt

        -- 1. move
        local movement = type_def.movement or Movement.patrol
        movement(instance, type_def, dt, player)

        -- 2. anything else this type does per-frame (the laser's beam cycle,
        --    the warden's closing arena)
        if type_def.update_extra then
            type_def.update_extra(instance, type_def, dt, player, hooks)
        end

        -- 3. shoot. `fire` is optional: the charger attacks with its body
        --    alone, and the laser does its firing from update_extra. A
        --    half-faded phantom holds its fire (see Movement.blink).
        if type_def.fire and not instance.intangible then
            instance.fire_timer = instance.fire_timer + dt
            if instance.fire_timer >= type_def.fire_interval then
                instance.fire_timer = 0
                type_def.fire(instance, type_def, spawn_projectile, player, spawn_mine)
            end
        end

        -- 4. a queued follow-up volley. Cleared BEFORE fire_second runs, which
        --    is what lets fire_second re-arm it and chain into a burst
        --    sequence -- turret and phantom both rely on that.
        if instance.pending_second_burst then
            instance.pending_second_burst = instance.pending_second_burst - dt
            if instance.pending_second_burst <= 0 then
                instance.pending_second_burst = nil
                if type_def.fire_second then
                    type_def.fire_second(instance, type_def, spawn_projectile, player, spawn_mine)
                end
            end
        end

        -- 5. split (splitter only) -- replaces this instance with two clones
        if type_def.is_splitter and not instance.split_done and instance.hover_timer >= type_def.split_time then
            instance.split_done = true
            Boss.spawn_split_clones(instance)
            instance.remove = true
            return
        end

        -- 6. is the encounter over? Most types run on a flat time budget; a
        --    type can override that (the laser counts completed sweeps, since
        --    a timer could cut it off mid-telegraph).
        local done
        if type_def.is_encounter_done then
            done = type_def.is_encounter_done(instance, type_def)
        else
            done = instance.hover_timer >= Config.encounter_duration(type_def)
        end

        if done then
            instance.phase = "exit"
            -- lets main.lua react to a specific type leaving (e.g. clearing
            -- the homing boss's still-active shots so they don't keep
            -- chasing the player once the boss itself is already gone)
            if hooks.on_type_exit then
                hooks.on_type_exit(instance.type_id)
            end
        end
    elseif instance.phase == "exit" then
        instance.y = instance.y - Config.EXIT_SPEED * dt
        if instance.y < -type_def.height then
            instance.remove = true
            return
        end
    end

    -- keep it on screen
    local width = Screen.WIDTH
    if instance.x < 0 then
        instance.x = 0
    end
    if instance.x > width - type_def.width then
        instance.x = width - type_def.width
    end

    -- an extra hit test beyond the body rect (the laser's beam)
    if type_def.extra_collision then
        type_def.extra_collision(instance, player, hooks.on_player_hit)
    end

    Boss.check_instance_collision(instance, type_def, player, hooks.on_player_hit)
end

-- `hooks` is how the boss talks back to the rest of the game without knowing
-- anything about it -- one named table rather than five positional callbacks,
-- which was impossible to read at either the call site or the signature:
--   on_player_hit()            -- this boss just touched/hit the player
--   spawn_projectile(x, y, dir_x, dir_y, homing)
--   spawn_mine(x, y)           -- bomber only: seeds a real Mine hazard
--   on_encounter_end()         -- the last instance just left the screen
--   on_type_exit(type_id)      -- one instance started leaving
-- All are optional except on_player_hit/spawn_projectile, which every type
-- that can hit or shoot needs.
function Boss.update(dt, game_over, player, hooks)
    if not Boss.active or game_over or Boss.is_paused then return end

    local instances = Boss.instances

    -- backward, because an instance can remove itself mid-loop (a splitter
    -- replacing itself with clones, anything finishing its exit)
    for i = #instances, 1, -1 do
        local instance = instances[i]
        local type_def = BOSS_TYPES[instance.type_id]

        Boss.update_instance(instance, type_def, dt, player, hooks)

        if instance.remove then
            table.remove(instances, i)
        end
    end

    if #instances == 0 then
        Boss.active = false
        if hooks.on_encounter_end then hooks.on_encounter_end() end
    end
end

function Boss.draw()
    for _, instance in ipairs(Boss.instances) do
        local type_def = BOSS_TYPES[instance.type_id]
        -- 1 for every type except the phantom mid-blink
        local alpha = instance.alpha or 1

        -- each type has its own silhouette (see src/boss/shapes.lua) -- they
        -- all used to draw the same rounded rectangle, which made nine bosses
        -- read as one boss in nine colors
        local shape = type_def.shape or Shapes.default
        shape(instance.x, instance.y, type_def.width, type_def.height,
            type_def.color_fill, type_def.color_core, alpha)

        -- per-type overlay (laser beam, charger warning column) -- each type
        -- decides for itself whether its current phase warrants drawing anything
        if type_def.draw_extra then
            type_def.draw_extra(instance, type_def)
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
end

-- returns the rect the player is confined to this frame as min_x, min_y,
-- max_x, max_y -- the full screen unless a live encounter narrows it. Two
-- kinds of restriction feed in: a static `player_min_y` on the type_def
-- (walling off the top of the screen so a downward-only boss can't be camped
-- above) and the warden's arena_* fields, which shrink all the way in over its
-- encounter.
--
-- Only counts instances in "hover" -- during enter/exit the boss isn't
-- actually threatening that space yet/anymore, so there's no reason to keep
-- the walls up for those brief transitions. Restrictions from multiple
-- instances combine to the tightest of each edge rather than first-wins.
function Boss.get_player_bounds()
    local min_x, min_y = 0, 0
    local max_x, max_y = Screen.WIDTH, Screen.HEIGHT

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
            -- (instance, type_def), matching draw_extra -- the charger needs
            -- its type_def to work out how far its aggression ramp has wound up
            local detail = type_def.debug_state(instance, type_def)
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
