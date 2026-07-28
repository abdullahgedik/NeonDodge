-- How bosses shoot. Every type's `fire`/`fire_second` in src/boss/types.lua
-- is built out of these, so a new attack pattern is usually a new combination
-- of `spread` rather than new code.
--
-- Deliberately knows nothing about the boss engine: these take an instance and
-- a type_def, read position/size off them, and call the `spawn_projectile`
-- callback they're handed. That's what keeps this file safe to read on its own.
local FXManager = require("src/fx_manager")

local Attacks   = {}

-- Where a boss's shots come out of: horizontally centered on its body, at its
-- bottom edge. Full-circle rings use the same origin -- they'd look odd from
-- the very bottom of a tall body, but no ring-firing type is tall.
local function muzzle(instance, type_def)
    return instance.x + type_def.width / 2, instance.y + type_def.height
end

-- A burst of projectiles, either fanned across an angle or spaced evenly
-- around a full circle, plus a matching ring-shockwave FX.
--
--   count            how many shots
--   spread_angle     half-width of the fan, in radians (fan mode)
--   full_circle      true for an evenly spaced ring instead of a fan
--   rotation_offset  rotates the whole pattern. This is what lets a follow-up
--                    volley land in the *gaps* of the one before it rather
--                    than being a plain repeat -- works for fans and rings.
--   ring_color       color of the shockwave FX
function Attacks.spread(instance, type_def, spawn_projectile, opts)
    local cx, cy = muzzle(instance, type_def)
    local count = opts.count
    local rotation_offset = opts.rotation_offset or 0

    if opts.full_circle then
        for i = 1, count do
            local angle = (i - 1) / count * math.pi * 2 + rotation_offset
            spawn_projectile(cx, cy, math.sin(angle), math.cos(angle))
        end
    else
        local spread_angle = opts.spread_angle
        for i = 1, count do
            -- 0..1 across the fan; a single shot goes straight down the middle
            local t = (count == 1) and 0.5 or (i - 1) / (count - 1)
            local angle = -spread_angle + t * (2 * spread_angle) + rotation_offset
            spawn_projectile(cx, cy, math.sin(angle), math.cos(angle))
        end
    end

    local c = opts.ring_color or { 1, 1, 1 }
    FXManager.spawn_ring(cx, cy, c[1], c[2], c[3], 10, 55, 220)
end

-- A single shot aimed at wherever the player is *right now* -- computed once at
-- fire time, then flying straight (unlike a homing projectile, which keeps
-- steering).
--
-- Why this exists: any fixed angle or fan leaves some position uncovered, and a
-- fan wide enough to cover every camping spot including the corners stops being
-- a fan at all. Aiming at the player's actual position is the only version of
-- "cover everywhere" that generalizes. Only the laser still uses it -- the
-- other types that once did got the `player_min_y` wall instead, which denies
-- the camping position outright rather than trying to out-shoot it.
function Attacks.aimed_shot(instance, type_def, player, spawn_projectile, opts)
    local cx, cy = muzzle(instance, type_def)
    local player_cx, player_cy = player.center()
    local dx, dy = player_cx - cx, player_cy - cy
    local len = math.sqrt(dx * dx + dy * dy)

    if len > 0 then
        spawn_projectile(cx, cy, dx / len, dy / len, false)
    end

    local c = (opts and opts.ring_color) or { 1, 1, 1 }
    FXManager.spawn_ring(cx, cy, c[1], c[2], c[3], 8, 35, 190)
end

-- One ring of the turret's volley: advances the spiral a step, then queues the
-- next ring if any remain. `pending_second_burst` is cleared by the engine
-- *before* fire_second runs, which is what lets this re-arm it and chain --
-- that's how one volley becomes 2 or 3 rings with no extra mechanism.
function Attacks.turret_ring(instance, type_def, spawn_projectile)
    instance.turret_rotation = (instance.turret_rotation or 0) + math.rad(18)

    Attacks.spread(instance, type_def, spawn_projectile, {
        count = 10,
        full_circle = true,
        ring_color = { 0.4, 0.6, 1 },
        rotation_offset = instance.turret_rotation,
    })

    local left = instance.turret_bursts_left or 0
    if left > 0 then
        instance.turret_bursts_left = left - 1
        instance.pending_second_burst = type_def.burst_gap
    end
end

-- One burst of the phantom's ring, alternating axis-aligned (+) and diagonal
-- (X) each time, and chaining the same way the turret does.
--
-- A single 8-shot ring would cover every one of those directions at once --
-- denser, but completely static, with no moment where some directions are safe.
-- Alternating moves the gaps between bursts, so wherever you dodged the first
-- burst to is the wrong place to be standing for the second.
function Attacks.phantom_ring(instance, type_def, spawn_projectile)
    local count = type_def.ring_count
    -- half a step rotates the ring from axis-aligned to diagonal
    local offset = instance.phantom_diagonal and (math.pi / count) or 0

    Attacks.spread(instance, type_def, spawn_projectile, {
        count = count,
        full_circle = true,
        rotation_offset = offset,
        ring_color = instance.phantom_diagonal and { 0.7, 0.7, 0.95 } or { 0.9, 0.9, 1 },
    })

    instance.phantom_diagonal = not instance.phantom_diagonal

    local left = instance.phantom_bursts_left or 0
    if left > 0 then
        instance.phantom_bursts_left = left - 1
        instance.pending_second_burst = type_def.burst_gap
    end
end

return Attacks
