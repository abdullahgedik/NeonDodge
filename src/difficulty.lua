local Difficulty = {}

local WAVE_DURATION = 20  -- seconds per wave
local RAMP_WAVES     = 6  -- waves until spawn rates hit their floor

local config = {
    enemy    = { start = 0.6, min = 0.28 },
    zigzag   = { start = 1.8, min = 0.9 },
    orb      = { start = 2.0, min = 1.2 },
    void_orb = { start = 5.0, min = 3.0 },
    mine     = { start = 5.0, min = 2.8 },
}

local function lerp(a, b, t)
    return a + (b - a) * t
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
    return math.floor(Difficulty.elapsed / WAVE_DURATION) + 1
end

function Difficulty.spawn_rate(kind)
    local c = config[kind]
    local progress = math.min(Difficulty.elapsed / (WAVE_DURATION * RAMP_WAVES), 1)
    return lerp(c.start, c.min, progress)
end

function Difficulty.skip_wave()
    Difficulty.elapsed = Difficulty.elapsed + WAVE_DURATION
end

function Difficulty.pause() Difficulty.is_paused = true end

function Difficulty.resume() Difficulty.is_paused = false end

function Difficulty.reset()
    Difficulty.elapsed = 0
end

return Difficulty
