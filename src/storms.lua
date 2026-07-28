-- The storm roster: mid-wave bursts where one hazard's spawn rate roughly
-- triples for ten seconds. Same idea as src/boss/types.lua -- a registry of
-- data, kept apart from the code that schedules it (main.lua).
--
-- A storm is defined by which single hazard it NARROWS DOWN TO, not by piling
-- everything on. Every hazard not named in a storm's `rates` is suppressed
-- outright for its duration. An early version sped up every type at once and
-- was flatly unsurvivable, and the fix was narrowing the mix rather than
-- turning the multiplier down.
--
-- `rates` multiplies that hazard's Difficulty.spawn_rate, which is a *period*
-- in seconds -- so a value BELOW 1 means "spawns more often" (0.35 ~= 3x) and 1
-- means "unchanged". Listing a hazard at 1 keeps it present but normal.
local Unlocks = require("src/unlocks")

local Storms  = {}

-- One storm per hazard, each gated on the same stage that unlocks the hazard it
-- is built around -- so the storm roster grows exactly as the hazard roster
-- does, instead of every storm being the same event forever.
Storms.TYPES  = {
    {
        id = "swarm",
        name = "HAZARD STORM",
        color = { 1, 0.5, 0.1 },
        required_unlock_stage = 0,
        rates = { enemy = 0.35, orb = 0.35 },
    },
    {
        -- inverts the game's core instinct: these must be *caught*, and
        -- missing one costs HP, so "dodge everything" actively kills you
        id = "void_rain",
        name = "VOID RAIN",
        color = { 0.75, 0.3, 1 },
        required_unlock_stage = Unlocks.VOID_ORB,
        rates = { void_orb = 0.32, orb = 0.6, enemy = 1 },
    },
    {
        id = "crossfire",
        name = "CROSSFIRE",
        color = { 1, 0.3, 0.05 },
        required_unlock_stage = Unlocks.ZIGZAG,
        rates = { zigzag = 0.3, orb = 0.6, enemy = 1 },
    },
    {
        -- zone denial rather than dodging -- the arena fills with blast
        -- circles and safe space is what keeps moving, not the hazards
        id = "minefield",
        name = "MINEFIELD",
        color = { 0.9, 0.6, 0.2 },
        required_unlock_stage = Unlocks.MINE,
        rates = { mine = 0.3, orb = 0.6, enemy = 1 },
    },
}

-- Picks the storm about to run from the types unlocked so far, avoiding an
-- immediate repeat whenever there's more than one to choose from -- so the
-- roster growing actually reads as variety instead of the same roll twice.
function Storms.pick(unlock_stage, previous)
    local eligible = {}
    for _, def in ipairs(Storms.TYPES) do
        if unlock_stage >= def.required_unlock_stage and def ~= previous then
            table.insert(eligible, def)
        end
    end

    -- only the just-played type is unlocked (i.e. very early on, when swarm is
    -- the whole roster) -- repeating it beats having no storm at all
    if #eligible == 0 then return previous or Storms.TYPES[1] end

    return eligible[love.math.random(#eligible)]
end

return Storms
