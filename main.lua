-- main.lua
local Player               = require("src/player")
local Enemy                = require("src/enemy")
local ZigzagEnemy          = require("src/zigzag_enemy")
local Orb                  = require("src/orb")
local VoidOrb              = require("src/void_orb")
local UI                   = require("src/ui")
local FXManager            = require("src/fx_manager")
local Background           = require("src/background")
local GameState            = require("src/game_state")
local Difficulty           = require("src/difficulty")
local Bloom                = require("src/bloom")

local score                = 0
local collected_orb_amount = 0

local shake_duration       = 0
local shake_magnitude      = 0

local hitstop_timer        = 0

function love.load()
    Player.load()
    Enemy.load()
    ZigzagEnemy.load()
    Orb.load()
    VoidOrb.load()
    UI.load()
    FXManager.load()
    Background.load()
    GameState.load()
    Difficulty.load()
    Bloom.load()
end

function love.update(dt)
    if GameState.is(GameState.MENU) then
        Background.update(dt)
        return
    end

    if GameState.is(GameState.PAUSED) then return end

    if hitstop_timer > 0 then
        hitstop_timer = hitstop_timer - dt
        return
    end

    if shake_duration > 0 then
        shake_duration = shake_duration - dt
    else
        shake_magnitude = 0
    end

    local is_game_over = GameState.is(GameState.GAME_OVER)

    Difficulty.update(dt, is_game_over)

    Player.update(dt, is_game_over)

    Enemy.update(dt, is_game_over, Player,
        function(index) love.on_enemy_player_collision(index) end,
        Difficulty.spawn_rate("enemy")
    )

    ZigzagEnemy.update(dt, is_game_over, Player,
        function(index) love.on_zigzag_enemy_player_collision(index) end,
        Difficulty.spawn_rate("zigzag")
    )

    Orb.update(dt, is_game_over, Player,
        function(index) love.on_orb_player_collision(index) end,
        Difficulty.spawn_rate("orb")
    )

    VoidOrb.update(dt, is_game_over, Player,
        function(index) love.on_void_orb_player_collision(index) end,
        function(index) love.on_void_orb_miss(index) end,
        Difficulty.spawn_rate("void_orb")
    )

    FXManager.update(dt)
    Background.update(dt)
end

function love.draw()
    Bloom.begin_scene()

    Background.draw()

    love.graphics.push()
    if shake_duration > 0 then
        local dx = love.math.random(-shake_magnitude, shake_magnitude)
        local dy = love.math.random(-shake_magnitude, shake_magnitude)
        love.graphics.translate(dx, dy)
    end

    FXManager.draw()

    if not GameState.is(GameState.MENU) then
        Player.draw()
        Enemy.draw()
        ZigzagEnemy.draw()
        Orb.draw()
        VoidOrb.draw()
    end

    love.graphics.pop()

    Bloom.finish_scene()

    UI.draw(GameState.current, score, Player.lives, collected_orb_amount, Difficulty.wave())
end

function love.on_enemy_player_collision(index)
    Enemy.remove(index)

    if Player.is_dead or GameState.is(GameState.GAME_OVER) then return end

    local p_cx = Player.x + Player.size / 2
    local p_cy = Player.y + Player.size / 2

    Player.take_damage(1, function()
        GameState.set(GameState.GAME_OVER)

        FXManager.spawn("player_death", p_cx, p_cy, 60)

        love.hitstop(0.12)
        love.shake(0.4, 12)
    end)

    if Player.is_dead then
        return
    end

    Player.flicker_timer = 0.25

    FXManager.spawn("player_damage", p_cx, p_cy, 15)

    love.hitstop(0.06)
    love.shake(0.15, 6)
end

function love.on_zigzag_enemy_player_collision(index)
    ZigzagEnemy.remove(index)

    if Player.is_dead or GameState.is(GameState.GAME_OVER) then return end

    local p_cx = Player.x + Player.size / 2
    local p_cy = Player.y + Player.size / 2

    Player.take_damage(1, function()
        GameState.set(GameState.GAME_OVER)

        FXManager.spawn("player_death", p_cx, p_cy, 60)

        love.hitstop(0.12)
        love.shake(0.4, 12)
    end)

    if Player.is_dead then
        return
    end

    Player.flicker_timer = 0.25

    FXManager.spawn("player_damage", p_cx, p_cy, 15)

    love.hitstop(0.06)
    love.shake(0.15, 6)
end

function love.on_orb_player_collision(index)
    Orb.remove(index)

    love.increase_score(5)
    love.increase_orb_count(1)
end

function love.on_void_orb_player_collision(index)
    VoidOrb.remove(index)
    love.increase_score(10)
    love.shake(0.15, 4)
end

function love.on_void_orb_miss(index)
    VoidOrb.remove(index)
    love.hitstop(0.06)
    love.shake(0.5, 15)

    local p_cx = Player.x + Player.size / 2
    local p_cy = Player.y + Player.size / 2

    Player.take_damage(1, function()
        GameState.set(GameState.GAME_OVER)
        FXManager.spawn("player_death", p_cx, p_cy, 60)
        love.hitstop(0.12)
        love.shake(0.6, 20)
    end)
end

function love.increase_score(amount)
    score = score + amount
end

function love.increase_orb_count(amount)
    collected_orb_amount = collected_orb_amount + amount

    if (collected_orb_amount % 5 == 0) then
        local is_healed = Player.heal(1)
        if is_healed then
            FXManager.spawn_ring(Player.x + Player.size / 2, Player.y + Player.size / 2, 0, 1, 0.85, 12, 65, 180)
            love.shake(0.1, 2)
        end
    end
end

function love.shake(duration, magnitude)
    shake_duration = duration
    shake_magnitude = magnitude
end

function love.hitstop(duration)
    hitstop_timer = duration
end

function love.pause()
    Player.pause()
    Enemy.pause()
    ZigzagEnemy.pause()
    Orb.pause()
    VoidOrb.pause()
    Difficulty.pause()
end

function love.resume()
    Player.resume()
    Enemy.resume()
    ZigzagEnemy.resume()
    Orb.resume()
    VoidOrb.resume()
    Difficulty.resume()
end

function love.keypressed(key)
    if key == "escape" then love.event.quit() end

    if GameState.is(GameState.MENU) then
        if key == "space" or key == "return" then
            GameState.set(GameState.PLAYING)
        end
        return
    end

    if key == "r" and GameState.is(GameState.GAME_OVER) then
        score = 0
        collected_orb_amount = 0
        Player.reset()
        Enemy.reset()
        ZigzagEnemy.reset()
        Orb.reset()
        VoidOrb.reset()
        FXManager.reset()
        Background.reset()
        Difficulty.reset()
        GameState.set(GameState.PLAYING)
    end

    if key == "p" then
        if GameState.is(GameState.PLAYING) then
            love.pause()
            GameState.set(GameState.PAUSED)
        elseif GameState.is(GameState.PAUSED) then
            love.resume()
            GameState.set(GameState.PLAYING)
        end
    end

    Player.keypressed(key)
end
