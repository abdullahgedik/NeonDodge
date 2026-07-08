-- main.lua
local Player               = require("src/player")
local Enemy                = require("src/enemy")
local Orb                  = require("src/orb")
local VoidOrb              = require("src/void_orb")
local UI                   = require("src/ui")
local FXManager            = require("src/fx_manager")
local Background           = require("src/background")

local score                = 0
local collected_orb_amount = 0

local shake_duration       = 0
local shake_magnitude      = 0

local enemy_spawn_rate     = 0.6
local orb_spawn_rate       = 2
local void_orb_spawn_rate  = 5

local game_over            = false
local is_paused            = false

function love.load()
    Player.load()
    Enemy.load()
    Orb.load()
    VoidOrb.load()
    UI.load()
    FXManager.load()
    Background.load()
end

function love.update(dt)
    if is_paused then return end

    if shake_duration > 0 then
        shake_duration = shake_duration - dt
    else
        shake_magnitude = 0
    end

    Player.update(dt, game_over)

    Enemy.update(dt, game_over, Player,
        function(index) love.on_enemy_player_collision(index) end,
        enemy_spawn_rate
    )

    Orb.update(dt, game_over, Player,
        function(index) love.on_orb_player_collision(index) end,
        orb_spawn_rate
    )

    VoidOrb.update(dt, game_over, Player,
        function(index) love.on_void_orb_player_collision(index) end,
        function(index) love.on_void_orb_miss(index) end,
        void_orb_spawn_rate
    )

    FXManager.update(dt)
    Background.update(dt)
end

function love.draw()
    Background.draw()

    love.graphics.push()
    if shake_duration > 0 then
        local dx = love.math.random(-shake_magnitude, shake_magnitude)
        local dy = love.math.random(-shake_magnitude, shake_magnitude)
        love.graphics.translate(dx, dy)
    end

    FXManager.draw()
    Player.draw()
    Enemy.draw()
    Orb.draw()
    VoidOrb.draw()

    love.graphics.pop()

    UI.draw(score, game_over, Player.lives, collected_orb_amount)
end

function love.on_enemy_player_collision(index)
    Enemy.remove(index)

    if Player.is_dead or game_over then return end

    local p_cx = Player.x + Player.size / 2
    local p_cy = Player.y + Player.size / 2

    Player.take_damage(1, function()
        game_over = true

        FXManager.spawn("player_death", p_cx, p_cy, 60)

        love.shake(0.4, 12)
    end)

    if Player.is_dead then
        return
    end

    Player.flicker_timer = 0.25

    FXManager.spawn("player_damage", p_cx, p_cy, 15)

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
    love.shake(0.5, 15)

    local p_cx = Player.x + Player.size / 2
    local p_cy = Player.y + Player.size / 2

    Player.take_damage(1, function()
        game_over = true
        FXManager.spawn("player_death", p_cx, p_cy, 60)
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
            FXManager.spawn("player_heal", Player.x + Player.size / 2, Player.y + Player.size / 2, 20)
            FXManager.spawn_ring(Player.x + Player.size / 2, Player.y + Player.size / 2, 0, 1, 0.85, 12, 65, 180)
            love.shake(0.1, 2)
        end
    end
end

function love.shake(duration, magnitude)
    shake_duration = duration
    shake_magnitude = magnitude
end

function love.pause()
    Player.pause()
    Enemy.pause()
    Orb.pause()
    VoidOrb.pause()
    UI.pause()
end

function love.resume()
    Player.resume()
    Enemy.resume()
    Orb.resume()
    VoidOrb.resume()
    UI.resume()
end

function love.keypressed(key)
    if key == "r" and game_over then
        score = 0
        collected_orb_amount = 0
        game_over = false
        is_paused = false
        Player.reset()
        Enemy.reset()
        Orb.reset()
        VoidOrb.reset()
        UI.resume()
        FXManager.reset()
        Background.reset()
    end

    if key == "escape" then love.event.quit() end

    if key == "p" and not game_over then
        if is_paused then
            love.resume()
            is_paused = false
        else
            love.pause()
            is_paused = true
        end
    end

    Player.keypressed(key)
end
