local GameState          = require("src/game_state")
local Screen             = require("src/screen")

local UI                 = {}

-- card-select appear animation: each card starts its own scale/fade-in
-- CARD_STAGGER seconds after the previous one, over CARD_ANIM_DURATION
local CARD_ANIM_DURATION = 0.35
local CARD_STAGGER       = 0.06

-- shared vertical button-list widget for simple menus (main menu, pause) --
-- unlike the card-select layout these are single-column, centered, and
-- don't need the appear animation since they're not the core roguelike
-- decision point, just navigation
local MENU_ITEM_WIDTH    = 260
local MENU_ITEM_HEIGHT   = 50
local MENU_ITEM_GAP      = 14

UI.MAIN_MENU_OPTIONS     = { "Start Game", "Reset High Score", "Quit" }
UI.PAUSE_MENU_OPTIONS    = { "Resume", "Restart", "Quit to Menu" }

local function main_menu_top_y()
    return Screen.HEIGHT / 2 - 90
end

local function pause_menu_top_y()
    return Screen.HEIGHT / 2 - 50
end

-- nominal sizes in game units -- the actual fonts are built this many game
-- units tall *times the current scale*, so they rasterize at their real
-- on-screen size instead of being stretched (see Screen.new_font)
local MAIN_FONT_SIZE     = 24
local TITLE_FONT_SIZE    = 40

function UI.load()
    UI.refresh_fonts()
end

-- rebuilt whenever the window scale changes (love.resize), since the pixel
-- size a font must be rasterized at depends on it. Skipped when the scale
-- hasn't actually moved, so dragging a window edge doesn't rebuild fonts on
-- every one of the many resize events that generates.
function UI.refresh_fonts()
    if UI.font_scale == Screen.scale then return end

    UI.font_scale = Screen.scale
    UI.main_font = Screen.new_font(MAIN_FONT_SIZE)
    UI.title_font = Screen.new_font(TITLE_FONT_SIZE)
end

-- shared layout for any simple menu -- single source of truth for both
-- drawing and mouse-click hit-testing, same convention as UI.card_layout()
function UI.simple_menu_layout(count, top_y)
    local rects = {}
    for i = 1, count do
        table.insert(rects, {
            x = (Screen.WIDTH - MENU_ITEM_WIDTH) / 2,
            y = top_y + (i - 1) * (MENU_ITEM_HEIGHT + MENU_ITEM_GAP),
            w = MENU_ITEM_WIDTH,
            h = MENU_ITEM_HEIGHT,
        })
    end
    return rects
end

function UI.main_menu_layout()
    return UI.simple_menu_layout(#UI.MAIN_MENU_OPTIONS, main_menu_top_y())
end

function UI.pause_menu_layout()
    return UI.simple_menu_layout(#UI.PAUSE_MENU_OPTIONS, pause_menu_top_y())
end

function UI.draw_simple_menu(labels, cursor_index, top_y, danger_index)
    local rects = UI.simple_menu_layout(#labels, top_y)

    love.graphics.setFont(UI.main_font)

    for i, rect in ipairs(rects) do
        local is_hovered = cursor_index == i
        local is_danger = danger_index == i

        love.graphics.setColor(0.08, 0.08, 0.15, 0.95)
        love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 8, 8)

        love.graphics.setLineWidth((is_hovered or is_danger) and 3 or 2)
        if is_danger then
            love.graphics.setColor(1, 0.3, 0.15, 1)
        elseif is_hovered then
            love.graphics.setColor(0, 1, 0.85, 1)
        else
            love.graphics.setColor(0.4, 0.5, 0.6, 0.7)
        end
        love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h, 8, 8)
        love.graphics.setLineWidth(1)

        if is_danger then
            love.graphics.setColor(1, 0.4, 0.3, 1)
        elseif is_hovered then
            love.graphics.setColor(0, 1, 0.85, 1)
        else
            love.graphics.setColor(1, 1, 1, 1)
        end
        Screen.printf(labels[i], rect.x, rect.y + (rect.h - Screen.text_height(UI.main_font)) / 2, rect.w, "center")
    end

    love.graphics.setColor(1, 1, 1, 1)
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

function UI.draw_menu(high_score, cursor_index, reset_armed)
    love.graphics.setFont(UI.title_font)
    love.graphics.setColor(0, 1, 0.85)

    local title_text = "NEON DODGE"
    local t_width = Screen.text_width(UI.title_font, title_text)
    Screen.print(title_text, (Screen.WIDTH - t_width) / 2, Screen.HEIGHT / 2 - 140)

    -- "Reset High Score" arms instead of firing immediately -- a second
    -- confirm within a few seconds (see main.lua's reset_confirm_timer)
    -- actually resets it, so a misclick can't silently erase the record
    local labels = UI.MAIN_MENU_OPTIONS
    local danger_index = nil
    if reset_armed then
        labels = { labels[1], "Click again to confirm", labels[3] }
        danger_index = 2
    end
    UI.draw_simple_menu(labels, cursor_index, main_menu_top_y(), danger_index)

    if high_score and high_score > 0 then
        love.graphics.setFont(UI.main_font)
        love.graphics.setColor(1, 0.9, 0.2)
        local hs_text = "High Score: " .. high_score
        local hs_width = Screen.text_width(UI.main_font, hs_text)
        Screen.print(hs_text, (Screen.WIDTH - hs_width) / 2, Screen.HEIGHT / 2 + 120)
    end
end

function UI.card_layout()
    local card_width, card_height = 220, 300
    local gap = 30
    local total_width = card_width * 3 + gap * 2
    local start_x = (Screen.WIDTH - total_width) / 2
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
    love.graphics.rectangle("fill", 0, 0, Screen.WIDTH, Screen.HEIGHT)

    if overlay_t <= 0 then return end

    love.graphics.setFont(UI.title_font)
    love.graphics.setColor(0, 1, 0.85, overlay_t)
    local title_text = "WAVE CLEAR"
    local t_width = Screen.text_width(UI.title_font, title_text)
    Screen.print(title_text, (Screen.WIDTH - t_width) / 2, 60)

    love.graphics.setFont(UI.main_font)
    love.graphics.setColor(1, 1, 1, overlay_t)
    local sub_text = "Choose an upgrade"
    local sub_width = Screen.text_width(UI.main_font, sub_text)
    Screen.print(sub_text, (Screen.WIDTH - sub_width) / 2, 105)

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
                Screen.print(tostring(i), rect.x + 14, rect.y + 12)

                love.graphics.setColor(0, 1, 0.85, alpha)
                Screen.printf(card.name, rect.x + 14, rect.y + 50, rect.w - 28, "center")

                love.graphics.setColor(1, 1, 1, alpha)
                Screen.printf(card.description, rect.x + 14, rect.y + 100, rect.w - 28, "center")

                love.graphics.pop()
            end
        end
    end

    love.graphics.setColor(0.7, 0.75, 0.8, overlay_t)
    local hint_text = "Click a card, press 1/2/3, or use D-pad + A"
    local hint_width = Screen.text_width(UI.main_font, hint_text)
    Screen.print(hint_text, (Screen.WIDTH - hint_width) / 2, 480)

    love.graphics.setColor(1, 1, 1, 1)
end

function UI.draw(state, score, player_lives, collected_orb_amount, wave, boss_active, high_score, cards, cursor_index,
                 boss_incoming, card_select_elapsed, chosen_index, storm_type, storm_phase, menu_cursor,
                 reset_armed)
    if state == GameState.MENU then
        UI.draw_menu(high_score, menu_cursor, reset_armed)
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
    local text_width = Screen.text_width(UI.main_font, score_text)
    local center_x = (Screen.WIDTH - text_width) / 2

    Screen.print(score_text, center_x, 20)

    if wave then
        local wave_text = "Wave: " .. wave
        local wave_width = Screen.text_width(UI.main_font, wave_text)
        love.graphics.setColor(0.7, 0.75, 1)
        Screen.print(wave_text, (Screen.WIDTH - wave_width) / 2, 50)
    end

    if boss_active then
        local boss_text = "BOSS"
        local boss_width = Screen.text_width(UI.main_font, boss_text)
        love.graphics.setColor(1, 0.2, 0.6)
        Screen.print(boss_text, (Screen.WIDTH - boss_width) / 2, 80)
    elseif boss_incoming then
        local warn_text = "BOSS INCOMING"
        local warn_width = Screen.text_width(UI.main_font, warn_text)
        -- pulses so it reads as a telegraph/warning, not a static label
        local pulse = 0.6 + 0.4 * math.abs(math.sin(love.timer.getTime() * 6))
        love.graphics.setColor(1, 0.3, 0.2, pulse)
        Screen.print(warn_text, (Screen.WIDTH - warn_width) / 2, 80)
        love.graphics.setColor(1, 1, 1, 1)
    elseif storm_phase and storm_type then
        -- one banner for both storm phases, named and colored by the storm
        -- type itself so which storm is coming reads at a glance. The active
        -- phase flickers noticeably faster than the telegraph -- it means
        -- "danger right now", not "danger soon"
        local is_active = storm_phase == "active"
        local storm_text = is_active and storm_type.name or (storm_type.name .. " INCOMING")
        local storm_width = Screen.text_width(UI.main_font, storm_text)
        local rate = is_active and 12 or 6
        local pulse = 0.5 + 0.5 * math.abs(math.sin(love.timer.getTime() * rate))
        local c = storm_type.color
        love.graphics.setColor(c[1], c[2], c[3], pulse)
        Screen.print(storm_text, (Screen.WIDTH - storm_width) / 2, 80)
        love.graphics.setColor(1, 1, 1, 1)
    end

    local orbs = collected_orb_amount or 0
    -- progress toward the next 5-orb milestone, not the lifetime total --
    -- shows 5/5 right at the trigger moment rather than looping back to 0/5
    local progress = orbs % 5
    if progress == 0 and orbs > 0 then progress = 5 end
    local orb_text = "Orbs: " .. progress .. "/5"
    local orb_width = Screen.text_width(UI.main_font, orb_text)

    love.graphics.setColor(1, 0.9, 0.2)
    Screen.print(orb_text, Screen.WIDTH - orb_width - 25, 20)

    if state == GameState.PAUSED then
        love.graphics.setColor(0, 0, 0, 0.55)
        love.graphics.rectangle("fill", 0, 0, Screen.WIDTH, Screen.HEIGHT)

        love.graphics.setFont(UI.title_font)
        love.graphics.setColor(0, 0.8, 1)

        local pause_text = "PAUSED"
        local p_width = Screen.text_width(UI.title_font, pause_text)
        Screen.print(pause_text, (Screen.WIDTH - p_width) / 2, Screen.HEIGHT / 2 - 120)

        UI.draw_simple_menu(UI.PAUSE_MENU_OPTIONS, menu_cursor, pause_menu_top_y())

        love.graphics.setFont(UI.main_font)
        love.graphics.setColor(0.7, 0.75, 0.8)
        local hint_text = "Shortcuts still work: P resume, R restart, M menu"
        local hint_width = Screen.text_width(UI.main_font, hint_text)
        Screen.print(hint_text, (Screen.WIDTH - hint_width) / 2, Screen.HEIGHT / 2 + 150)
        love.graphics.setColor(1, 1, 1, 1)
    end

    if state == GameState.GAME_OVER then
        love.graphics.setFont(UI.title_font)
        love.graphics.setColor(1, 0, 0)

        local game_over_text = "GAME OVER!"
        local go_width = Screen.text_width(UI.title_font, game_over_text)
        Screen.print(game_over_text, (Screen.WIDTH - go_width) / 2, Screen.HEIGHT / 2 - 40)

        love.graphics.setFont(UI.main_font)
        love.graphics.setColor(1, 1, 1)

        local restart_text = "Press 'R' to restart.."
        local r_width = Screen.text_width(UI.main_font, restart_text)
        Screen.print(restart_text, (Screen.WIDTH - r_width) / 2, Screen.HEIGHT / 2 + 20)

        if high_score then
            local is_new_record = score >= high_score and score > 0
            local hs_text = is_new_record and ("New High Score: " .. high_score .. "!") or ("High Score: " .. high_score)

            love.graphics.setColor(1, 0.9, 0.2)
            local hs_width = Screen.text_width(UI.main_font, hs_text)
            Screen.print(hs_text, (Screen.WIDTH - hs_width) / 2, Screen.HEIGHT / 2 + 55)
        end
    end
end

return UI
