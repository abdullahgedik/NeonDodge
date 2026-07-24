local Difficulty    = {}

local WAVE_DURATION = 20 -- steady-state seconds per wave, from wave 4 onward
local RAMP_WAVES    = 6  -- how many WAVE_DURATION-lengths of real time until spawn rates hit their floor -- a
                         -- fixed time budget (RAMP_WAVES * WAVE_DURATION), not literally "wave number RAMP_WAVES",
                         -- so it's unaffected by EARLY_WAVE_DURATIONS below

-- waves 1-3 are shorter than the steady-state duration, so the game
-- escalates noticeably faster while the player is still getting oriented
-- instead of an uneventful 20s sit before anything changes -- storms/bosses
-- (wave-number-gated) naturally arrive sooner in real time as a result
local EARLY_WAVE_DURATIONS = { 10, 13, 16 }

local config        = {
    enemy    = { start = 0.6, min = 0.3 },
    zigzag   = { start = 2, min = 1 },
    orb      = { start = 2, min = 1 },
    void_orb = { start = 6.0, min = 3.0 },
    mine     = { start = 7, min = 3.5 },
}

local function lerp(a, b, t)
    return a + (b - a) * t
end

-- returns the wave number `elapsed` falls in, plus that wave's own
-- [start, end) boundary in seconds -- shared by Difficulty.wave() and
-- Difficulty.skip_wave() so the two can't drift out of sync with each other
local function wave_at(elapsed)
    local remaining = elapsed
    local wave_start = 0

    for i, duration in ipairs(EARLY_WAVE_DURATIONS) do
        if remaining < duration then
            return i, wave_start, wave_start + duration
        end
        remaining = remaining - duration
        wave_start = wave_start + duration
    end

    local extra_waves = math.floor(remaining / WAVE_DURATION)
    local start = wave_start + extra_waves * WAVE_DURATION
    return #EARLY_WAVE_DURATIONS + extra_waves + 1, start, start + WAVE_DURATION
end

function Difficulty.load()
    Difficulty.elapsed = 0
    Difficulty.is_paused = false
end

function Difficulty.update(dt, game_over)
    if game_over or Difficulty.is_paused then return end
    Difficulty.elapsed = Difficulty.elapsed + dt
end

function Difficulty.wave()
    local wave = wave_at(Difficulty.elapsed)
    return wave
end

function Difficulty.spawn_rate(kind)
    local c = config[kind]
    local progress = math.min(Difficulty.elapsed / (WAVE_DURATION * RAMP_WAVES), 1)
    return lerp(c.start, c.min, progress)
end

function Difficulty.skip_wave()
    -- jump precisely to the start of the next wave, regardless of how far
    -- into the current (possibly shorter, early) wave elapsed currently is
    local _, _, wave_end = wave_at(Difficulty.elapsed)
    Difficulty.elapsed = wave_end
end

function Difficulty.pause() Difficulty.is_paused = true end

function Difficulty.resume() Difficulty.is_paused = false end

function Difficulty.reset()
    Difficulty.elapsed = 0
end

return Difficulty
