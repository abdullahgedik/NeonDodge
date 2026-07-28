-- The laser boss's beam, as a self-contained subsystem: its own constants, its
-- own update/draw/collision, and its own encounter-exit rule.
--
-- It lives in its own file for a concrete reason. The beam is the one type whose
-- behavior the generic engine couldn't express, so the engine used to carry
-- three `if type_def.is_laser` special cases (a replacement update step, an
-- extra collision check, and a different exit condition) while the laser's own
-- drawing and constants sat at the far end of the file from the type that used
-- them. Pulled out here and plugged in through the same optional hooks every
-- other type uses, the engine has no idea the laser is special.
--
-- The beam is a full-width OR full-height band that sweeps edge-to-edge across
-- the WHOLE screen each cycle, on a randomly chosen axis and direction. Earlier
-- versions pivoted from a fixed point, then slid a short distance -- both left
-- some region of the arena permanently safe. Edge-to-edge across a random axis
-- doesn't.
local Screen  = require("src/screen")
local Config  = require("src/boss/config")
local Attacks = require("src/boss/attacks")

local Laser   = {}

local TELEGRAPH_DURATION = 0.9
local FIRE_DURATION      = 2.8
local COOLDOWN_DURATION  = 0.6  -- short gap between sweeps: the beam cycles fast
local THICKNESS          = 18
local EDGE_MARGIN        = 30   -- keep the sweep just inside the absolute screen edges
local SHOT_INTERVAL      = 0.75 -- the aimed shot, independent of the beam cycle

-- The encounter ends once exactly this many sweeps finish. Stays at 4 on
-- purpose: with the cooldown above, 5 pushed the encounter to ~23s against ~16s
-- for every other type, which reads as dragging rather than intense. Raise it
-- only if the laser is meant to be a longer set piece than the rest.
local MAX_SWEEPS         = 4

-- Runs in place of the generic fire step (the laser type has no `fire` field,
-- so nothing double-fires). Two independent things tick here: the beam's
-- cooldown -> telegraph -> firing cycle, and a straight aimed shot on its own
-- faster cadence so shots don't have to wait on the beam.
function Laser.update(instance, type_def, dt, player, hooks)
    instance.laser_timer = instance.laser_timer + dt

    instance.shot_timer = instance.shot_timer + dt
    if instance.shot_timer >= SHOT_INTERVAL then
        instance.shot_timer = 0
        Attacks.aimed_shot(instance, type_def, player, hooks.spawn_projectile, { ring_color = { 1, 0.7, 0.2 } })
    end

    if instance.laser_state == "cooldown" then
        if instance.laser_timer >= COOLDOWN_DURATION then
            instance.laser_state = "telegraph"
            instance.laser_timer = 0

            -- pick the axis, then the direction along it -- both random, so no
            -- row, column or direction is ever the safe one to memorize
            instance.laser_axis = (love.math.random() < 0.5) and "horizontal" or "vertical"
            local span = (instance.laser_axis == "horizontal") and Screen.HEIGHT or Screen.WIDTH

            if love.math.random() < 0.5 then
                instance.laser_row_start = EDGE_MARGIN
                instance.laser_row_end = span - EDGE_MARGIN
            else
                instance.laser_row_start = span - EDGE_MARGIN
                instance.laser_row_end = EDGE_MARGIN
            end

            instance.laser_row_y = instance.laser_row_start
        end
    elseif instance.laser_state == "telegraph" then
        if instance.laser_timer >= TELEGRAPH_DURATION then
            instance.laser_state = "firing"
            instance.laser_timer = 0
        end
    elseif instance.laser_state == "firing" then
        local t = math.min(instance.laser_timer / FIRE_DURATION, 1)
        instance.laser_row_y = instance.laser_row_start +
            (instance.laser_row_end - instance.laser_row_start) * t

        if instance.laser_timer >= FIRE_DURATION then
            instance.laser_state = "cooldown"
            instance.laser_timer = 0
            instance.laser_sweep_count = instance.laser_sweep_count + 1
        end
    end
end

-- A 1-D band test rather than either of src/collision.lua's two shapes: the
-- beam always spans the full screen on one axis, so only the player's position
-- on the *other* axis matters. Dash phase-through still applies, same as any
-- hazard.
function Laser.check_collision(instance, player, on_player_hit)
    if instance.laser_state ~= "firing" or instance.hit_cooldown > 0 or player.is_dashing then return end

    local half_band = THICKNESS / 2 + player.size / 2
    local player_cx, player_cy = player.center()
    local player_pos = (instance.laser_axis == "horizontal") and player_cy or player_cx

    if math.abs(player_pos - instance.laser_row_y) < half_band then
        instance.hit_cooldown = Config.HIT_COOLDOWN
        on_player_hit()
    end
end

-- Exits on completed sweeps, not the shared time budget. The two never lined
-- up, so on a timer the boss could leave mid-telegraph or cut its last sweep
-- off partway through.
function Laser.is_encounter_done(instance)
    return instance.laser_sweep_count >= MAX_SWEEPS
end

function Laser.draw(instance)
    if instance.phase ~= "hover" then return end

    local width, height = Screen.WIDTH, Screen.HEIGHT
    local horizontal = instance.laser_axis == "horizontal"

    if instance.laser_state == "telegraph" then
        -- only the start line is shown: the sweep always ends at the opposite
        -- screen edge, so a second line for the far end was noise, not info
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
            love.graphics.rectangle("fill", 0, instance.laser_row_y - THICKNESS / 2, width, THICKNESS)
        else
            love.graphics.rectangle("fill", instance.laser_row_y - THICKNESS / 2, 0, THICKNESS, height)
        end
    end
end

function Laser.debug_state(instance)
    return string.format("%s %d/%d", instance.laser_state, instance.laser_sweep_count, MAX_SWEEPS)
end

return Laser
