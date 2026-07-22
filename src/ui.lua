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

function UI.draw_menu(high_score)
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

    if high_score and high_score > 0 then
        love.graphics.setColor(1, 0.9, 0.2)
        local hs_text = "High Score: " .. high_score
        local hs_width = UI.main_font:getWidth(hs_text)
        love.graphics.print(hs_text, (love.graphics.getWidth() - hs_width) / 2, love.graphics.getHeight() / 2 + 50)
    end
end

function UI.card_layout()
    local card_width, card_height = 220, 300
    local gap = 30
    local total_width = card_width * 3 + gap * 2
    local start_x = (love.graphics.getWidth() - total_width) / 2
    local y = 160

    local rects = {}
    for i = 1, 3 do
        local x = start_x + (i - 1) * (card_width + gap)
        table.insert(rects, { x = x, y = y, w = card_width, h = card_height })
    end

    return rects
end

function UI.draw_card_select(cards, cursor_index)
    love.graphics.setColor(0, 0, 0, 0.75)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())

    love.graphics.setFont(UI.title_font)
    love.graphics.setColor(0, 1, 0.85)
    local title_text = "WAVE CLEAR"
    local t_width = UI.title_font:getWidth(title_text)
    love.graphics.print(title_text, (love.graphics.getWidth() - t_width) / 2, 60)

    love.graphics.setFont(UI.main_font)
    love.graphics.setColor(1, 1, 1)
    local sub_text = "Choose an upgrade"
    local sub_width = UI.main_font:getWidth(sub_text)
    love.graphics.print(sub_text, (love.graphics.getWidth() - sub_width) / 2, 105)

    local rects = UI.card_layout()

    for i, rect in ipairs(rects) do
        local card = cards and cards[i]
        if card then
            local is_hovered = cursor_index == i

            love.graphics.setColor(0.08, 0.08, 0.15, 0.95)
            love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 10, 10)

            love.graphics.setLineWidth(is_hovered and 4 or 2)
            if is_hovered then
                love.graphics.setColor(0, 1, 0.85, 1)
            else
                love.graphics.setColor(0.4, 0.5, 0.6, 0.8)
            end
            love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h, 10, 10)
            love.graphics.setLineWidth(1)

            love.graphics.setColor(1, 0.9, 0.2)
            love.graphics.print(tostring(i), rect.x + 14, rect.y + 12)

            love.graphics.setColor(0, 1, 0.85)
            love.graphics.printf(card.name, rect.x + 14, rect.y + 50, rect.w - 28, "center")

            love.graphics.setColor(1, 1, 1)
            love.graphics.printf(card.description, rect.x + 14, rect.y + 100, rect.w - 28, "center")
        end
    end

    love.graphics.setColor(0.7, 0.75, 0.8)
    local hint_text = "Click a card, press 1/2/3, or use D-pad + A"
    local hint_width = UI.main_font:getWidth(hint_text)
    love.graphics.print(hint_text, (love.graphics.getWidth() - hint_width) / 2, 480)
end

function UI.draw(state, score, player_lives, collected_orb_amount, wave, boss_active, high_score, cards, cursor_index)
    if state == GameState.MENU then
        UI.draw_menu(high_score)
        return
    end

    if state == GameState.CARD_SELECT then
        UI.draw_card_select(cards, cursor_index)
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

        if high_score then
            local is_new_record = score >= high_score and score > 0
            local hs_text = is_new_record and ("New High Score: " .. high_score .. "!") or ("High Score: " .. high_score)

            love.graphics.setColor(1, 0.9, 0.2)
            local hs_width = UI.main_font:getWidth(hs_text)
            love.graphics.print(hs_text, (love.graphics.getWidth() - hs_width) / 2, love.graphics.getHeight() / 2 + 55)
        end
    end
end

return UI
