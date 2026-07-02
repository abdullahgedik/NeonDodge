local Enemy = {}

function Enemy.load()
    Enemy.list = {}
    Enemy.speed = 225
    Enemy.spawn_timer = 0
    Enemy.size = 30
    Enemy.is_paused = false
    -- Partikül kodları buradan tamamen kaldırıldı!
end

function Enemy.update(dt, game_over, player, on_collision, spawn_rate)
    if game_over then return end
    if Enemy.is_paused then return end

    Enemy.spawn(dt, spawn_rate)
    Enemy.move_and_process(dt, player, on_collision)
end

function Enemy.draw()
    love.graphics.setColor(1, 0, 0.2)
    for _, e in ipairs(Enemy.list) do
        love.graphics.polygon("fill",
            e.x, e.y,
            e.x + e.size, e.y,
            e.x + e.size / 2, e.y + e.size
        )
    end
end

function Enemy.spawn(dt, spawn_rate)
    Enemy.spawn_timer = Enemy.spawn_timer + dt
    if Enemy.spawn_timer > spawn_rate then
        Enemy.spawn_timer = 0
        local random_x = love.math.random(0, love.graphics.getWidth() - Enemy.size)
        table.insert(Enemy.list, { x = random_x, y = -25, size = Enemy.size })
    end
end

function Enemy.move_and_process(dt, player, on_collision)
    -- FXManager'ı lokal olarak çağırıyoruz
    local FXManager = require("src/fx_manager")

    for i = #Enemy.list, 1, -1 do
        local e = Enemy.list[i]
        e.y = e.y + Enemy.speed * dt

        local padding = e.size * 0.2

        if player.x < (e.x + e.size - padding) and (e.x + padding) < player.x + player.size and
            player.y < e.y + e.size and e.y < player.y + player.size then
            -- MODÜLER ÇAĞRI: FXManager üzerinden şablon adı ve merkez koordinatları ile çağırıyoruz
            FXManager.spawn("enemy_explosion", e.x + e.size / 2, e.y + e.size / 2, 30)

            on_collision(i)
            goto continue
        end

        if e.y > love.graphics.getHeight() then
            Enemy.remove(i)
            Enemy.speed = Enemy.speed + 5
        end

        ::continue::
    end
end

function Enemy.remove(index)
    if Enemy.list[index] then
        table.remove(Enemy.list, index)
    end
end

function Enemy.pause() Enemy.is_paused = true end

function Enemy.resume() Enemy.is_paused = false end

function Enemy.reset()
    Enemy.list = {}
    Enemy.speed = 225
    Enemy.spawn_timer = 0
end

return Enemy
