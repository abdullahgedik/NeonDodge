-- Oyun ilk açıldığında bir kez çalışır (Tanımlamalar burada yapılır)
function love.load()
    -- Oyuncu değişkenleri (Zaten yazmıştık)
    player = {
        x = 400,
        y = 500,
        size = 30,
        speed = 300
    }

    -- Engel (Enemy) listesi ve ayarları
    enemies = {}          -- Tüm engelleri bu tabloda toplayacağız
    enemy_speed = 200
    enemy_spawn_timer = 0 -- Yeni engel yaratmak için sayaç

    -- Oyun durumu ve Skor
    score = 0
    game_over = false
end

-- Oyun döngüsü (Saniyede onlarca kez çalışır, mantık ve hareket buradadır)
-- dt: 'delta time' demektir. Bilgisayar hızından bağımsız sabit hızda hareket sağlar.
function love.update(dt)
    -- Eğer oyun bittiyse hiçbir şeyi güncelleme (oyun donsun)
    if game_over then return end

    -- 1. Oyuncu Hareketi (Zaten yazmıştık)
    if love.keyboard.isDown("left") or love.keyboard.isDown("a") then
        player.x = player.x - player.speed * dt
    end
    if love.keyboard.isDown("right") or love.keyboard.isDown("d") then
        player.x = player.x + player.speed * dt
    end
    if love.keyboard.isDown("up") or love.keyboard.isDown("w") then
        player.y = player.y - player.speed * dt
    end
    if love.keyboard.isDown("down") or love.keyboard.isDown("s") then
        player.y = player.y + player.speed * dt
    end

    -- Ekran sınırları dışına çıkmayı engelleme (Bonus)
    if player.x < 0 then player.x = 0 end
    if player.x > love.graphics.getWidth() - player.size then
        player.x = love.graphics.getWidth() - player.size
    end
    if player.y < 0 then player.y = 0 end
    if player.y > love.graphics.getHeight() - player.size then
        player.y = love.graphics.getHeight() - player.size
    end

    -- 2. Zamanlayıcı ile Engel Oluşturma
    enemy_spawn_timer = enemy_spawn_timer + dt
    if enemy_spawn_timer > 0.5 then -- Her 0.5 saniyede bir engel düşsün
        enemy_spawn_timer = 0
        -- Rastgele bir X pozisyonu seçelim (0 ile ekran genişliği arasında)
        local random_x = love.math.random(0, love.graphics.getWidth() - 20)

        -- Yeni engeli tabloya ekle
        table.insert(enemies, {
            x = random_x,
            y = -20, -- Ekranın hemen üstünden başlasın
            size = 20
        })
    end

    -- 3. Engelleri Hareket Ettirme ve Çarpışma Kontrolü
    -- Listeden eleman silerken döngüyü tersten (sondan başa) çalıştırmak Lua'da altın kuraldır!
    for i = #enemies, 1, -1 do
        local enemy = enemies[i]
        enemy.y = enemy.y + enemy_speed * dt -- Aşağı doğru hareket

        -- Çarpışma Testi (AABB Collision)
        if checkCollision(player, enemy) then
            game_over = true
        end

        -- Ekrandan çıkan engelleri temizle ve puan yaz
        if enemy.y > love.graphics.getHeight() then
            table.remove(enemies, i)
            score = score + 1
            -- Oyun zorlaşsın: Her puanda hız biraz artsın
            enemy_speed = enemy_speed + 6
        end
    end
end

-- Ekrana çizim yapma fonksiyonu (Her karede yenilenir)
function love.draw()
    -- Arka plan
    love.graphics.clear(0.05, 0.05, 0.1) -- Gece mavisi neon teması

    -- Oyuncuyu çiz (Neon Yeşil)
    love.graphics.setColor(0, 1, 0.5)
    love.graphics.rectangle("fill", player.x, player.y, player.size, player.size)

    -- Engelleri çiz (Neon Pembe)
    love.graphics.setColor(1, 0, 0.4)
    for i, enemy in ipairs(enemies) do
        love.graphics.rectangle("fill", enemy.x, enemy.y, enemy.size, enemy.size)
    end

    -- Skoru Yazdır (Beyaz)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("SCORE: " .. score, 10, 10, 0, 1.5, 1.5) -- 1.5 kat büyük yaz

    -- Oyun Bitti Ekranı
    if game_over then
        love.graphics.setColor(1, 0, 0)
        love.graphics.print("OYUN BİTTİ!", love.graphics.getWidth() / 2 - 80, love.graphics.getHeight() / 2 - 20, 0, 2, 2)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print("Yeniden başlamak için 'R' tuşuna bas.", love.graphics.getWidth() / 2 - 130,
            love.graphics.getHeight() / 2 + 20, 0, 1.2, 1.2)
    end
end

function checkCollision(obj1, obj2)
    return obj1.x < obj2.x + obj2.size and
        obj2.x < obj1.x + obj1.size and
        obj1.y < obj2.y + obj2.size and
        obj2.y < obj1.y + obj1.size
end

function love.keypressed(key)
    if key == "r" and game_over then
        -- Her şeyi sıfırla
        enemies = {}
        enemy_speed = 200
        enemy_spawn_timer = 0
        score = 0
        game_over = false
        player.x = 400
        player.y = 500
    end
end
