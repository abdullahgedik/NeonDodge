-- src/void_orb.lua
local VoidOrb = {}

function VoidOrb.load()
    VoidOrb.list = {}
    VoidOrb.speed = 200 -- Normal orbdan biraz daha hızlı olsun ki panik yaratsın!
    VoidOrb.spawn_timer = 0
    VoidOrb.radius = 14 -- Biraz daha büyük ve belirgin olsun
    VoidOrb.is_paused = false
end

function VoidOrb.update(dt, game_over, player, on_collision, on_miss, spawn_rate)
    if game_over or VoidOrb.is_paused then return end

    VoidOrb.spawn(dt, spawn_rate)
    VoidOrb.move_and_process(dt, player, on_collision, on_miss)
end

function VoidOrb.draw()
    -- Mor / Eflatun RGB rengi (0.6, 0, 1)
    for _, o in ipairs(VoidOrb.list) do
        -- İç içe iki daire çizerek neon havası veriyoruz
        love.graphics.setColor(0.6, 0, 1, 0.4)
        love.graphics.circle("fill", o.x, o.y, o.radius + 4) -- Dış parlama
        love.graphics.setColor(0.7, 0.2, 1)
        love.graphics.circle("fill", o.x, o.y, o.radius)     -- Çekirdek
    end
end

function VoidOrb.spawn(dt, spawn_rate)
    VoidOrb.spawn_timer = VoidOrb.spawn_timer + dt
    if VoidOrb.spawn_timer > spawn_rate then
        VoidOrb.spawn_timer = 0
        local random_x = love.math.random(VoidOrb.radius, love.graphics.getWidth() - VoidOrb.radius)
        table.insert(VoidOrb.list, { x = random_x, y = -20, radius = VoidOrb.radius })
    end
end

-- src/void_orb.lua içindeki move_and_process fonksiyonu
function VoidOrb.move_and_process(dt, player, on_collision, on_miss)
    local FXManager = require("src/fx_manager") -- FXManager'ı çağır

    for i = #VoidOrb.list, 1, -1 do
        local o = VoidOrb.list[i]
        o.y = o.y + VoidOrb.speed * dt

        local player_cx = player.x + player.size / 2
        local player_cy = player.y + player.size / 2
        local distance = math.sqrt((player_cx - o.x) ^ 2 + (player_cy - o.y) ^ 2)

        if distance < (player.size / 2 + o.radius) then
            -- MODÜLER ÇAĞRI: Mor renkte (0.7, 0.2, 1), başlangıç yarıçapı 14, max 80 olan (biraz daha büyük) şok dalgası
            FXManager.spawn_ring(o.x, o.y, 0.7, 0.2, 1, 14, 80, 200)

            on_collision(i) -- Toplandığında başarı callback'i
            goto continue
        end

        if o.y > love.graphics.getHeight() + o.radius then
            -- Kaçırma durumunda olan partikül patlaması (Aynen kalıyor)
            FXManager.spawn("void_explosion", o.x, love.graphics.getHeight() - 5, 45)
            on_miss(i)
            table.remove(VoidOrb.list, i)
            goto continue
        end

        ::continue::
    end
end

function VoidOrb.remove(index)
    table.remove(VoidOrb.list, index)
end

function VoidOrb.pause() VoidOrb.is_paused = true end

function VoidOrb.resume() VoidOrb.is_paused = false end

function VoidOrb.reset()
    VoidOrb.list = {}
    VoidOrb.spawn_timer = 0
end

return VoidOrb
