local Enemy = {}

function Enemy.load()
    Enemy.list = {}
    Enemy.speed = 225
    Enemy.spawn_timer = 0
    Enemy.size = 25
    Enemy.is_paused = false
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
        love.graphics.rectangle("fill", e.x, e.y, e.size, e.size)
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

-- BUG FIX: Tüm mantığı indeks kayması yaşatmayacak TEK BİR güvenli döngüde topladık
function Enemy.move_and_process(dt, player, on_collision)
    for i = #Enemy.list, 1, -1 do
        local e = Enemy.list[i]

        -- 1. Hareket ettir
        e.y = e.y + Enemy.speed * dt

        -- 2. Çarpışma Kontrolü (AABB) - Doğrudan mevcut indeks (i) üzerinden kontrol
        if player.x < e.x + e.size and e.x < player.x + player.size and
            player.y < e.y + e.size and e.y < player.y + player.size then
            -- Çarpışma gerçekleşti, main.lua'daki callback'i tetikle
            on_collision(i)

            -- Bu düşmanla işimiz bitti (silindiği için), döngünün bu adımını sonlandırıp bir sonrakine geç (Unity'deki continue)
            goto continue
        end

        -- 3. Ekrandan çıkma kontrolü
        if e.y > love.graphics.getHeight() then
            Enemy.remove(i)
            Enemy.speed = Enemy.speed + 5
        end

        ::continue::
    end
end

function Enemy.remove(index)
    table.remove(Enemy.list, index)
end

function Enemy.pause()
    Enemy.is_paused = true
end

function Enemy.resume()
    Enemy.is_paused = false
end

function Enemy.reset()
    Enemy.list = {}
    Enemy.speed = 225 -- Yükleme hızıyla senkronize olsun diye 225 yaptık
    Enemy.spawn_timer = 0
end

return Enemy
