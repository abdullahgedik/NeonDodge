-- The boss roster. One entry per type, holding every number and every bit of
-- behavior that makes that type itself -- so tuning a boss, or adding one,
-- happens here and (almost always) nowhere else.
--
-- The engine in src/boss.lua reads these fields. All are optional except
-- width/height/colors:
--
--   MOVEMENT
--     movement            where it is each hover frame. Defaults to the sine
--                         patrol; see src/boss/movement.lua for the others.
--     patrol_amplitude    for the default patrol. MUST be big enough to reach
--     patrol_speed        both screen edges from the spawn x, or a strip down
--                         each side is permanently safe.
--     is_orbiter          affects spawn placement + the enter-phase target y
--     is_bouncer          affects the edge clamp + clone-vs-clone collision
--
--   ATTACKS
--     fire                (instance, type_def, spawn_projectile, player, spawn_mine)
--     fire_interval       seconds between volleys
--     fire_second         a follow-up volley, armed by setting
--                         instance.pending_second_burst. It can re-arm itself
--                         to chain -- that's how turret/phantom get 2-3 bursts.
--
--   RESTRICTIONS
--     player_min_y        walls off the top of the screen for this encounter.
--                         Needed by any type that only threatens downward,
--                         otherwise standing above it is completely safe.
--
--   HOOKS (each optional; the engine skips what isn't set)
--     update_extra        extra per-frame work, e.g. the laser beam cycle or
--                         the warden's closing arena
--     extra_collision     an extra hit test beyond the body rect
--     is_encounter_done   override the "hover_timer >= ENCOUNTER_DURATION" exit
--     draw_extra          per-type overlay drawn on top of the body
--     debug_state         one line of sub-state for the F1 overlay
--
--   SPLITTING
--     is_splitter         splits into clones at split_time
--
-- See README.md's "Add a boss type" for the walkthrough.
local FXManager = require("src/fx_manager")
local Screen    = require("src/screen")
local Mathx     = require("src/mathx")
local Config    = require("src/boss/config")
local Attacks   = require("src/boss/attacks")
local Movement  = require("src/boss/movement")
local Laser     = require("src/boss/laser")

-- warden only: eases the legal play area from the full screen down to a
-- centered arena_final_width column whose top edge sits below the boss, over
-- arena_close_ratio of the encounter, then holds. Written onto the instance
-- (not the type_def) because Boss.get_player_bounds reads whatever the live
-- instances currently want, and two wardens would each have their own.
local function update_warden_arena(instance, type_def)
    local width = Screen.WIDTH
    local t = math.min(instance.hover_timer / (Config.ENCOUNTER_DURATION * type_def.arena_close_ratio), 1)
    -- ease-out so most of the squeeze lands early and the last stretch is a
    -- slow tighten rather than a sudden clamp
    local eased = Mathx.ease_out(t)

    local half = (width - (width - type_def.arena_final_width) * eased) / 2
    instance.arena_min_x = width / 2 - half
    instance.arena_max_x = width / 2 + half
    instance.arena_min_y = type_def.arena_final_min_y * eased
end

local Types = {}

Types.BOSS_TYPES = {
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
        fire_interval = 0.95,
        -- chance that a volley is followed by a second one a beat later,
        -- rotated half a shot so it threads the first fan's gaps. Random
        -- rather than every time on purpose: a fixed double is just a denser
        -- fan you learn once, but a coin-flip means you can't commit to
        -- stepping into the gap the instant the first volley passes
        double_shot_chance = 0.35,
        double_shot_delay = 0.28,
        -- walls off the top of the screen (see Boss.get_player_bounds): a
        -- single tracked shot every couple seconds was still trivially
        -- dodgeable from a static camping spot, so this pairs a bigger body
        -- (harder to squeeze past during patrol) with denying the player the
        -- "stand above the boss and ignore everything" position outright
        player_min_y = 155,
        fire = function(instance, type_def, spawn_projectile)
            Attacks.spread(instance, type_def, spawn_projectile,
                { count = 7, spread_angle = math.rad(50), ring_color = { 1, 0.2, 0.6 } })

            if love.math.random() < type_def.double_shot_chance then
                instance.pending_second_burst = type_def.double_shot_delay
            end
        end,
        fire_second = function(instance, type_def, spawn_projectile)
            -- half the 16.7-degree gap between shots in a 7-wide 50-degree
            -- fan, so this volley lands exactly between the last one's shots
            Attacks.spread(instance, type_def, spawn_projectile,
                {
                    count = 7,
                    spread_angle = math.rad(50),
                    rotation_offset = math.rad(8.3),
                    ring_color = { 1, 0.4, 0.75 },
                })
        end,
    },
    homing = {
        width = 80,
        height = 55,
        color_fill = { 0.15, 0.9, 0.45 },
        color_core = { 0.6, 1, 0.75 },
        patrol_amplitude = 150,
        patrol_speed = 0.5,
        -- its shots now detonate in a blast when their lifetime runs out (see
        -- src/projectile.lua), so a denser stream also means the arena is
        -- steadily seeded with delayed explosions rather than just chased
        fire_interval = 1.45,
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
    -- the beam is its own subsystem (src/boss/laser.lua) plugged in through the
    -- generic hooks: it replaces the fire step, adds its own collision test,
    -- and exits on a completed-sweep count instead of the shared timer. Note
    -- there is no `fire` field, so nothing double-fires.
    laser = {
        width = 100,
        height = 50,
        color_fill = { 1, 0.55, 0.05 },
        color_core = { 1, 0.8, 0.4 },
        patrol_amplitude = 40,
        patrol_speed = 0.3,
        update_extra = Laser.update,
        extra_collision = Laser.check_collision,
        is_encounter_done = Laser.is_encounter_done,
        draw_extra = Laser.draw,
        debug_state = Laser.debug_state,
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
            Attacks.spread(instance, type_def, spawn_projectile,
                { count = 8, spread_angle = math.rad(45), ring_color = { 0.75, 1, 0.2 } })
        end,
        is_splitter = true,
        split_time = 6,
    },
    -- spawned by splitter's split, not part of the normal boss sequence.
    -- unlike every other type, clones don't sine-patrol -- they ping-pong in
    -- a straight line, reversing off the screen's left/right edges and off
    -- each other (see resolve_bouncer_collisions in the engine). Sine-patrolling
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
        movement = Movement.bounce,
        bounce_speed = 230,
        fire_interval = 1.15,
        player_min_y = 110,
        -- opt-in for Movement.bounce's reposition step -- a straight-line
        -- ping-pong is fully predictable once read, so each clone jumps along
        -- its row on this cadence and re-rolls direction, which also stops the
        -- pair from settling into a mirrored rhythm off each other
        reposition_interval_min = 1.5,
        reposition_interval_max = 2.9,
        double_shot_chance = 0.22,
        double_shot_delay = 0.24,
        fire = function(instance, type_def, spawn_projectile)
            Attacks.spread(instance, type_def, spawn_projectile,
                { count = 6, spread_angle = math.rad(35), ring_color = { 0.75, 1, 0.2 } })

            -- deliberately a low chance: with two clones firing independently
            -- this lands often enough to keep you honest without the pair
            -- routinely doubling at once
            if love.math.random() < type_def.double_shot_chance then
                instance.pending_second_burst = type_def.double_shot_delay
            end
        end,
        fire_second = function(instance, type_def, spawn_projectile)
            Attacks.spread(instance, type_def, spawn_projectile,
                {
                    count = 6,
                    spread_angle = math.rad(35),
                    rotation_offset = math.rad(7),
                    ring_color = { 0.9, 1, 0.5 },
                })
        end,
    },
    turret = {
        width = 110,
        height = 70,
        color_fill = { 0.15, 0.35, 0.95 },
        color_core = { 0.5, 0.65, 1 },
        is_orbiter = true,
        movement = Movement.orbit,
        orbit_radius = 170,
        orbit_center_y = 260,
        orbit_speed = 0.6,
        fire_interval = 1.5,
        -- Rings per volley alternate 2, 3, 2, 3... Each ring in a volley is
        -- rotated another half-step so they interleave into one denser
        -- lattice rather than repeating, and every volley carries the spiral
        -- further round. The alternating count is what makes it readable but
        -- not memorizable: you can count the rings as they come, but "how many
        -- more after this one" changes every volley, so the safe moment to
        -- cross the ring gap moves with it.
        burst_gap = 0.18,
        burst_counts = { 2, 3 },
        fire = function(instance, type_def, spawn_projectile)
            -- step through 2, 3, 2, 3... one volley at a time
            local cycle = (instance.turret_cycle or 0) % #type_def.burst_counts + 1
            instance.turret_cycle = cycle
            instance.turret_bursts_left = type_def.burst_counts[cycle] - 1

            Attacks.turret_ring(instance, type_def, spawn_projectile)
        end,
        fire_second = function(instance, type_def, spawn_projectile)
            Attacks.turret_ring(instance, type_def, spawn_projectile)
        end,
        -- how many rings are still queued in the current volley, which is the
        -- whole point of the 2/3 cycle and invisible from the generic phase
        debug_state = function(instance)
            return "rings +" .. (instance.turret_bursts_left or 0)
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
        movement = Movement.charge,
        -- without this the whole encounter is dodgeable by standing above it:
        -- it only ever slams *downward*, so anything higher than its hover
        -- line is a position it structurally cannot threaten
        player_min_y = 175,
        -- opening values; Movement.charge lerps all five toward the late_*
        -- scales below as the encounter runs, so the last slams come with
        -- roughly a third of the aim time and half the telegraph of the first
        track_speed = 250,
        aim_duration = 1.1,
        telegraph_duration = 0.55,
        slam_speed = 1250,
        retreat_speed = 430,
        late_aim_scale = 0.35,
        late_telegraph_scale = 0.5,
        late_speed_scale = 1.55,
        draw_extra = function(instance, type_def)
            if instance.phase ~= "hover" or instance.charge_state ~= "telegraph" then return end

            -- the column it's committed to falling through, from its own
            -- bottom edge all the way to the floor
            local height = Screen.HEIGHT
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
        -- the ramp is the whole point of this type now, and it's invisible
        -- from the state name alone -- show how far wound up it is
        debug_state = function(instance)
            return string.format("%s %d%%", instance.charge_state,
                math.floor(Movement.charge_aggression(instance) * 100))
        end,
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
        -- the shot volley is deliberately offset from the bombs rather than
        -- simultaneous: mines are a "be elsewhere in a moment" threat and
        -- projectiles are a "move now" one, and landing both on the same beat
        -- just reads as one confusing wall. Staggered, they're two problems
        -- that overlap -- you dodge the spread into ground the bombs already
        -- claimed, which is the point of giving it a gun at all
        shot_delay = 0.5,
        fire = function(instance, type_def, spawn_projectile, player, spawn_mine)
            local width = Screen.WIDTH
            local min_x, max_x = type_def.bomb_edge_margin, width - type_def.bomb_edge_margin

            if spawn_mine then
                local player_cx, player_cy = player.center()
                local aimed_x = math.max(min_x, math.min(player_cx, max_x))
                spawn_mine(aimed_x, math.max(type_def.bomb_min_y, math.min(player_cy, type_def.bomb_max_y)))
                spawn_mine(love.math.random(min_x, max_x), love.math.random(type_def.bomb_min_y, type_def.bomb_max_y))
            end

            local cx = instance.x + type_def.width / 2
            local cy = instance.y + type_def.height
            FXManager.spawn_ring(cx, cy, 1, 0.75, 0.2, 10, 45, 200)

            instance.pending_second_burst = type_def.shot_delay
        end,
        fire_second = function(instance, type_def, spawn_projectile)
            Attacks.spread(instance, type_def, spawn_projectile,
                { count = 5, spread_angle = math.rad(42), ring_color = { 1, 0.85, 0.3 } })
        end,
    },
    -- squeezes the legal play area inward over the encounter (see
    -- update_warden_arena above) while lobbing a slow spread. Generalizes the
    -- existing player_min_y wall from one edge to all four -- the shots
    -- barely matter on their own, the point is that the room to dodge them
    -- keeps shrinking
    warden = {
        width = 115,
        height = 65,
        color_fill = { 0.5, 0.45, 0.75 },
        color_core = { 0.8, 0.75, 1 },
        patrol_amplitude = 130,
        patrol_speed = 0.4,
        fire_interval = 1.15,
        update_extra = update_warden_arena,
        -- The arena it closes down to, and how much of the encounter it takes
        -- to get there (held at full squeeze for the remainder). Tightened
        -- from 380 wide / 0.8 ratio: the squeeze is the entire identity of
        -- this type and at the old numbers it finished barely narrower than
        -- the space a Sentinel already denies. These three are the knobs to
        -- move for the rework -- the shots are incidental by design.
        arena_final_width = 320,
        arena_final_min_y = 235,
        arena_close_ratio = 0.7,
        fire = function(instance, type_def, spawn_projectile)
            Attacks.spread(instance, type_def, spawn_projectile,
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
                round10(Screen.HEIGHT - instance.arena_min_y))
        end,
    },
    -- no readable patrol at all: it blinks around the arena and fires the
    -- instant it lands, so there's no corner you can pre-plan as safe
    phantom = {
        width = 85,
        height = 55,
        color_fill = { 0.75, 0.75, 0.82 },
        color_core = { 1, 1, 1 },
        movement = Movement.blink,
        visible_duration = 1.5,
        fade_duration = 0.35,
        fire_interval = 0.65,
        -- fires a full ring rather than a downward fan: it materializes at an
        -- unpredictable spot, so a directional attack would be dodgeable just
        -- by staying above wherever it happened to land. A ring makes its
        -- position the threat, which is the whole point of the type, and
        -- means it needs no player_min_y wall to stay honest.
        --
        -- Each volley is 2-3 bursts of a 4-shot ring, alternating between
        -- axis-aligned (+) and diagonal (X) -- see Attacks.phantom_ring.
        ring_count = 4,
        burst_gap = 0.22,
        min_bursts = 2,
        max_bursts = 3,
        fire = function(instance, type_def, spawn_projectile)
            instance.phantom_bursts_left = love.math.random(type_def.min_bursts, type_def.max_bursts) - 1
            instance.phantom_diagonal = false
            Attacks.phantom_ring(instance, type_def, spawn_projectile)
        end,
        -- re-arms itself while bursts remain, so one volley chains into a
        -- short burst sequence off the same generic pending_second_burst hook
        fire_second = function(instance, type_def, spawn_projectile)
            Attacks.phantom_ring(instance, type_def, spawn_projectile)
        end,
        -- intangible is the non-obvious half of a blink (collision AND firing
        -- both off), so surface it rather than just the visual state
        debug_state = function(instance)
            return instance.blink_state .. (instance.intangible and " (intangible)" or "")
                .. ((instance.phantom_bursts_left or 0) > 0 and (" +" .. instance.phantom_bursts_left) or "")
        end,
    },
}

-- The fixed cycle order encounters run in, repeating once exhausted. Lives
-- with the roster rather than in main.lua because it's a property of the boss
-- lineup, not of wave scheduling -- main.lua reads it for the cadence and Debug
-- reads it for its spawn hotkeys, so adding a type means touching only this
-- folder. The four newer types are interleaved rather than appended: on the end
-- they'd sit behind five encounters (wave 36+) and never be seen in a run.
Types.SEQUENCE = {
    "sentinel", "charger", "homing", "bomber", "laser", "phantom", "splitter", "warden", "turret"
}

return Types
