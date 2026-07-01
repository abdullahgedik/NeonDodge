local Enemy = {}

function Enemy.load()
    Enemy.list = {}
    Enemy.speed = 225
    Enemy.spawn_timer = 0
    Enemy.size = 25
end

function Enemy.update(dt, game_over, player, on_collision, spawn_rate)
    if game_over then return end

    Enemy.spawn(dt, spawn_rate)

    Enemy.move(dt, player, on_collision)
end

function Enemy.draw()
    love.graphics.setColor(1, 0, 0.2)
    for _, e in ipairs(Enemy.list) do
        love.graphics.rectangle("fill", e.x, e.y, e.size, e.size)
    end
end

function Enemy.spawn(dt, spawn_rate)
    -- Zamanlayıcı ile düşman yaratma
    Enemy.spawn_timer = Enemy.spawn_timer + dt
    if Enemy.spawn_timer > spawn_rate then
        Enemy.spawn_timer = 0
        local random_x = love.math.random(0, love.graphics.getWidth() - Enemy.size)
        table.insert(Enemy.list, { x = random_x, y = -25, size = Enemy.size, missed = false })
    end
end

function Enemy.move(dt, player, on_collision)
    for i = #Enemy.list, 1, -1 do
        local e = Enemy.list[i]
        e.y = e.y + Enemy.speed * dt

        -- 1. Çarpışma Kontrolü (AABB)
        Enemy.check_collision(player, on_collision)

        -- 3. Ekrandan çıkma kontrolü
        Enemy.disappear(e, i)
    end
end

function Enemy.check_collision(player, on_collision)
    for i, e in ipairs(Enemy.list) do
        if player.x < e.x + e.size and e.x < player.x + player.size and
            player.y < e.y + e.size and e.y < player.y + player.size then
            on_collision(i) -- main.lua'dan gelen callback'i tetikle
        end
    end
end

function Enemy.disappear(e, i)
    if e.y > love.graphics.getHeight() then
        table.remove(Enemy.list, i)
        Enemy.speed = Enemy.speed + 5
        -- Normal ekrandan çıkma skoru için de bir tetikleyici yapılabilir,
        -- şimdilik main.lua skoru direkt uçuracak.
    end
end

function Enemy.reset()
    Enemy.list = {}
    Enemy.speed = 200
    Enemy.spawn_timer = 0
end

return Enemy
