-- Modülleri içeri aktarıyoruz (Unity'deki C# referans tanımlamaları gibi)
local Player               = require("src/player")
local Enemy                = require("src/enemy")
local Orb                  = require("src/orb")
local UI                   = require("src/ui")

-- Global oyun durumları
local score                = 0
local game_over            = false
local shake_duration       = 0
local shake_magnitude      = 0
local enemy_spawn_rate     = 0.65 -- Düşman spawn hızı (saniye cinsinden)
local orb_spawn_rate       = 1.5  -- Orb spawn hızı (saniye cinsinden)
local collected_orb_amount = 0    -- Toplanan orb sayısı

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

    -- Modüllerin Update'lerini çağırıyoruz
    Player.update(dt, game_over)

    -- Düşman modülüne, çarpışma olduğunda ne yapacağını fonksiyon (Callback) olarak paslıyoruz
    -- main.lua içindeki Enemy.update kısmı
    Enemy.update(dt, game_over, Player,
        -- Çarpışma olduğunda (on_collision):
        function(index)
            love.on_enemy_player_collision(index)
        end,
        enemy_spawn_rate
    )

    Orb.update(dt, game_over, Player,
        -- Çarpışma olduğunda (on_collision):
        function(index)
            love.on_orb_player_collision(index)
        end,
        orb_spawn_rate
    )
end

function love.draw()
    love.graphics.clear(0.05, 0.05, 0.1)

    -- Ekran sallama efekti matris push/pop arasında sadece oyun içi objeleri etkilesin
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

    -- UI sallantı matrisinin dışında kalıyor (Canvas mantığı)
    UI.draw(score, game_over, Player.lives)
end

function love.on_enemy_player_collision(index)
    Player.take_damage(1)

    -- Can gitme efektleri (Ekran sarsılsın ve çarpan düşman silinsin)
    shake_duration = 0.3
    shake_magnitude = 10
    table.remove(Enemy.list, index)

    -- Eğer can kalmadıysa oyunu bitir
    if Player.lives <= 0 then
        game_over = true
        shake_duration = 0.6 -- Ölüm sarsıntısı daha büyük olsun
        shake_magnitude = 20
    end
end

function love.on_orb_player_collision(index)
    score = score + 5
    collected_orb_amount = collected_orb_amount + 1
    table.remove(Orb.list, index)

    if (collected_orb_amount % 5 == 0) then
        Player.lives = math.min(Player.lives + 1, Player.max_lives)
    end
end

function love.shake(duration, magnitude)
    shake_duration = duration
    shake_magnitude = magnitude
end

function love.keypressed(key)
    if key == "r" and game_over then
        score = 0
        game_over = false
        Player.reset()
        Enemy.reset()
        Orb.reset()
    end
end
