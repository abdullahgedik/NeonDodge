local GameState = {}

GameState.MENU        = "menu"
GameState.PLAYING     = "playing"
GameState.PAUSED      = "paused"
GameState.GAME_OVER   = "game_over"
GameState.CARD_SELECT = "card_select"

function GameState.load()
    GameState.current = GameState.MENU
end

function GameState.set(new_state)
    GameState.current = new_state
end

function GameState.is(state)
    return GameState.current == state
end

return GameState
