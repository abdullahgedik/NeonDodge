local Player = {}

function Player.load()
    Player.x = love.graphics.getWidth() / 2 - 15
    Player.y = love.graphics.getHeight() - 100
    Player.size = 35
    Player.speed = 325
    Player.lives = 3
    Player.max_lives = 3
    Player.is_paused = false

    -- --- DASH MEKANİĞİ DEĞİŞKENLERİ ---
    Player.dash_speed = 900            -- Dash hızı (Normal hızın ~3 katı)
    Player.dash_duration = 0.10        -- Dash süresi (Saniyenin onda biri kadar, anlık patlama)
    Player.dash_cooldown = 0.75        -- Tekrar dash atabilmek için 1 saniye bekleme süresi
    Player.dash_timer = 0              -- Cooldown sayacı
    Player.dash_time_left = 0          -- Dash'in bitmesine kalan süre
    Player.is_dashing = false          -- Dash atıyor mu?
    Player.dash_dir = { x = 0, y = 0 } -- Dash yönü

    Player.load_particles()
end

function Player.update(dt, game_over)
    if game_over then
        Player.trail:stop()
        return
    end

    if Player.is_paused then return end

    -- Cooldown sayacını azalt
    if Player.dash_timer > 0 then
        Player.dash_timer = Player.dash_timer - dt
    end

    -- Hareket ve Dash lojiği
    Player.move(dt)

    -- --- YENİ: PARTİKÜL RENK SENKRONİZASYONU ---
    -- Oyuncunun draw'daki renk mantığının aynısını buraya kuruyoruz.
    -- Böylece yeni doğan partiküller karakterin o anki rengini alır.
    if Player.dash_timer <= 0 and not Player.is_dashing then
        -- Dash Hazır: Parlak neon elektrik turkuazı partiküller
        Player.trail:setColors(0, 1, 0.85, 0.8, 0, 1, 0.85, 0)
    else
        -- Dash Atıyor veya Cooldown'da: Mat yeşil partiküller
        Player.trail:setColors(0.0, 0.6, 0.3, 0.8, 0.0, 0.6, 0.3, 0)
    end

    -- Trail güncellemesi (Dash atarken parçacık sayısını coşturuyoruz)
    Player.trail:setPosition(Player.x + Player.size / 2, Player.y + Player.size / 2)
    Player.trail:update(dt)
end

function Player.draw()
    -- --- KRİTİK DÜZENLEME ---
    -- LÖVE2D'nin partikülleri başka renklerle (kırmızı/sarı) maskelememesi için
    -- partikül çiziminden hemen önce global rengi saf beyaza (1, 1, 1) sıfırlıyoruz.
    love.graphics.setColor(1, 1, 1, 1)

    -- 1. ÖNCE TRAIL (Arkada kalması için en üstte çiziyoruz)
    love.graphics.setBlendMode("add")
    love.graphics.draw(Player.trail, 0, 0)
    love.graphics.setBlendMode("alpha")

    -- 2. --- DASH HAZIRLIK RENK KONTROLÜ ---
    if Player.dash_timer <= 0 and not Player.is_dashing then
        -- Dash Hazır: Parlak neon elektrik turkuazı
        love.graphics.setColor(0, 1, 0.85)
    else
        -- Dash Şarj Oluyor veya Dash Atıyor: Mat yeşil
        love.graphics.setColor(0.0, 0.6, 0.3)
    end

    -- OYUNCU KÜPÜ ÇİZİMİ
    love.graphics.rectangle("fill", Player.x, Player.y, Player.size, Player.size)

    -- 3. --- KARE ANİMASYONU ---
    if Player.dash_timer > 0 then
        local ratio = Player.dash_timer / Player.dash_cooldown
        local max_size = Player.size * 2.0
        local current_ind_size = Player.size + (max_size - Player.size) * ratio

        local player_cx = Player.x + Player.size / 2
        local player_cy = Player.y + Player.size / 2
        local ind_x = player_cx - current_ind_size / 2
        local ind_y = player_cy - current_ind_size / 2

        -- Transparanlığı artırılmış soft kare
        love.graphics.setColor(1, 1, 1, 0.04 * ratio)
        love.graphics.rectangle("fill", ind_x, ind_y, current_ind_size, current_ind_size)

        love.graphics.setLineWidth(1.2)
        love.graphics.setColor(1, 1, 1, 0.18 * ratio)
        love.graphics.rectangle("line", ind_x, ind_y, current_ind_size, current_ind_size)
        love.graphics.setLineWidth(1)
    end
end

function Player.take_damage(amount, on_death_callback)
    Player.lives = Player.lives - amount
    if Player.lives <= 0 and on_death_callback then
        on_death_callback()
    end
end

function Player.load_particles()
    local p_data = love.image.newImageData(32, 32)
    for y = 0, 31 do
        for x = 0, 31 do
            local dx = x - 15.5
            local dy = y - 15.5
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist <= 15.5 then
                local alpha = (15.5 - dist) / 15.5
                p_data:setPixel(x, y, 1, 1, 1, alpha)
            end
        end
    end
    local particle_img = love.graphics.newImage(p_data)

    Player.trail = love.graphics.newParticleSystem(particle_img, 1000)
    Player.trail:setParticleLifetime(0.2, 0.4)
    Player.trail:setEmissionRate(60)
    Player.trail:setSizeVariation(0.5)

    -- GÜNCELLEME: Partiküller artık oyuncunun parlak neon turkuaz rengiyle (0, 1, 0.85) doğacak
    -- ve zamanla opaklığı azalarak (0.8 -> 0) yumuşakça yok olacak.
    Player.trail:setColors(0, 1, 0.85, 0.8, 0, 1, 0.85, 0)
end

function Player.input(moveInput)
    if love.keyboard.isDown("left") or love.keyboard.isDown("a") then moveInput.x = moveInput.x - 1 end
    if love.keyboard.isDown("right") or love.keyboard.isDown("d") then moveInput.x = moveInput.x + 1 end
    if love.keyboard.isDown("up") or love.keyboard.isDown("w") then moveInput.y = moveInput.y - 1 end
    if love.keyboard.isDown("down") or love.keyboard.isDown("s") then moveInput.y = moveInput.y + 1 end
end

function Player.bounds()
    if Player.x < 0 then Player.x = 0 end
    if Player.x > love.graphics.getWidth() - Player.size then Player.x = love.graphics.getWidth() - Player.size end
    if Player.y < 0 then Player.y = 0 end
    if Player.y > love.graphics.getHeight() - Player.size then Player.y = love.graphics.getHeight() - Player.size end
end

function Player.move(dt)
    local moveInput = { x = 0, y = 0 }
    local moveVector = { x = 0, y = 0 }

    Player.input(moveInput)

    if (math.abs(moveInput.x) == 1 and math.abs(moveInput.y) == 1) then
        moveVector.x = moveInput.x / math.sqrt(2)
        moveVector.y = moveInput.y / math.sqrt(2)
    else
        moveVector.x = moveInput.x
        moveVector.y = moveInput.y
    end

    -- --- HAREKET UYGULAMASI ---
    if Player.is_dashing then
        Player.x = Player.x + Player.dash_dir.x * Player.dash_speed * dt
        Player.y = Player.y + Player.dash_dir.y * Player.dash_speed * dt

        Player.dash_time_left = Player.dash_time_left - dt

        -- DÜZENLEME: Dash hareketi tam olarak bittiği bu karede cooldown ve animasyon tetikleniyor
        if Player.dash_time_left <= 0 then
            Player.is_dashing = false
            Player.dash_timer = Player.dash_cooldown -- Cooldown sayacı şimdi başlıyor!
            Player.trail:setEmissionRate(60)
        end
    else
        -- Normal Hareket
        Player.x = Player.x + moveVector.x * Player.speed * dt
        Player.y = Player.y + moveVector.y * Player.speed * dt
    end

    Player.bounds()
end

function Player.keypressed(key)
    if Player.is_paused or Player.lives <= 0 then return end

    -- DÜZENLEME: Cooldown bitmiş olmalı VE oyuncu şu an aktif olarak dash atıyor olmamalı
    if (key == "lshift" or key == "rshift") and Player.dash_timer <= 0 and not Player.is_dashing then
        local moveInput = { x = 0, y = 0 }
        Player.input(moveInput)

        local moveVector = { x = 0, y = 0 }
        if (math.abs(moveInput.x) == 1 and math.abs(moveInput.y) == 1) then
            moveVector.x = moveInput.x / math.sqrt(2)
            moveVector.y = moveInput.y / math.sqrt(2)
        else
            moveVector.x = moveInput.x
            moveVector.y = moveInput.y
        end

        if moveVector.x ~= 0 or moveVector.y ~= 0 then
            Player.is_dashing = true
            Player.dash_time_left = Player.dash_duration
            -- DÜZENLEME: Buradaki Player.dash_timer ataması silindi, Player.move içine taşındı
            Player.dash_dir.x = moveVector.x
            Player.dash_dir.y = moveVector.y
            Player.trail:setEmissionRate(300)
        end
    end
end

function Player.pause()
    Player.is_paused = true
    Player.trail:stop()
end

function Player.resume()
    Player.is_paused = false
    Player.trail:start()
end

function Player.reset()
    Player.x = love.graphics.getWidth() / 2 - 15
    Player.y = love.graphics.getHeight() - 100
    Player.lives = Player.max_lives
    Player.dash_timer = 0
    Player.is_dashing = false
    Player.trail:start()
    Player.trail:reset()
    Player.trail:setEmissionRate(60)
end

return Player
