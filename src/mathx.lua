-- Small math helpers used across the project. Nothing LÖVE-specific here --
-- these are the two or three bits of arithmetic that kept getting written out
-- by hand in several files, where the formula is short but says nothing about
-- its intent unless you already recognize it.
local Mathx = {}

-- Straight-line blend between two values. t=0 gives `a`, t=1 gives `b`,
-- 0.5 gives the midpoint. Used for the difficulty spawn-rate ramp and for the
-- charger boss winding its timings up over an encounter.
function Mathx.lerp(a, b, t)
    return a + (b - a) * t
end

-- Clamps a value into [min, max].
function Mathx.clamp(value, min, max)
    if value < min then return min end
    if value > max then return max end
    return value
end

-- Easing curves. Feed in a raw 0->1 progress value and get back a reshaped
-- 0->1 value, so an animation doesn't move at a dead-constant rate.
--
-- "ease out" = starts fast, slows as it approaches 1. Most of the change
-- happens early, which reads as something *settling into place* rather than
-- sliding at a fixed speed. That's why these exist as names: written inline,
-- `1 - (1 - t) * (1 - t)` tells you nothing about what it's for.
function Mathx.ease_out(t)
    return 1 - (1 - t) * (1 - t)
end

-- Same shape, stronger: even more of the movement is front-loaded, so it
-- snaps in and then drifts the last bit. Used by the card-select cards.
function Mathx.ease_out_strong(t)
    return 1 - (1 - t) ^ 3
end

return Mathx
