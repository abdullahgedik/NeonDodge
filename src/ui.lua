local GameState = require("src/game_state")

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

function UI.draw_menu()
    love.graphics.setFont(UI.title_font)
    love.graphics.setColor(0, 1, 0.85)

    local title_text = "NEON DODGE"
    local t_width = UI.title_font:getWidth(title_text)
    love.graphics.print(title_text, (love.graphics.getWidth() - t_width) / 2, love.graphics.getHeight() / 2 - 60)

    love.graphics.setFont(UI.main_font)
    love.graphics.setColor(1, 1, 1)

    local start_text = "Press SPACE to start"
    local s_width = UI.main_font:getWidth(start_text)
    love.graphics.print(start_text, (love.graphics.getWidth() - s_width) / 2, love.graphics.getHeight() / 2 + 10)
end

function UI.draw(state, score, player_lives, collected_orb_amount, wave, boss_active)
    if state == GameState.MENU then
        UI.draw_menu()
        return
    end

    for i = 1, player_lives do
        local distance = (i - 1) * 35
        drawHeart(25, 25, distance)
    end

    love.graphics.setFont(UI.main_font)
    love.graphics.setColor(1, 1, 1)

    local score_text = "Score: " .. score
    local text_width = UI.main_font:getWidth(score_text)
    local center_x = (love.graphics.getWidth() - text_width) / 2

    love.graphics.print(score_text, center_x, 20)

    if wave then
        local wave_text = "Wave: " .. wave
        local wave_width = UI.main_font:getWidth(wave_text)
        love.graphics.setColor(0.7, 0.75, 1)
        love.graphics.print(wave_text, (love.graphics.getWidth() - wave_width) / 2, 50)
    end

    if boss_active then
        local boss_text = "BOSS"
        local boss_width = UI.main_font:getWidth(boss_text)
        love.graphics.setColor(1, 0.2, 0.6)
        love.graphics.print(boss_text, (love.graphics.getWidth() - boss_width) / 2, 80)
    end

    local orbs = collected_orb_amount or 0
    local orb_text = "Orbs: " .. orbs .. "/5"
    local orb_width = UI.main_font:getWidth(orb_text)

    love.graphics.setColor(1, 0.9, 0.2)
    love.graphics.print(orb_text, love.graphics.getWidth() - orb_width - 25, 20)

    if state == GameState.PAUSED then
        love.graphics.setFont(UI.title_font)
        love.graphics.setColor(0, 0.8, 1)

        local pause_text = "PAUSED"
        local p_width = UI.title_font:getWidth(pause_text)
        love.graphics.print(pause_text, (love.graphics.getWidth() - p_width) / 2, love.graphics.getHeight() / 2 - 40)

        love.graphics.setFont(UI.main_font)
        love.graphics.setColor(1, 1, 1)
        local resume_text = "Press 'P' to resume"
        local res_width = UI.main_font:getWidth(resume_text)
        love.graphics.print(resume_text, (love.graphics.getWidth() - res_width) / 2, love.graphics.getHeight() / 2 + 10)
    end

    if state == GameState.GAME_OVER then
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
