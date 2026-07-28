-- The progressive hazard roster.
--
-- Rather than every hazard type being live from wave 1 with only its spawn
-- *rate* ramping, the roster itself grows one event at a time: each boss
-- defeated or storm survived advances the stage, and each hazard waits for its
-- own stage before it can spawn at all. That separates *variety* from *pace* --
-- they used to be the same axis, so wave 1 and wave 10 differed in speed but
-- not in kind.
--
-- With the current 6-wave boss / 3-wave storm cadence this lands as:
--   waves 1-3   Enemy + Orb only
--   after the wave-3 storm    + VoidOrb
--   after the wave-6 boss     + ZigzagEnemy
--   after the wave-9 storm    + Mine   (full roster)
local Unlocks    = {}

Unlocks.VOID_ORB = 1
Unlocks.ZIGZAG   = 2
Unlocks.MINE     = 3
Unlocks.MAX      = Unlocks.MINE

-- Which stage each hazard needs before it may spawn. Enemy and Orb are
-- deliberately absent: they're the two the game always has, so there's never a
-- moment with nothing to dodge and nothing to collect.
local REQUIRED   = {
    void_orb = Unlocks.VOID_ORB,
    zigzag   = Unlocks.ZIGZAG,
    mine     = Unlocks.MINE,
}

function Unlocks.is_unlocked(stage, kind)
    local needed = REQUIRED[kind]
    return needed == nil or stage >= needed
end

-- Called once when a boss or storm *concludes* -- not when it starts, so the
-- new hazard arrives as a reward for surviving rather than as part of the
-- event itself.
function Unlocks.advance(stage)
    return math.min(stage + 1, Unlocks.MAX)
end

return Unlocks
