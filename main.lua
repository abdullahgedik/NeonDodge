-- Oyun ilk açıldığında bir kez çalışır (Tanımlamalar burada yapılır)
function love.load()
    debug = false

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

    camera = {
        x = 0,
        y = 0,
        z = -20, -- Kamerayı parçacıklardan geriye çekiyoruz (Dolly shot)
        rotation = 0,
        fov = 60 -- Görüş açısı (Field of View)
    }

    local p_data = love.image.newImageData(32, 32)
    -- Döngüyle basit bir yumuşak daire (pixel maskesi) oluşturuyoruz
    for y = 0, 31 do
        for x = 0, 31 do
            local dx = x - 15.5
            local dy = y - 15.5
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist <= 15.5 then
                local alpha = (15.5 - dist) / 15.5 -- Kenarlara doğru şeffaflaşsın
                p_data:setPixel(x, y, 1, 1, 1, alpha)
            end
        end
    end
    local particle_img = love.graphics.newImage(p_data)

    -- 2. Unity'deki Particle System gibi nesnemizi kuruyoruz (Maksimum 1000 parçacık)
    trail_system = love.graphics.newParticleSystem(particle_img, 1000)
    trail_system:setParticleLifetime(0.2, 0.4) -- Ömür (sn)
    trail_system:setEmissionRate(50)           -- Saniyede kaç tane çıkacak
    trail_system:setSizeVariation(0.5)         -- Boyut çeşitliliği
    trail_system:setLinearAcceleration(0, 0)   -- Yerçekimi istemiyoruz
    -- Renk geçişi: Neon yeşilinden tamamen şeffafa (Unity'deki Color Over Lifetime)
    trail_system:setColors(0, 1, 0.5, 0.8, 0, 1, 0.5, 0)

    -- Ekran sallama değişkenleri
    shake_duration = 0  -- Sallanma süresi (saniye)
    shake_magnitude = 0 -- Sallanma şiddeti (piksel)

    -- Unity'deki font boyutu (Font Size) mantığı:
    -- LÖVE'ın dahili fontunu 24 piksel boyutunda keskin bir şekilde oluşturuyoruz
    game_font = love.graphics.newFont(24)

    -- Aktif font olarak bunu belirliyoruz
    love.graphics.setFont(game_font)
end

-- Oyun döngüsü (Saniyede onlarca kez çalışır, mantık ve hareket buradadır)
-- dt: 'delta time' demektir. Bilgisayar hızından bağımsız sabit hızda hareket sağlar.
function love.update(dt)
    -- Eğer oyun bittiyse hiçbir şeyi güncelleme (oyun donsun)
    if game_over then return end

    moveInput = { x = 0, y = 0 }
    moveVector = { x = 0, y = 0 }

    if love.keyboard.isDown("left") or love.keyboard.isDown("a") then
        moveInput.x = moveInput.x - 1
    end
    if love.keyboard.isDown("right") or love.keyboard.isDown("d") then
        moveInput.x = moveInput.x + 1
    end
    if love.keyboard.isDown("up") or love.keyboard.isDown("w") then
        moveInput.y = moveInput.y - 1
    end
    if love.keyboard.isDown("down") or love.keyboard.isDown("s") then
        moveInput.y = moveInput.y + 1
    end

    -- Klavye girdilerini aldıktan hemen sonra:
    moveVector.x, moveVector.y = normalize(moveInput.x, moveInput.y)

    player.x = player.x + moveVector.x * player.speed * dt
    player.y = player.y + moveVector.y * player.speed * dt

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

        -- Çarpışma Testi
        if checkCollision(player, enemy) then
            -- Sadece oyun henüz bitmediyse bu çarpışmayı KABUL ET
            if not game_over then
                game_over = true
                shake_duration = 0.4
                shake_magnitude = 15

                -- BUG FIX: Çarptığımız engeli anında sahneden siliyoruz
                -- ya da ekrandan uzaklaştırıyoruz ki bir sonraki karede tekrar çarpışma tetiklemesin!
                table.remove(enemies, i)
            end
        end

        -- Near-Miss Kontrolü (Engeller ekrandan çıkmadan önce yakınından geçti mi?)
        -- Oyuncunun merkezi ile engelin merkezini bulalım
        local p_cx = player.x + player.size / 2
        local p_cy = player.y + player.size / 2
        local e_cx = enemy.x + enemy.size / 2
        local e_cy = enemy.y + enemy.size / 2

        -- İki merkez arasındaki mesafe (Pisagor teoremi)
        local distance = math.sqrt((p_cx - e_cx) ^ 2 + (p_cy - e_cy) ^ 2)

        -- Eğer mesafe 60 pikselden azsa ve engel oyuncunun hizasını yeni geçtiyse (Örn: y koordinatı yakınsa)
        -- Ve bu engele daha önce "near-miss" puanı verilmediyse (bunun için engele bir flag ekleyebiliriz)
        if distance < 65 and not enemy.missed and not game_over then
            enemy.missed = true -- Aynı engelden defalarca puan almamak için
            score = score + 2   -- Yakın geçişe +2 ekstra puan!

            -- Ekranı hafifçe sallayarak oyuncuya geri bildirim verelim (Micro-shading)
            shake_duration = 0.05
            shake_magnitude = 3
        end

        -- Ekrandan çıkan engelleri temizle ve puan yaz
        if enemy.y > love.graphics.getHeight() then
            table.remove(enemies, i)
            score = score + 1
            -- Oyun zorlaşsın: Her puanda hız biraz artsın
            enemy_speed = enemy_speed + 6
        end
    end

    -- Parçacık emisyon yerini oyuncunun merkezine taşıyoruz
    if not game_over then
        trail_system:setPosition(player.x + player.size / 2, player.y + player.size / 2)
        trail_system:update(dt) -- Sistemi ilerlet
    else
        trail_system:stop()     -- Oyun bittiyse yeni parçacık üretme
    end

    -- Ekran sallanma zamanlayıcısını güncelle
    if shake_duration > 0 then
        shake_duration = shake_duration - dt
    else
        shake_magnitude = 0
    end
end

-- Ekrana çizim yapma fonksiyonu (Her karede yenilenir)
function love.draw()
    -- ALTIN KURAL: Ekranı SADECE EN BAŞTA BİR KERE TEMİZLİYORUZ (Unity'deki Clear Flags gibi)
    love.graphics.clear(0.05, 0.05, 0.1)

    -- GÖRSEL DEĞİŞİKLİK: Ekran Sallama Matrisi
    -- Çizim matrisini sakla (Push)
    love.graphics.push()
    if shake_duration > 0 then
        -- Unity'deki Random.insideUnitCircle * magnitude mantığı
        local dx = love.math.random(-shake_magnitude, shake_magnitude)
        local dy = love.math.random(-shake_magnitude, shake_magnitude)
        love.graphics.translate(dx, dy)
    end

    -- 1. PARÇACIKLARI ÇİZ (Oyuncunun arkasında kalması için en önce çiziyoruz)
    -- BlendMode'u Additive (eklemeli) yapıyoruz ki üst üste binen parçacıklar parlasın (Neon efekti)
    love.graphics.setBlendMode("add")
    love.graphics.draw(trail_system, 0, 0)
    love.graphics.setBlendMode("alpha") -- Diğer objeler için normal şeffaflık moduna geri dön

    -- 2. OYUNCUYU ÇİZ (Neon Yeşil)
    love.graphics.setColor(0, 1, 0.5)
    love.graphics.rectangle("fill", player.x, player.y, player.size, player.size)

    -- 3. ENGELLERİ ÇİZ (Neon Pembe)
    love.graphics.setColor(1, 0, 0.4)
    for i, enemy in ipairs(enemies) do
        love.graphics.rectangle("fill", enemy.x, enemy.y, enemy.size, enemy.size)
    end

    love.graphics.pop()

    -- Skor ve Oyun Bitti yazıları burada kalmalı (Sallantıdan etkilenmesinler diye)
    -- 4. SKORU VE YAZILARI ÇİZ (En önde görünmesi için en son çizilir)
    love.graphics.setColor(1, 1, 1)
    -- Sondaki ölçek çarpanlarını 1 yaptık çünkü font zaten 24px boyutunda keskin!
    love.graphics.print("Score: " .. score, 10, 10, 0, 1, 1)

    if debug then
        love.graphics.setColor(1, 1, 1)
        -- Sondaki ölçek çarpanlarını 1 yaptık çünkü font zaten 24px boyutunda keskin!
        love.graphics.print("Player Velocity: " .. math.sqrt(moveVector.x ^ 2 + moveVector.y ^ 2), 10, 10, 0, 1, 1)
    end

    if game_over then
        love.graphics.setColor(1, 0, 0)
        -- Oyun bitti yazısı için belki daha da büyük bir font istersen,
        -- love.load'da ikinci bir font tanımlayıp burada love.graphics.setFont() ile değiştirebilirsin.
        love.graphics.print("GAME OVER!", love.graphics.getWidth() / 2 - 80,
            love.graphics.getHeight() / 2 - 30, 0, 1, 1)
        love.graphics.print("PRESS R TO RESTART", love.graphics.getWidth() / 2 - 130,
            love.graphics.getHeight() / 2, 0, 1, 1)
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
        -- Eski sıfırlama kodları
        enemies = {}
        enemy_speed = 200
        enemy_spawn_timer = 0
        score = 0
        game_over = false
        player.x = 400
        player.y = 500 -- Eğer dikey hareketi eklediysen Y'yi de sıfırlayalım

        -- BUG FIX: Parçacık sistemini yeniden uyandırıyoruz (Unity'deki particleSystem.Play())
        trail_system:start()
    end
end

-- Genel bir vektör normalizasyon fonksiyonu
function normalize(x, y)
    local length = math.sqrt(x * x + y * y)
    if length > 0 then
        return x / length, y / length
    end
    return 0, 0
end
