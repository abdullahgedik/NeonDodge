local Screen                = require("src/screen")

local Bloom                 = {}

local BLUR_PASSES           = 4 -- how many blur iterations, more = softer/wider glow
local BLOOM_THRESHOLD       = 0.55 -- brightness cutoff, only pixels brighter than this glow
local BLOOM_STRENGTH        = 0.9 -- alpha of the glow layer when composited back on top

-- uses max-channel "brightness" rather than perceptual luminance: perceptual weights
-- (favoring green) unfairly discount saturated reds/blues/purples, so neon colors like
-- the void orb or the enemy triangle would never cross the threshold despite being fully lit
local THRESHOLD_SHADER_CODE = [[
    extern number threshold;

    vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords)
    {
        vec4 pixel = Texel(tex, texture_coords);
        float brightness = max(pixel.r, max(pixel.g, pixel.b));
        if (brightness < threshold) {
            pixel.rgb = vec3(0.0);
        }
        return pixel * color;
    }
]]

-- separable 9-tap gaussian blur, called once per axis via the `direction` uniform
local BLUR_SHADER_CODE      = [[
    extern vec2 direction;

    vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords)
    {
        vec4 sum = vec4(0.0);
        sum += Texel(tex, texture_coords - 4.0 * direction) * 0.0162162162;
        sum += Texel(tex, texture_coords - 3.0 * direction) * 0.0540540541;
        sum += Texel(tex, texture_coords - 2.0 * direction) * 0.1216216216;
        sum += Texel(tex, texture_coords - 1.0 * direction) * 0.1945945946;
        sum += Texel(tex, texture_coords)                   * 0.2270270270;
        sum += Texel(tex, texture_coords + 1.0 * direction) * 0.1945945946;
        sum += Texel(tex, texture_coords + 2.0 * direction) * 0.1216216216;
        sum += Texel(tex, texture_coords + 3.0 * direction) * 0.0540540541;
        sum += Texel(tex, texture_coords + 4.0 * direction) * 0.0162162162;
        return sum * color;
    }
]]

-- the blur canvases are sized off the GAME's resolution, not the window's --
-- see Bloom.load
local BLUR_DIVISOR          = 2

function Bloom.load()
    -- Half of the *game* resolution, fixed, no matter how big the window is.
    -- The blur kernel below is a fixed 4 texels wide, so its reach in game
    -- units is set entirely by this size -- following the window instead
    -- would quietly tighten the glow as the window grew, changing the look
    -- the whole palette was tuned against. Blurred output is low-frequency by
    -- definition, so computing it small and upscaling on composite is free
    -- visually and cheaper besides.
    Bloom.blur_width = math.floor(Screen.WIDTH / BLUR_DIVISOR)
    Bloom.blur_height = math.floor(Screen.HEIGHT / BLUR_DIVISOR)
    Bloom.bright_canvas = love.graphics.newCanvas(Bloom.blur_width, Bloom.blur_height)
    Bloom.ping_canvas = love.graphics.newCanvas(Bloom.blur_width, Bloom.blur_height)
    Bloom.pong_canvas = love.graphics.newCanvas(Bloom.blur_width, Bloom.blur_height)

    Bloom.threshold_shader = love.graphics.newShader(THRESHOLD_SHADER_CODE)
    Bloom.threshold_shader:send("threshold", BLOOM_THRESHOLD)

    Bloom.blur_shader = love.graphics.newShader(BLUR_SHADER_CODE)

    Bloom.resize()
end

-- The scene and final canvases DO match the window, so every procedurally
-- drawn shape rasterizes at the display's true resolution. Nothing in this
-- game is a sprite -- it's all rectangles, circles, polygons and lines -- so
-- there is no reason to render it at 800x600 and stretch the result; drawing
-- the same geometry under a scale transform costs nothing and stays sharp at
-- any size. Called on load and from love.resize.
function Bloom.resize()
    local w, h = Screen.window_size()
    if Bloom.width == w and Bloom.height == h then return end

    Bloom.width, Bloom.height = w, h
    Bloom.scene_canvas = love.graphics.newCanvas(w, h)
    Bloom.final_canvas = love.graphics.newCanvas(w, h)
end

function Bloom.begin_scene()
    love.graphics.setCanvas(Bloom.scene_canvas)
    love.graphics.clear(0, 0, 0, 1)
end

function Bloom.finish_scene()
    love.graphics.setCanvas(Bloom.bright_canvas)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setShader(Bloom.threshold_shader)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(Bloom.scene_canvas, 0, 0, 0,
        Bloom.blur_width / Bloom.width, Bloom.blur_height / Bloom.height)
    love.graphics.setShader()

    local read_canvas = Bloom.bright_canvas
    for _ = 1, BLUR_PASSES do
        love.graphics.setCanvas(Bloom.ping_canvas)
        love.graphics.clear(0, 0, 0, 1)
        love.graphics.setShader(Bloom.blur_shader)
        Bloom.blur_shader:send("direction", { 1 / Bloom.blur_width, 0 })
        love.graphics.draw(read_canvas, 0, 0)

        love.graphics.setCanvas(Bloom.pong_canvas)
        love.graphics.clear(0, 0, 0, 1)
        Bloom.blur_shader:send("direction", { 0, 1 / Bloom.blur_height })
        love.graphics.draw(Bloom.ping_canvas, 0, 0)
        love.graphics.setShader()

        read_canvas = Bloom.pong_canvas
    end

    love.graphics.setCanvas(Bloom.final_canvas)
    love.graphics.clear(0, 0, 0, 1)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(Bloom.scene_canvas, 0, 0)

    love.graphics.setBlendMode("add")
    love.graphics.setColor(1, 1, 1, BLOOM_STRENGTH)
    love.graphics.draw(read_canvas, 0, 0, 0,
        Bloom.width / Bloom.blur_width, Bloom.height / Bloom.blur_height)
    love.graphics.setBlendMode("alpha")
    love.graphics.setColor(1, 1, 1, 1)

    love.graphics.setCanvas()
end

return Bloom
