local Orb = {}

function Orb.load()
    Orb.list = {}
    Orb.speed = 175
    Orb.spawn_timer = 0
    Orb.size = 15
end

function Orb.update(dt, game_over, player, on_collision, spawn_rate)
    if game_over then return end

    Orb.spawn(dt, spawn_rate)

    Orb.move(dt, player, on_collision)
end

function Orb.draw()
    love.graphics.setColor(1, 1, 0)
    for _, e in ipairs(Orb.list) do
        love.graphics.circle("fill", e.x, e.y, e.size)
    end
end

function Orb.spawn(dt, spawn_rate)
    -- Zamanlayıcı ile daire yaratma
    Orb.spawn_timer = Orb.spawn_timer + dt
    if Orb.spawn_timer > spawn_rate then
        Orb.spawn_timer = 0
        local random_x = love.math.random(0, love.graphics.getWidth() - Orb.size)
        table.insert(Orb.list, { x = random_x, y = -25, size = Orb.size, missed = false })
    end
end

function Orb.move(dt, player, on_collision)
    for i = #Orb.list, 1, -1 do
        local e = Orb.list[i]
        e.y = e.y + Orb.speed * dt

        -- 1. Çarpışma Kontrolü (AABB)
        Orb.check_collision(player, on_collision)

        -- 3. Ekrandan çıkma kontrolü
        Orb.disappear(e, i)
    end
end

function Orb.check_collision(player, on_collision)
    for i, e in ipairs(Orb.list) do
        if player.x < e.x + e.size and e.x < player.x + player.size and
            player.y < e.y + e.size and e.y < player.y + player.size then
            on_collision(i) -- main.lua'dan gelen callback'i tetikle
        end
    end
end

function Orb.disappear(e, i)
    if e.y > love.graphics.getHeight() then
        table.remove(Orb.list, i)
        Orb.speed = Orb.speed + 5
    end
end

function Orb.reset()
    Orb.list = {}
    Orb.speed = 200
    Orb.spawn_timer = 0
end

return Orb
