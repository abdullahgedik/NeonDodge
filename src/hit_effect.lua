local HitEffect         = {}

local DURATION          = 0.35
local DANGER_BEAT_SPEED = 5.5  -- controls how fast the low-hp pulse beats
local DANGER_BASE       = 0.22 -- vignette/tint present even at the low point of a beat
local DANGER_AMPLITUDE  = 0.4  -- how much stronger the tint gets at the peak of a beat

local SHADER_CODE       = [[
    extern number hit_strength;
    extern number danger_strength;

    vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords)
    {
        vec2 dir = texture_coords - vec2(0.5, 0.5);

        float offset = hit_strength * 0.012;
        float r = Texel(tex, texture_coords + dir * offset).r;
        float g = Texel(tex, texture_coords).g;
        float b = Texel(tex, texture_coords - dir * offset).b;
        float a = Texel(tex, texture_coords).a;

        vec4 pixel = vec4(r, g, b, a);

        float dist = length(dir);
        float edge = smoothstep(0.15, 0.75, dist);

        float hit_vignette = 1.0 - hit_strength * 0.6 * edge;
        pixel.rgb *= hit_vignette;

        vec3 danger_tint = vec3(0.85, 0.05, 0.05);
        pixel.rgb = mix(pixel.rgb, pixel.rgb * danger_tint * 1.6, danger_strength * edge);

        return pixel * color;
    }
]]

function HitEffect.load()
    HitEffect.timer = 0
    HitEffect.clock = 0
    HitEffect.is_danger = false
    HitEffect.shader = love.graphics.newShader(SHADER_CODE)
end

function HitEffect.trigger()
    HitEffect.timer = DURATION
end

function HitEffect.update(dt, is_danger)
    if HitEffect.timer > 0 then
        HitEffect.timer = math.max(HitEffect.timer - dt, 0)
    end

    HitEffect.clock = HitEffect.clock + dt
    HitEffect.is_danger = is_danger
end

function HitEffect.draw(canvas)
    local hit_strength = HitEffect.timer / DURATION

    local danger_strength = 0
    if HitEffect.is_danger then
        local pulse = math.abs(math.sin(HitEffect.clock * DANGER_BEAT_SPEED)) ^ 3
        danger_strength = DANGER_BASE + DANGER_AMPLITUDE * pulse
    end

    love.graphics.setColor(1, 1, 1, 1)

    if hit_strength <= 0 and danger_strength <= 0 then
        love.graphics.draw(canvas, 0, 0)
        return
    end

    love.graphics.setShader(HitEffect.shader)
    HitEffect.shader:send("hit_strength", hit_strength)
    HitEffect.shader:send("danger_strength", danger_strength)
    love.graphics.draw(canvas, 0, 0)
    love.graphics.setShader()
end

function HitEffect.reset()
    HitEffect.timer = 0
    HitEffect.clock = 0
    HitEffect.is_danger = false
end

return HitEffect
