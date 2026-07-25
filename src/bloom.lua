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

function Bloom.load()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    Bloom.width, Bloom.height = w, h

    Bloom.scene_canvas = love.graphics.newCanvas(w, h)
    Bloom.final_canvas = love.graphics.newCanvas(w, h)

    -- half-res for the blur passes: cheaper, and the upscale-on-composite adds width to the glow
    Bloom.blur_width = math.floor(w / 2)
    Bloom.blur_height = math.floor(h / 2)
    Bloom.bright_canvas = love.graphics.newCanvas(Bloom.blur_width, Bloom.blur_height)
    Bloom.ping_canvas = love.graphics.newCanvas(Bloom.blur_width, Bloom.blur_height)
    Bloom.pong_canvas = love.graphics.newCanvas(Bloom.blur_width, Bloom.blur_height)

    Bloom.threshold_shader = love.graphics.newShader(THRESHOLD_SHADER_CODE)
    Bloom.threshold_shader:send("threshold", BLOOM_THRESHOLD)

    Bloom.blur_shader = love.graphics.newShader(BLUR_SHADER_CODE)
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
