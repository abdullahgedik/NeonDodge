local Enemy = {}

function Enemy.load()
    Enemy.list = {}
    Enemy.speed = 220
    Enemy.spawn_timer = 0
end

function Enemy.update(dt, game_over, player, on_collision, on_near_miss, spawn_rate)
    if game_over then return end

    -- Zamanlayıcı ile düşman yaratma
    Enemy.spawn_timer = Enemy.spawn_timer + dt
    if Enemy.spawn_timer > spawn_rate then
        Enemy.spawn_timer = 0
        local random_x = love.math.random(0, love.graphics.getWidth() - 25)
        table.insert(Enemy.list, { x = random_x, y = -25, size = 25, missed = false })
    end

    -- Düşmanları hareket ettir ve kontrol et
    for i = #Enemy.list, 1, -1 do
        local e = Enemy.list[i]
        e.y = e.y + Enemy.speed * dt

        -- 1. Çarpışma Kontrolü (AABB)
        if player.x < e.x + e.size and e.x < player.x + player.size and
            player.y < e.y + e.size and e.y < player.y + player.size then
            on_collision(i) -- main.lua'dan gelen callback'i tetikle
        end

        -- 2. Near-Miss Kontrolü (Mesafe tabanlı)
        if not e.missed and not game_over then
            local p_cx, p_cy = player.x + player.size / 2, player.y + player.size / 2
            local e_cx, e_cy = e.x + e.size / 2, e.y + e.size / 2
            local dist = math.sqrt((p_cx - e_cx) ^ 2 + (p_cy - e_cy) ^ 2)

            if dist < 65 then
                e.missed = true
                on_near_miss() -- main.lua'dan gelen callback'i tetikle
            end
        end

        -- 3. Ekrandan çıkma kontrolü
        if e.y > love.graphics.getHeight() then
            table.remove(Enemy.list, i)
            Enemy.speed = Enemy.speed + 5
            -- Normal ekrandan çıkma skoru için de bir tetikleyici yapılabilir,
            -- şimdilik main.lua skoru direkt uçuracak.
        end
    end
end

function Enemy.draw()
    love.graphics.setColor(1, 0, 0.4)
    for _, e in ipairs(Enemy.list) do
        love.graphics.rectangle("fill", e.x, e.y, e.size, e.size)
    end
end

function Enemy.reset()
    Enemy.list = {}
    Enemy.speed = 200
    Enemy.spawn_timer = 0
end

return Enemy
