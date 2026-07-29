-- Where a boss is on each hover frame. A type picks one of these via its
-- `movement` field in src/boss/types.lua; leaving it out gives the sine patrol.
--
-- This started as an if/elseif chain on is_orbiter/is_bouncer inside the
-- engine, which stopped scaling the moment charger and phantom needed their own
-- multi-phase motion. The is_* flags still exist, but only for things that
-- aren't movement: spawn placement, the screen-edge clamp, and clone-vs-clone
-- collision.
--
-- Every mode takes the same (instance, type_def, dt, player) signature even
-- where it ignores the tail arguments (hence the `_dt` / `_player` names) --
-- they're all stored in and called through the one `movement` slot
-- interchangeably, so a narrower signature would be lying about the contract.
local FXManager = require("src/fx_manager")
local Screen    = require("src/screen")
local Mathx     = require("src/mathx")
local Config    = require("src/boss/config")

local lerp      = Mathx.lerp

local Movement  = {}

-- ---------------------------------------------------------------------------
-- patrol: a sine sweep across patrol_amplitude. amplitude 0 gives "stationary"
-- for free, which is why there's no separate stationary mode.
--
-- Watch out: amplitude must be large enough to actually reach both screen edges
-- from the boss's spawn x, or a strip down each side is permanently safe no
-- matter what else the type does. That was a real bug in three types at once.
-- ---------------------------------------------------------------------------
function Movement.patrol(instance, type_def, _dt, _player)
    instance.x = instance.base_x + math.sin(instance.age * type_def.patrol_speed) * type_def.patrol_amplitude
end

-- ---------------------------------------------------------------------------
-- orbit: a circle around a fixed arena point. The engine's spawn and enter
-- phase both special-case orbiters to land exactly where this formula puts them
-- at age 0 -- otherwise hover starts with a visible jump from the generic entry
-- point to wherever the orbit math first evaluates to.
-- ---------------------------------------------------------------------------
function Movement.orbit(instance, type_def, _dt, _player)
    local center_x = Screen.WIDTH / 2
    instance.x = center_x + math.cos(instance.age * type_def.orbit_speed) * type_def.orbit_radius -
        type_def.width / 2
    instance.y = type_def.orbit_center_y + math.sin(instance.age * type_def.orbit_speed) * type_def.orbit_radius -
        type_def.height / 2
end

-- ---------------------------------------------------------------------------
-- bounce: a straight line at a constant speed. The engine's edge clamp and its
-- clone-vs-clone check are what actually reverse `bounce_dir`.
--
-- On its own that's a metronome -- once you've read which way a clone is going,
-- its whole future is known, which is what made the split phase dull. So a
-- clone periodically jumps somewhere else along its row and re-rolls direction
-- on landing. Opt-in via reposition_interval_min, so "bounce" itself stays a
-- plain movement mode.
-- ---------------------------------------------------------------------------

-- how far from the player a repositioned clone must land -- same reasoning as
-- the phantom's blink distance: a jump landing on top of someone is an
-- unreactable hit rather than a mechanic
local BOUNCER_MIN_PLAYER_DISTANCE = 150
local BOUNCER_EDGE_MARGIN         = 36

local function roll_reposition_timer(type_def)
    return type_def.reposition_interval_min +
        love.math.random() * (type_def.reposition_interval_max - type_def.reposition_interval_min)
end

function Movement.reposition_bouncer(instance, type_def, player)
    instance.reposition_timer = roll_reposition_timer(type_def)

    local player_cx = player.center()
    local max_x = Screen.WIDTH - type_def.width - BOUNCER_EDGE_MARGIN
    local x = instance.x

    for _ = 1, 8 do
        local try = love.math.random(BOUNCER_EDGE_MARGIN, max_x)
        if math.abs((try + type_def.width / 2) - player_cx) >= BOUNCER_MIN_PLAYER_DISTANCE then
            x = try
            break
        end
    end

    local color = type_def.color_fill
    local cy = instance.y + type_def.height / 2
    -- a ring at both ends, so the jump reads as "it left there, it's here now"
    -- rather than the clone appearing to teleport for no reason
    FXManager.spawn_ring(instance.x + type_def.width / 2, cy, color[1], color[2], color[3], 8, 45, 200)
    instance.x = x
    FXManager.spawn_ring(x + type_def.width / 2, cy, color[1], color[2], color[3], 8, 45, 200)

    instance.bounce_dir = (love.math.random() < 0.5) and -1 or 1
end

function Movement.bounce(instance, type_def, dt, player)
    if type_def.reposition_interval_min then
        -- seeded with a full interval on the first frame rather than starting at
        -- zero: a fresh clone must keep the placement spawn_split_clones
        -- deliberately gave it (guaranteed clearance to move outward) for a
        -- cycle, instead of teleporting away before it has visibly split
        instance.reposition_timer = (instance.reposition_timer or roll_reposition_timer(type_def)) - dt
        if instance.reposition_timer <= 0 then
            Movement.reposition_bouncer(instance, type_def, player)
        end
    end

    instance.x = instance.x + instance.bounce_dir * type_def.bounce_speed * dt
end

-- ---------------------------------------------------------------------------
-- charge: line up over the player, telegraph the column it's about to fall
-- through, slam to the floor, climb back up, repeat. The body is the whole
-- attack -- this type fires nothing -- so it's the one encounter where standing
-- still is what kills you and dash-phasing through the boss is the answer.
-- ---------------------------------------------------------------------------

-- 0 at the start of the encounter, 1 at the end. Every timing below is lerped
-- against it, so the cycle winds up as the fight goes on: early slams stay
-- readable enough to learn the pattern on, late ones give so little warning
-- that you have to commit to moving before the telegraph even appears. That's
-- the fix for it being too predictable at a fixed rhythm.
--
-- Exported because the charger's debug_state displays it as a percentage.
function Movement.charge_aggression(instance, type_def)
    return math.min(instance.hover_timer / Config.encounter_duration(type_def), 1)
end

-- The charger may only leave from "aim" -- the part of its cycle where it's
-- just hovering and tracking, having committed to nothing.
--
-- On the shared time budget alone it left the instant the timer expired, which
-- could be mid-telegraph (the warning column is up, promising a slam that then
-- never comes) or mid-slam (it vanishes on the way down). Both read as the
-- boss glitching out rather than leaving. Finishing the cycle first costs at
-- most a couple of extra seconds, the same way the laser runs slightly long to
-- finish its last sweep.
function Movement.charge_is_encounter_done(instance, type_def)
    return instance.hover_timer >= Config.encounter_duration(type_def)
        and instance.charge_state == "aim"
end

function Movement.charge(instance, type_def, dt, player)
    instance.charge_timer = instance.charge_timer + dt

    local aggression = Movement.charge_aggression(instance, type_def)
    local aim_duration = lerp(type_def.aim_duration, type_def.aim_duration * type_def.late_aim_scale, aggression)
    local telegraph_duration = lerp(type_def.telegraph_duration,
        type_def.telegraph_duration * type_def.late_telegraph_scale, aggression)
    local track_speed = lerp(type_def.track_speed, type_def.track_speed * type_def.late_speed_scale, aggression)
    local slam_speed = lerp(type_def.slam_speed, type_def.slam_speed * type_def.late_speed_scale, aggression)
    local retreat_speed = lerp(type_def.retreat_speed, type_def.retreat_speed * type_def.late_speed_scale, aggression)

    if instance.charge_state == "aim" then
        -- track the player's column, but capped -- it closes the gap rather
        -- than teleporting onto them, so running is a real option
        local player_cx = player.center()
        local target_x = player_cx - type_def.width / 2
        local delta = target_x - instance.x
        local step = track_speed * dt
        if math.abs(delta) <= step then
            instance.x = target_x
        else
            instance.x = instance.x + (delta > 0 and step or -step)
        end

        if instance.charge_timer >= aim_duration then
            instance.charge_state = "telegraph"
            instance.charge_timer = 0
        end
    elseif instance.charge_state == "telegraph" then
        -- deliberately motionless: the warning column below it is only honest
        -- if the boss can't still be sliding sideways while it shows
        if instance.charge_timer >= telegraph_duration then
            instance.charge_state = "slam"
            instance.charge_timer = 0
        end
    elseif instance.charge_state == "slam" then
        instance.y = instance.y + slam_speed * dt
        local floor_y = Screen.HEIGHT - type_def.height - 10
        if instance.y >= floor_y then
            instance.y = floor_y
            instance.charge_state = "retreat"
            instance.charge_timer = 0
        end
    elseif instance.charge_state == "retreat" then
        instance.y = instance.y - retreat_speed * dt
        if instance.y <= Config.HOVER_Y then
            instance.y = Config.HOVER_Y
            instance.charge_state = "aim"
            instance.charge_timer = 0
        end
    end
end

-- ---------------------------------------------------------------------------
-- blink: fade out, reappear somewhere else, fire on arrival. While it is
-- anything but fully visible it sets `intangible`, which switches off both its
-- collision and its firing -- a half-faded boss you can still walk into (or
-- that shoots you from nowhere) reads as a bug, not a mechanic.
-- ---------------------------------------------------------------------------

-- somewhere in the upper arena, at least this far from the player --
-- materializing on top of them would be an unreactable hit
local BLINK_MIN_PLAYER_DISTANCE = 150
local BLINK_EDGE_MARGIN         = 48
local BLINK_MIN_Y               = 54
local BLINK_MAX_Y               = 297

function Movement.pick_blink_position(type_def, player)
    local max_x = Screen.WIDTH - type_def.width - BLINK_EDGE_MARGIN
    local player_cx, player_cy = player.center()
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

    -- every try landed too close (the player is mid-arena) -- take the last
    -- roll rather than looping forever
    return x, y
end

function Movement.blink(instance, type_def, dt, player)
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
            instance.x, instance.y = Movement.pick_blink_position(type_def, player)
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

return Movement
