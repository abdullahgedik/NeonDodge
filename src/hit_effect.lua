local HitEffect = {}

local DURATION = 0.35

local SHADER_CODE = [[
    extern number strength;

    vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords)
    {
        vec2 dir = texture_coords - vec2(0.5, 0.5);

        float offset = strength * 0.012;
        float r = Texel(tex, texture_coords + dir * offset).r;
        float g = Texel(tex, texture_coords).g;
        float b = Texel(tex, texture_coords - dir * offset).b;
        float a = Texel(tex, texture_coords).a;

        vec4 pixel = vec4(r, g, b, a);

        float dist = length(dir);
        float vignette = 1.0 - strength * 0.6 * smoothstep(0.15, 0.75, dist);
        pixel.rgb *= vignette;

        return pixel * color;
    }
]]

function HitEffect.load()
    HitEffect.timer = 0
    HitEffect.shader = love.graphics.newShader(SHADER_CODE)
end

function HitEffect.trigger()
    HitEffect.timer = DURATION
end

function HitEffect.update(dt)
    if HitEffect.timer > 0 then
        HitEffect.timer = math.max(HitEffect.timer - dt, 0)
    end
end

function HitEffect.draw(canvas)
    local strength = HitEffect.timer / DURATION

    love.graphics.setColor(1, 1, 1, 1)

    if strength <= 0 then
        love.graphics.draw(canvas, 0, 0)
        return
    end

    love.graphics.setShader(HitEffect.shader)
    HitEffect.shader:send("strength", strength)
    love.graphics.draw(canvas, 0, 0)
    love.graphics.setShader()
end

function HitEffect.reset()
    HitEffect.timer = 0
end

return HitEffect
