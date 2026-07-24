local Cards = require("src/cards")
local Difficulty = require("src/difficulty")
local GameState = require("src/game_state")

local Debug = {}

function Debug.load()
    Debug.enabled = false
    Debug.god_mode = false
    Debug.font = love.graphics.newFont(14)
end

function Debug.toggle()
    Debug.enabled = not Debug.enabled
    if not Debug.enabled then
        Debug.god_mode = false
    end
end

function Debug.toggle_god_mode()
    Debug.god_mode = not Debug.god_mode
end

local function join_table_summary(t, prefix, formatter)
    local line = prefix
    local any = false
    for key, value in pairs(t) do
        line = line .. formatter(key, value) .. "  "
        any = true
    end
    if not any then
        line = line .. "(none)"
    end
    return line
end

function Debug.draw(player, boss)
    if not Debug.enabled then return end

    local lines = {
        "DEBUG MODE -- F1 toggle | F2 force card select | F3 spawn boss | F4 skip wave | F5 god mode: " ..
        (Debug.god_mode and "ON" or "OFF"),
        string.format("State: %s | Wave: %d | Boss: %s", GameState.current, Difficulty.wave(),
            boss.debug_summary()),
        string.format("Player HP: %d/%d | Shield: %s", player.lives, player.max_lives, tostring(player.has_shield)),
        join_table_summary(Cards.modifiers, "Modifiers: ", function(k, v) return k .. "=" .. tostring(v) end),
        join_table_summary(Cards.owned, "Owned cards: ", function(id, stacks) return id .. "x" .. stacks end),
    }

    love.graphics.setFont(Debug.font)

    local line_height = 18
    local total_height = line_height * #lines + 10
    love.graphics.setColor(0, 0, 0, 0.65)
    love.graphics.rectangle("fill", 0, love.graphics.getHeight() - total_height, love.graphics.getWidth(),
        total_height)

    love.graphics.setColor(0.4, 1, 0.4)
    for i, line in ipairs(lines) do
        love.graphics.print(line, 10, love.graphics.getHeight() - total_height + 5 + (i - 1) * line_height)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return Debug
