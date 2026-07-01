local UI = {}

function UI.load()
    -- Jilet gibi keskin fontlarımızı yüklüyoruz
    UI.main_font = love.graphics.newFont(24)
    UI.title_font = love.graphics.newFont(40)
end

function UI.draw(score, game_over)
    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(UI.main_font)
    love.graphics.print("Score: " .. score, 10, 10)

    if game_over then
        love.graphics.setFont(UI.title_font)
        love.graphics.setColor(1, 0, 0)
        love.graphics.print("GAME OVER!", love.graphics.getWidth() / 2 - 120, love.graphics.getHeight() / 2 - 40)

        love.graphics.setFont(UI.main_font)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print("Press 'R' to restart", love.graphics.getWidth() / 2 - 110,
            love.graphics.getHeight() / 2 + 20)
    end
end

return UI
