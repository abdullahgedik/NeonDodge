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
    Player.dash_duration = 0.12        -- Dash süresi (Saniyenin onda biri kadar, anlık patlama)
    Player.dash_cooldown = 1.0         -- Tekrar dash atabilmek için 1 saniye bekleme süresi
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

    -- Trail güncellemesi (Dash atarken parçacık sayısını coşturuyoruz)
    Player.trail:setPosition(Player.x + Player.size / 2, Player.y + Player.size / 2)
    Player.trail:update(dt)
end

function Player.draw()
    -- Önce trail (arkada kalsın)
    love.graphics.setBlendMode("add")
    love.graphics.draw(Player.trail, 0, 0)
    love.graphics.setBlendMode("alpha")

    -- Sonra oyuncu küpü
    love.graphics.setColor(0, 1, 0.5)
    love.graphics.rectangle("fill", Player.x, Player.y, Player.size, Player.size)
end

-- Can azaltma fonksiyonuna, oyun bittiğinde main.lua'yı tetikleyecek bir callback ekliyoruz
function Player.take_damage(amount, on_death_callback)
    Player.lives = Player.lives - amount

    -- Eğer can 0 veya altına düşerse
    if Player.lives <= 0 then
        Player.lives = 0
        -- Unity'deki invoke/event tetikleme mantığı:
        -- Eğer main.lua bize bir ölüm fonksiyonu pasladıysa onu çalıştır diyoruz
        if on_death_callback then
            on_death_callback()
        end
    end
end

function Player.load_particles()
    -- Parçacık sistemini de oyuncunun bir alt bileşeni (Component) gibi buraya bağlıyoruz
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
    Player.trail:setColors(0, 1, 0.5, 0.8, 0, 1, 0.5, 0)
end

function Player.input(moveInput)
    if love.keyboard.isDown("left") or love.keyboard.isDown("a") then moveInput.x = moveInput.x - 1 end
    if love.keyboard.isDown("right") or love.keyboard.isDown("d") then moveInput.x = moveInput.x + 1 end
    if love.keyboard.isDown("up") or love.keyboard.isDown("w") then moveInput.y = moveInput.y - 1 end
    if love.keyboard.isDown("down") or love.keyboard.isDown("s") then moveInput.y = moveInput.y + 1 end
end

function Player.bounds()
    -- Ekran sınırları koruması
    if Player.x < 0 then Player.x = 0 end
    if Player.x > love.graphics.getWidth() - Player.size then Player.x = love.graphics.getWidth() - Player.size end
    if Player.y < 0 then Player.y = 0 end
    if Player.y > love.graphics.getHeight() - Player.size then Player.y = love.graphics.getHeight() - Player.size end
end

local function normalizeVector(x, y) --Will be implemented in the future for diagonal movement normalization
    local length = math.sqrt(x * x + y * y)
    if length == 0 then
        return 0, 0
    else
        return x / length, y / length
    end
end

function Player.move(dt)
    local moveInput = { x = 0, y = 0 }
    local moveVector = { x = 0, y = 0 }

    Player.input(moveInput)

    -- 8 Yönlü Normalizasyon
    if (math.abs(moveInput.x) == 1 and math.abs(moveInput.y) == 1) then
        moveVector.x = moveInput.x / math.sqrt(2)
        moveVector.y = moveInput.y / math.sqrt(2)
    else
        moveVector.x = moveInput.x
        moveVector.y = moveInput.y
    end

    -- --- BUG FIX: DASH BAŞLANGIÇ KONTROLÜ BURADAN KALDIRILDI ---
    -- Girdi kontrolünü buradaki her kare çalışan (polling) alandan temizledik.

    -- --- HAREKET UYGULAMASI ---
    if Player.is_dashing then
        Player.x = Player.x + Player.dash_dir.x * Player.dash_speed * dt
        Player.y = Player.y + Player.dash_dir.y * Player.dash_speed * dt

        Player.dash_time_left = Player.dash_time_left - dt
        if Player.dash_time_left <= 0 then
            Player.is_dashing = false
            Player.trail:setEmissionRate(60)
        end
    else
        -- Normal Hareket
        Player.x = Player.x + moveVector.x * Player.speed * dt
        Player.y = Player.y + moveVector.y * Player.speed * dt
    end

    Player.bounds()
end

-- --- YENI EVENT: TIKLAMA BAŞINA TETİKLENEN ALAN ---
function Player.keypressed(key)
    -- Oyun duraklatılmışsa veya oyuncu ölmüşse girdileri reddet
    if Player.is_paused or Player.lives <= 0 then return end

    -- Sol Shift veya Sağ Shift tuşuna İLK BASILDIĞI AN ve Cooldown bittiyse:
    if (key == "lshift" or key == "rshift") and Player.dash_timer <= 0 then
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

        -- Oyuncu dururken dash atamasın, mutlaka bir hareket yönü olmalı
        if moveVector.x ~= 0 or moveVector.y ~= 0 then
            Player.is_dashing = true
            Player.dash_time_left = Player.dash_duration
            Player.dash_timer = Player.dash_cooldown
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
