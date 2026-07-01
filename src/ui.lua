local UI = {}

function UI.load()
    UI.main_font = love.graphics.newFont(24)
    UI.title_font = love.graphics.newFont(40)
end

local function drawHeart(x, y, distance)
    love.graphics.setColor(1, 0.2, 0.3)
    local ox = distance
    local lcx = x + 6 + ox
    local rcx = x + 18 + ox
    local cy = y + 6
    local radius = 6

    love.graphics.circle("fill", lcx, cy, radius)
    love.graphics.circle("fill", rcx, cy, radius)

    local points = {
        x + ox, y + 8,
        x + 12 + ox, y + 24,
        x + 24 + ox, y + 8,
    }
    love.graphics.polygon("fill", points)
end

-- BUG FIX 1: collected_orb_amount parametresini buraya ekledik
function UI.draw(score, game_over, player_lives, collected_orb_amount)
    -- 1. SOL ÜSTE KALPLERİ ÇİZMEK
    for i = 1, player_lives do
        local distance = (i - 1) * 35
        drawHeart(25, 25, distance)
    end

    -- 2. SKOR TABELASINI ORTALAMAK
    love.graphics.setFont(UI.main_font)
    love.graphics.setColor(1, 1, 1)

    local score_text = "Score: " .. score
    local text_width = UI.main_font:getWidth(score_text)
    local center_x = (love.graphics.getWidth() - text_width) / 2

    love.graphics.print(score_text, center_x, 20)

    -- BUG FIX 2: SAĞ ÜSTE ORB SAYACINI ÇİZMEK
    -- Eğer oyun henüz başlamışsa ve veri gelmişse hata vermemesi için koruma (default: 0)
    local orbs = collected_orb_amount or 0
    local orb_text = "Orbs: " .. orbs .. "/5"
    local orb_width = UI.main_font:getWidth(orb_text)

    love.graphics.setColor(1, 0.9, 0.2) -- Altın sarısı neon renk
    -- Sağ kenardan 25 piksel içeride olacak şekilde hizalıyoruz
    love.graphics.print(orb_text, love.graphics.getWidth() - orb_width - 25, 20)

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
