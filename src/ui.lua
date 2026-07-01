local UI = {}

function UI.load()
    -- Jilet gibi keskin fontlarımızı yüklüyoruz
    UI.main_font = love.graphics.newFont(24)
    UI.title_font = love.graphics.newFont(40)
end

-- Yardımcı Fonksiyon: Tek bir neon kalp çizen fonksiyon
local function drawHeart(x, y, distance)
    love.graphics.setColor(1, 0.2, 0.3) -- Neon Kırmızı/Pembe
    -- Daha düzgün bir kalp: iki daire (lobes) ve alt üçgen/poligon
    local ox = distance
    local lcx = x + 6 + ox
    local rcx = x + 18 + ox
    local cy = y + 6
    local radius = 6

    -- Lobes
    love.graphics.circle("fill", lcx, cy, radius)
    love.graphics.circle("fill", rcx, cy, radius)

    -- Alt kısmı (üçgenimsi kısım)
    local points = {
        x + ox, y + 8,
        x + 12 + ox, y + 24,
        x + 24 + ox, y + 8,
    }
    love.graphics.polygon("fill", points)
end

function UI.draw(score, game_over, player_lives)
    -- 1. SOL ÜSTE KALPLERİ ÇİZMEK
    -- Döngü oyuncunun kalan canı kadar döner (Unity'deki UI Layout Group mantığı)
    for i = 1, player_lives do
        local distance = (i - 1) * 35 -- Her kalp arasına 35 piksel boşluk bırak
        drawHeart(25, 25, distance)   -- X, Y, Boyut
    end

    -- 2. SKOR TABELASINI ORTALAMAK
    love.graphics.setFont(UI.main_font)
    love.graphics.setColor(1, 1, 1)

    local score_text = "Score: " .. score
    -- Unity'deki RectTransform hileleri gibi: Metnin genişliğini bulup ekrandan çıkarıyoruz
    local text_width = UI.main_font:getWidth(score_text)
    local center_x = (love.graphics.getWidth() - text_width) / 2

    love.graphics.print(score_text, center_x, 20)

    -- 3. OYUN BİTTİ EKRANI
    if game_over then
        love.graphics.setFont(UI.title_font)
        love.graphics.setColor(1, 0, 0)

        local game_over_text = "GAME OVER!"
        local go_width = UI.title_font:getWidth(game_over_text)
        love.graphics.print(game_over_text, (love.graphics.getWidth() - go_width) / 2, love.graphics.getHeight() / 2 - 40)

        love.graphics.setFont(UI.main_font)
        love.graphics.setColor(1, 1, 1)

        local restart_text = "Press 'R' to restart.."
        local r_width = UI.main_font:getWidth(restart_text)
        love.graphics.print(restart_text, (love.graphics.getWidth() - r_width) / 2, love.graphics.getHeight() / 2 + 20)
    end
end

return UI
