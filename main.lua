-- main.lua
local Player               = require("src/player")
local Enemy                = require("src/enemy")
local Orb                  = require("src/orb")
local VoidOrb              = require("src/void_orb") -- Yeni ekledik
local UI                   = require("src/ui")

local score                = 0
local game_over            = false
local shake_duration       = 0
local shake_magnitude      = 0
local enemy_spawn_rate     = 0.65
local orb_spawn_rate       = 1.5
local void_orb_spawn_rate  = 4.5 -- Nadir gelsin (Her 4.5 saniyede bir)
local collected_orb_amount = 0
local is_paused            = false

function love.load()
    Player.load()
    Enemy.load()
    Orb.load()
    VoidOrb.load() -- Yeni ekledik
    UI.load()
end

function love.update(dt)
    if is_paused then return end

    if shake_duration > 0 then
        shake_duration = shake_duration - dt
    else
        shake_magnitude = 0
    end

    Player.update(dt, game_over)

    Enemy.update(dt, game_over, Player,
        function(index) love.on_enemy_player_collision(index) end,
        enemy_spawn_rate
    )

    Orb.update(dt, game_over, Player,
        function(index) love.on_orb_player_collision(index) end,
        orb_spawn_rate
    )

    -- --- YENİ: MOR ORB GÜNCELLEMESİ ---
    VoidOrb.update(dt, game_over, Player,
        -- 1. Callback: Oyuncu mor orbu toplarsa (+10 Puan)
        function(index)
            VoidOrb.remove(index)
            score = score + 10
            love.shake(0.15, 4) -- Toplama geri bildirimi
        end,

        -- 2. Callback: Mor orb tabandan kaçarsa (Patlar ve Hasar Verir)
        function(index)
            VoidOrb.remove(index)
            love.shake(0.5, 15) -- Büyük patlama sarsıntısı!

            Player.take_damage(1, function()
                game_over = true
                love.shake(0.6, 20)
            end)
        end,
        void_orb_spawn_rate
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
    VoidOrb.draw() -- Yeni ekledik

    love.graphics.pop()

    UI.draw(score, game_over, Player.lives, collected_orb_amount)
end

function love.on_enemy_player_collision(index)
    -- BUG FIX 1: Dışarıdan listeye müdahale etmek yerine düşman modülüne "bu indeksi sil" diyoruz
    Enemy.remove(index)

    -- Ekran sarsıntısı tetikle
    love.shake(0.3, 10)

    -- BUG FIX 2: player.lua'ya hasar verdiriyoruz ve eğer ölürse ne yapacağını anonim fonksiyonla bildiriyoruz
    Player.take_damage(1,
        function()
            game_over = true
            love.shake(0.6, 20)
        end
    )
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

function love.pause()
    Player.pause()
    Enemy.pause()
    Orb.pause()
    VoidOrb.pause()
    UI.pause()
end

function love.resume()
    Player.resume()
    Enemy.resume()
    Orb.resume()
    VoidOrb.resume()
    UI.resume()
end

function love.keypressed(key)
    if key == "r" and game_over then
        score = 0
        collected_orb_amount = 0
        game_over = false
        is_paused = false
        Player.reset()
        Enemy.reset()
        Orb.reset()
        VoidOrb.reset() -- Yeni ekledik
        UI.resume()
    end

    if key == "escape" then love.event.quit() end

    if key == "p" and not game_over then
        if is_paused then
            love.resume()
            is_paused = false
        else
            love.pause()
            is_paused = true
        end
    end

    Player.keypressed(key)
end
