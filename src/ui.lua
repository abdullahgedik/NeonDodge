local GameState          = require("src/game_state")

local UI                 = {}

-- card-select appear animation: each card starts its own scale/fade-in
-- CARD_STAGGER seconds after the previous one, over CARD_ANIM_DURATION
local CARD_ANIM_DURATION = 0.35
local CARD_STAGGER       = 0.06

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

function UI.draw_card_select(cards, cursor_index, elapsed, chosen_index)
    elapsed = elapsed or CARD_ANIM_DURATION

    -- overlay itself fades in first; everything else rides on top of it
    local overlay_t = math.min(elapsed / CARD_ANIM_DURATION, 1)
    love.graphics.setColor(0, 0, 0, 0.75 * overlay_t)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())

    if overlay_t <= 0 then return end

    love.graphics.setFont(UI.title_font)
    love.graphics.setColor(0, 1, 0.85, overlay_t)
    local title_text = "WAVE CLEAR"
    local t_width = UI.title_font:getWidth(title_text)
    love.graphics.print(title_text, (love.graphics.getWidth() - t_width) / 2, 60)

    love.graphics.setFont(UI.main_font)
    love.graphics.setColor(1, 1, 1, overlay_t)
    local sub_text = "Choose an upgrade"
    local sub_width = UI.main_font:getWidth(sub_text)
    love.graphics.print(sub_text, (love.graphics.getWidth() - sub_width) / 2, 105)

    local rects = UI.card_layout()

    for i, rect in ipairs(rects) do
        local card = cards and cards[i]
        if card then
            -- cascade: card i doesn't start animating until the previous
            -- one is already CARD_STAGGER seconds into its own animation
            local card_t = math.max(0, math.min((elapsed - (i - 1) * CARD_STAGGER) / CARD_ANIM_DURATION, 1))

            if card_t > 0 then
                local is_hovered = cursor_index == i
                local is_chosen = chosen_index == i
                local is_other_chosen = chosen_index ~= nil and not is_chosen

                -- ease-out: scales up from 85% and rises into place, rather
                -- than just popping straight to full size
                local eased = 1 - (1 - card_t) ^ 3
                local scale = 0.85 + 0.15 * eased
                local rise = (1 - eased) * 24
                local alpha = eased * (is_other_chosen and 0.35 or 1)

                local cx, cy = rect.x + rect.w / 2, rect.y + rect.h / 2

                love.graphics.push()
                love.graphics.translate(cx, cy + rise)
                love.graphics.scale(scale, scale)
                love.graphics.translate(-cx, -cy)

                love.graphics.setColor(0.08, 0.08, 0.15, 0.95 * alpha)
                love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 10, 10)

                love.graphics.setLineWidth((is_hovered or is_chosen) and 4 or 2)
                if is_chosen then
                    love.graphics.setColor(1, 0.9, 0.2, alpha)
                elseif is_hovered then
                    love.graphics.setColor(0, 1, 0.85, alpha)
                else
                    love.graphics.setColor(0.4, 0.5, 0.6, 0.8 * alpha)
                end
                love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h, 10, 10)
                love.graphics.setLineWidth(1)

                love.graphics.setColor(1, 0.9, 0.2, alpha)
                love.graphics.print(tostring(i), rect.x + 14, rect.y + 12)

                love.graphics.setColor(0, 1, 0.85, alpha)
                love.graphics.printf(card.name, rect.x + 14, rect.y + 50, rect.w - 28, "center")

                love.graphics.setColor(1, 1, 1, alpha)
                love.graphics.printf(card.description, rect.x + 14, rect.y + 100, rect.w - 28, "center")

                love.graphics.pop()
            end
        end
    end

    love.graphics.setColor(0.7, 0.75, 0.8, overlay_t)
    local hint_text = "Click a card, press 1/2/3, or use D-pad + A"
    local hint_width = UI.main_font:getWidth(hint_text)
    love.graphics.print(hint_text, (love.graphics.getWidth() - hint_width) / 2, 480)

    love.graphics.setColor(1, 1, 1, 1)
end

function UI.draw(state, score, player_lives, collected_orb_amount, wave, boss_active, high_score, cards, cursor_index,
                 boss_incoming, card_select_elapsed, chosen_index, storm_incoming, storm_active)
    if state == GameState.MENU then
        UI.draw_menu(high_score)
        return
    end

    if state == GameState.CARD_SELECT then
        UI.draw_card_select(cards, cursor_index, card_select_elapsed, chosen_index)
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
    elseif boss_incoming then
        local warn_text = "BOSS INCOMING"
        local warn_width = UI.main_font:getWidth(warn_text)
        -- pulses so it reads as a telegraph/warning, not a static label
        local pulse = 0.6 + 0.4 * math.abs(math.sin(love.timer.getTime() * 6))
        love.graphics.setColor(1, 0.3, 0.2, pulse)
        love.graphics.print(warn_text, (love.graphics.getWidth() - warn_width) / 2, 80)
        love.graphics.setColor(1, 1, 1, 1)
    elseif storm_active then
        local storm_text = "HAZARD STORM"
        local storm_width = UI.main_font:getWidth(storm_text)
        -- a faster, harsher flicker than the boss banners -- this one means
        -- "danger right now", not "danger soon"
        local flicker = 0.5 + 0.5 * math.abs(math.sin(love.timer.getTime() * 12))
        love.graphics.setColor(1, 0.5, 0.1, flicker)
        love.graphics.print(storm_text, (love.graphics.getWidth() - storm_width) / 2, 80)
        love.graphics.setColor(1, 1, 1, 1)
    elseif storm_incoming then
        local warn_text = "STORM INCOMING"
        local warn_width = UI.main_font:getWidth(warn_text)
        local pulse = 0.6 + 0.4 * math.abs(math.sin(love.timer.getTime() * 6))
        love.graphics.setColor(1, 0.7, 0.2, pulse)
        love.graphics.print(warn_text, (love.graphics.getWidth() - warn_width) / 2, 80)
        love.graphics.setColor(1, 1, 1, 1)
    end

    local orbs = collected_orb_amount or 0
    -- progress toward the next 5-orb milestone, not the lifetime total --
    -- shows 5/5 right at the trigger moment rather than looping back to 0/5
    local progress = orbs % 5
    if progress == 0 and orbs > 0 then progress = 5 end
    local orb_text = "Orbs: " .. progress .. "/5"
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
