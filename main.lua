-- Modülleri içeri aktarıyoruz (Unity'deki C# referans tanımlamaları gibi)
local Player          = require("src/player")
local Enemy           = require("src/enemy")
local UI              = require("src/ui")

-- Global oyun durumları
local score           = 0
local game_over       = false
local shake_duration  = 0
local shake_magnitude = 0

function love.load()
    Player.load()
    Enemy.load()
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
    Enemy.update(dt, game_over, Player,
        -- Çarpışma olduğunda çalışacak fonksiyon (on_collision):
        function(index)
            game_over = true
            shake_duration = 0.25
            shake_magnitude = 18
            table.remove(Enemy.list, index)
        end,
        -- Near-miss olduğunda çalışacak fonksiyon (on_near_miss):
        function()
            score = score + 2
            shake_duration = 0.05
            shake_magnitude = 2
        end,
        -- Düşman yaratma oranı
        0.65
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

    love.graphics.pop()

    -- UI sallantı matrisinin dışında kalıyor (Canvas mantığı)
    UI.draw(score, game_over)
end

function love.keypressed(key)
    if key == "r" and game_over then
        score = 0
        game_over = false
        Player.reset()
        Enemy.reset()
    end
end
