-- Modülleri içeri aktarıyoruz
local Player               = require("src/player")
local Enemy                = require("src/enemy")
local Orb                  = require("src/orb")
local UI                   = require("src/ui")

-- Global oyun durumları (Sadece bu dosya içinden erişilebilir)
local score                = 0
local game_over            = false
local shake_duration       = 0
local shake_magnitude      = 0
local enemy_spawn_rate     = 0.65
local orb_spawn_rate       = 1.5
local collected_orb_amount = 0

function love.load()
    Player.load()
    Enemy.load()
    Orb.load()
    UI.load()
end

function love.update(dt)
    -- Ekran Sallanma Zamanlayıcısı
    if shake_duration > 0 then
        shake_duration = shake_duration - dt
    else
        shake_magnitude = 0
    end

    -- Oyuncu durumunu güncelliyoruz (Mevcut game_over durumunu her kare paslıyoruz)
    Player.update(dt, game_over)

    -- Düşman Modülü Güncellemesi
    Enemy.update(dt, game_over, Player,
        -- on_collision callback'i:
        function(index)
            love.on_enemy_player_collision(index)
        end,
        enemy_spawn_rate
    )

    -- Orb Modülü Güncellemesi
    Orb.update(dt, game_over, Player,
        -- on_collision callback'i:
        function(index)
            love.on_orb_player_collision(index)
        end,
        orb_spawn_rate
    )
end

function love.draw()
    love.graphics.clear(0.05, 0.05, 0.1)

    love.graphics.push()
    if shake_duration > 0 then
        local dx = love.math.random(-shake_magnitude, shake_magnitude)
        local dy = love.math.random(-shake_magnitude, shake_magnitude)
        love.graphics.translate(dx, dy)
    end

    Player.draw()
    Enemy.draw()
    Orb.draw()

    love.graphics.pop()

    -- UI modülüne toplanan orb miktarını da gönderelim ki sağ üstte gösterebilsin
    UI.draw(score, game_over, Player.lives, collected_orb_amount)
end

function love.on_enemy_player_collision(index)
    -- BUG FIX 1: Dışarıdan listeye müdahale etmek yerine düşman modülüne "bu indeksi sil" diyoruz
    Enemy.remove(index)

    -- Ekran sarsıntısı tetikle
    love.shake(0.3, 10)

    -- BUG FIX 2: player.lua'ya hasar verdiriyoruz ve eğer ölürse ne yapacağını anonim fonksiyonla bildiriyoruz
    Player.take_damage(1, function()
        game_over = true
        love.shake(0.6, 20)
    end)
end

function love.on_orb_player_collision(index)
    -- BUG FIX 1: Orb listesini korumak için silme yetkisini kendi modülüne verdik
    Orb.remove(index)

    score = score + 5
    collected_orb_amount = collected_orb_amount + 1

    -- Can yenileme mekaniği (Max can sınırını aşamaz)
    if (collected_orb_amount % 5 == 0) then
        Player.lives = math.min(Player.lives + 1, Player.max_lives)
        love.shake(0.1, 2) -- Can alınca tatlı bir geri bildirim sarsıntısı
    end
end

function love.shake(duration, magnitude)
    shake_duration = duration
    shake_magnitude = magnitude
end

function love.keypressed(key)
    if key == "r" and game_over then
        score = 0
        collected_orb_amount = 0 -- Yeni oyunda toplanan orb sayacını sıfırla
        game_over = false
        Player.reset()
        Enemy.reset()
        Orb.reset()
    end
end
