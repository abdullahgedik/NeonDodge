-- Timings and geometry shared by the whole boss system. These are in their own
-- file because more than one of the boss modules needs them: the engine, the
-- movement modes and the laser subsystem would otherwise each need a copy, and
-- a copy is how two numbers that must agree quietly stop agreeing.
--
-- Per-type numbers do NOT belong here -- those live on each entry in
-- src/boss/types.lua, next to the behavior they tune.
return {
    -- how fast a boss slides down into position, and back out again
    ENTER_SPEED             = 120,
    EXIT_SPEED              = 160,

    -- the y a boss settles at for its encounter (orbiters override this with
    -- their own orbit_center_y)
    HOVER_Y                 = 90,

    -- minimum seconds between two hits from the same instance, so overlapping
    -- a boss body doesn't drain HP every single frame
    HIT_COOLDOWN            = 0.6,

    -- how long a normal encounter lasts once hovering. The laser ignores this
    -- and exits on a sweep count instead (see src/boss/laser.lua) -- its beam
    -- cycle length never lined up with a flat time budget, so it could leave
    -- mid-telegraph.
    ENCOUNTER_DURATION      = 14,

    -- fraction of a boss's width shaved off each side of its hitbox, so
    -- brushing the very edge reads as a miss
    COLLISION_PADDING_RATIO = 0.15,
}
