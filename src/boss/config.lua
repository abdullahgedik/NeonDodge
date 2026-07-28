-- Timings and geometry shared by the whole boss system. These are in their own
-- file because more than one of the boss modules needs them: the engine, the
-- movement modes and the laser subsystem would otherwise each need a copy, and
-- a copy is how two numbers that must agree quietly stop agreeing.
--
-- Per-type numbers do NOT belong here -- those live on each entry in
-- src/boss/types.lua, next to the behavior they tune.
local Config                   = {}

-- how fast a boss slides down into position, and back out again
Config.ENTER_SPEED             = 120
Config.EXIT_SPEED              = 160

-- the y a boss settles at for its encounter (orbiters override this with their
-- own orbit_center_y)
Config.HOVER_Y                 = 90

-- minimum seconds between two hits from the same instance, so overlapping a
-- boss body doesn't drain HP every single frame
Config.HIT_COOLDOWN            = 0.6

-- Default seconds a boss spends hovering, i.e. the encounter proper. Types
-- override it with their own `encounter_duration`, and the later ones in
-- Boss.SEQUENCE deliberately run longer -- a boss you meet at wave 48 should be
-- a bigger set piece than the one at wave 6.
--
-- Two types ignore this entirely: the laser exits on a completed-sweep count
-- (its beam cycle never lined up with a flat time budget, so on a timer it
-- could leave mid-telegraph), and the charger may only leave from its "aim"
-- state so it never abandons a slam it already committed to. Both go through
-- the `is_encounter_done` hook.
Config.ENCOUNTER_DURATION      = 16

-- fraction of a boss's width shaved off each side of its hitbox, so brushing
-- the very edge reads as a miss
Config.COLLISION_PADDING_RATIO = 0.15

-- How long this particular type hovers. Everything that needs to scale with
-- the encounter's length -- the charger's aggression ramp, the warden's closing
-- arena, the engine's exit check -- asks through here, so a type's duration and
-- the curves timed against it can never disagree.
function Config.encounter_duration(type_def)
    return type_def.encounter_duration or Config.ENCOUNTER_DURATION
end

return Config
