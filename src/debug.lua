local Cards = require("src/cards")
local Difficulty = require("src/difficulty")
local GameState = require("src/game_state")
local Screen = require("src/screen")

local Debug = {}

function Debug.load()
    Debug.enabled = false
    Debug.god_mode = false
    Debug.refresh_font()
    -- which boss F3 will spawn next; also where the 1-9 hotkeys leave off, so
    -- the two ways of picking a boss stay in step. Deliberately not reset on
    -- restart -- it's testing state, not run state.
    Debug.next_boss_index = 1
end

-- same scale-aware font handling as UI's (see Screen.new_font): built at the
-- pixel size it will actually occupy, rebuilt from love.resize when that
-- changes, skipped when the scale hasn't moved
local FONT_SIZE = 14

function Debug.refresh_font()
    if Debug.font_scale == Screen.scale then return end

    Debug.font_scale = Screen.scale
    Debug.font = Screen.new_font(FONT_SIZE)
end

-- F3: spawn the next boss in the cycle and advance
function Debug.cycle_boss(sequence)
    local id = sequence[Debug.next_boss_index]
    Debug.next_boss_index = Debug.next_boss_index % #sequence + 1
    return id
end

-- 1-9: spawn one specific boss, leaving F3 to continue from just after it.
-- Returns nil for any key that isn't a valid index, so the caller can fall
-- through to whatever else that key might do.
function Debug.select_boss(index, sequence)
    if not index or not sequence[index] then return nil end
    Debug.next_boss_index = index % #sequence + 1
    return sequence[index]
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
    -- pairs() order is unspecified in Lua -- sort keys so this debug line
    -- doesn't reorder itself between runs/frames
    local keys = {}
    for key in pairs(t) do table.insert(keys, key) end
    table.sort(keys)

    local line = prefix
    if #keys == 0 then
        line = line .. "(none)"
    else
        for _, key in ipairs(keys) do
            line = line .. formatter(key, t[key]) .. "  "
        end
    end
    return line
end

function Debug.draw(player, boss, unlock_stage, max_unlock_stage, storm_type, storm_phase)
    if not Debug.enabled then return end

    local storm_summary = storm_type and (storm_type.id .. ":" .. (storm_phase or "-")) or "(none)"

    -- the whole boss roster with its hotkey number, marking which one F3 is
    -- pointing at -- otherwise "press F3 and see what turns up" is the only
    -- way to find a specific type
    local roster = {}
    for i, id in ipairs(boss.SEQUENCE) do
        local marker = (i == Debug.next_boss_index) and ">" or " "
        table.insert(roster, string.format("%s%d %s", marker, i, id))
    end

    local lines = {
        "DEBUG MODE -- F1 toggle | F2 card select | F3 next boss | F4 skip wave | F5 god mode: " ..
        (Debug.god_mode and "ON" or "OFF"),
        "Spawn boss:" .. table.concat(roster, " "),
        string.format("State: %s | Wave: %d | Boss: %s | Unlock stage: %d/%d | Storm: %s", GameState.current,
            Difficulty.wave(), boss.debug_summary(), unlock_stage or 0, max_unlock_stage or 0, storm_summary),
        string.format("Player HP: %d/%d | Shield: %s", player.lives, player.max_lives, tostring(player.has_shield)),
        join_table_summary(Cards.modifiers, "Modifiers: ", function(k, v) return k .. "=" .. tostring(v) end),
        join_table_summary(Cards.owned, "Owned cards: ", function(id, stacks) return id .. "x" .. stacks end),
    }

    love.graphics.setFont(Debug.font)

    local line_height = 18
    local total_height = line_height * #lines + 10
    love.graphics.setColor(0, 0, 0, 0.65)
    love.graphics.rectangle("fill", 0, Screen.HEIGHT - total_height, Screen.WIDTH,
        total_height)

    love.graphics.setColor(0.4, 1, 0.4)
    for i, line in ipairs(lines) do
        Screen.print(line, 10, Screen.HEIGHT - total_height + 5 + (i - 1) * line_height)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return Debug
