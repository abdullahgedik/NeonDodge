-- main.lua
local Player                = require("src/player")
local Enemy                 = require("src/enemy")
local ZigzagEnemy           = require("src/zigzag_enemy")
local Orb                   = require("src/orb")
local VoidOrb               = require("src/void_orb")
local UI                    = require("src/ui")
local FXManager             = require("src/fx_manager")
local Background            = require("src/background")
local GameState             = require("src/game_state")
local Difficulty            = require("src/difficulty")
local Bloom                 = require("src/bloom")
local Boss                  = require("src/boss")
local Projectile            = require("src/projectile")
local HitEffect             = require("src/hit_effect")
local HighScore             = require("src/high_score")
local Cards                 = require("src/cards")
local Debug                 = require("src/debug")

local score                 = 0
local collected_orb_amount  = 0

local shake_duration        = 0
local shake_magnitude       = 0

local hitstop_timer         = 0

local BOSS_WAVE_INTERVAL    = 3
local BOSS_SEQUENCE         = { "sentinel", "homing", "laser", "splitter", "turret" }
local last_boss_wave        = 0
local last_wave_seen        = 1
local boss_encounter_index  = 0
local debug_boss_test_index = 0
local current_card_choices  = nil
local card_cursor           = 1

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
    Boss.load()
    Projectile.load()
    HitEffect.load()
    HighScore.load()
    Cards.load()
    Debug.load()
end

function love.update(dt)
    if GameState.is(GameState.MENU) then
        Background.update(dt)
        return
    end

    if GameState.is(GameState.PAUSED) then return end

    if GameState.is(GameState.CARD_SELECT) then return end

    if hitstop_timer > 0 then
        hitstop_timer = hitstop_timer - dt
        return
    end

    if shake_duration > 0 then
        shake_duration = shake_duration - dt
    else
        shake_magnitude = 0
    end

    HitEffect.update(dt, Player.lives == 1 and not Player.is_dead)

    local is_game_over = GameState.is(GameState.GAME_OVER)

    Cards.update(dt, is_game_over, Player)

    Difficulty.update(dt, is_game_over)

    if not is_game_over then
        local wave = Difficulty.wave()
        if wave > last_wave_seen then
            last_wave_seen = wave
            love.increase_score(Cards.get("wave_bonus_score", 0))
        end
    end

    if not is_game_over and not Boss.active then
        local wave = Difficulty.wave()
        if wave > last_boss_wave and wave % BOSS_WAVE_INTERVAL == 0 then
            last_boss_wave = wave
            local boss_type = BOSS_SEQUENCE[(boss_encounter_index % #BOSS_SEQUENCE) + 1]
            boss_encounter_index = boss_encounter_index + 1
            Boss.spawn(boss_type)
        end
    end

    Player.update(dt, is_game_over)

    local suppress_spawns = Boss.active

    Enemy.update(dt, is_game_over, Player,
        function(index) love.on_enemy_player_collision(index) end,
        suppress_spawns and math.huge or Difficulty.spawn_rate("enemy")
    )

    ZigzagEnemy.update(dt, is_game_over, Player,
        function(index) love.on_zigzag_enemy_player_collision(index) end,
        suppress_spawns and math.huge or Difficulty.spawn_rate("zigzag")
    )

    Orb.update(dt, is_game_over, Player,
        function(index) love.on_orb_player_collision(index) end,
        suppress_spawns and math.huge or Difficulty.spawn_rate("orb")
    )

    VoidOrb.update(dt, is_game_over, Player,
        function(index) love.on_void_orb_player_collision(index) end,
        function(index) love.on_void_orb_miss(index) end,
        suppress_spawns and math.huge or Difficulty.spawn_rate("void_orb")
    )

    Boss.update(dt, is_game_over, Player,
        function() love.on_boss_player_collision() end,
        function(x, y, dir_x, dir_y, homing) Projectile.spawn(x, y, dir_x, dir_y, homing) end,
        function() love.on_boss_encounter_end() end,
        function(type_id)
            if type_id == "homing" then
                Projectile.clear_homing()
            end
        end
    )

    Projectile.update(dt, is_game_over, Player,
        function(index) love.on_projectile_player_collision(index) end
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
        Boss.draw()
        Projectile.draw()
    end

    love.graphics.pop()

    Bloom.finish_scene()
    HitEffect.draw(Bloom.final_canvas)

    UI.draw(GameState.current, score, Player.lives, collected_orb_amount, Difficulty.wave(), Boss.active,
        HighScore.value, current_card_choices, card_cursor)

    Debug.draw(Player, Boss)
end

local function apply_player_hit(hit_shake_duration, hit_shake_magnitude)
    local p_cx = Player.x + Player.size / 2
    local p_cy = Player.y + Player.size / 2

    local result = Player.take_damage(1, function()
        GameState.set(GameState.GAME_OVER)
        HighScore.try_save(score)

        FXManager.spawn("player_death", p_cx, p_cy, 60)

        love.hitstop(0.12)
        love.shake(0.4, 12)
    end)

    if result == "dodged" then
        FXManager.spawn_ring(p_cx, p_cy, 1, 1, 1, 15, 55, 200)
        love.hitstop(0.03)
        love.shake(0.05, 2)
        return
    end

    if result == "shielded" then
        FXManager.spawn_ring(p_cx, p_cy, 0.25, 0.6, 1, 20, 70, 260)
        love.hitstop(0.05)
        love.shake(0.1, 4)
        return
    end

    if result == "revived" then
        FXManager.spawn_ring(p_cx, p_cy, 1, 0.85, 0.2, 25, 90, 280)
        FXManager.spawn("player_damage", p_cx, p_cy, 30)
        Player.flicker_timer = 0.6
        love.hitstop(0.15)
        love.shake(0.35, 14)
        return
    end

    HitEffect.trigger()

    if result == "dead" then
        return
    end

    Player.flicker_timer = 0.25

    FXManager.spawn("player_damage", p_cx, p_cy, 15)

    love.hitstop(0.06)
    love.shake(hit_shake_duration, hit_shake_magnitude)
end

function love.on_enemy_player_collision(index)
    Enemy.remove(index)

    if Player.is_dead or GameState.is(GameState.GAME_OVER) then return end

    apply_player_hit(0.15, 6)
end

function love.on_zigzag_enemy_player_collision(index)
    ZigzagEnemy.remove(index)

    if Player.is_dead or GameState.is(GameState.GAME_OVER) then return end

    apply_player_hit(0.15, 6)
end

function love.on_boss_player_collision()
    if Player.is_dead or GameState.is(GameState.GAME_OVER) then return end

    apply_player_hit(0.2, 8)
end

function love.on_projectile_player_collision(index)
    Projectile.remove(index)

    if Player.is_dead or GameState.is(GameState.GAME_OVER) then return end

    apply_player_hit(0.15, 6)
end

local function trigger_card_select()
    current_card_choices = Cards.roll_choices(3)
    card_cursor = 1
    love.pause()
    GameState.set(GameState.CARD_SELECT)
end

function love.on_boss_encounter_end()
    love.increase_score(50 + Cards.get("boss_bonus_score_add", 0))
    trigger_card_select()
end

function love.on_orb_player_collision(index)
    Orb.remove(index)

    love.increase_score(5 + Cards.get("orb_score_bonus", 0))
    love.increase_orb_count(1)
end

function love.on_void_orb_player_collision(index)
    VoidOrb.remove(index)
    love.increase_score(10 + Cards.get("void_orb_score_bonus", 0))
    love.shake(0.15, 4)
end

function love.on_void_orb_miss(index)
    VoidOrb.remove(index)

    if Cards.get("void_orb_miss_safe", false) then
        return
    end

    local p_cx = Player.x + Player.size / 2
    local p_cy = Player.y + Player.size / 2

    local result = Player.take_damage(1, function()
        GameState.set(GameState.GAME_OVER)
        HighScore.try_save(score)
        FXManager.spawn("player_death", p_cx, p_cy, 60)
        love.hitstop(0.12)
        love.shake(0.6, 20)
    end)

    if result == "dodged" then
        FXManager.spawn_ring(p_cx, p_cy, 1, 1, 1, 15, 55, 200)
        love.hitstop(0.03)
        love.shake(0.05, 2)
        return
    end

    if result == "shielded" then
        FXManager.spawn_ring(p_cx, p_cy, 0.25, 0.6, 1, 20, 70, 260)
        love.hitstop(0.05)
        love.shake(0.1, 4)
        return
    end

    if result == "revived" then
        FXManager.spawn_ring(p_cx, p_cy, 1, 0.85, 0.2, 25, 90, 280)
        FXManager.spawn("player_damage", p_cx, p_cy, 30)
        Player.flicker_timer = 0.6
        love.hitstop(0.15)
        love.shake(0.35, 14)
        return
    end

    HitEffect.trigger()

    love.hitstop(0.06)
    love.shake(0.5, 15)
end

function love.increase_score(amount)
    local mult = Cards.get("score_mult", 1)
    if Player.lives == 1 then
        mult = mult * Cards.get("low_hp_score_mult", 1)
    end
    score = score + math.floor(amount * mult + 0.5)
end

function love.increase_orb_count(amount)
    collected_orb_amount = collected_orb_amount + amount

    if (collected_orb_amount % 5 == 0) then
        love.increase_score(Cards.get("orb_milestone_bonus", 0))

        if Player.lives >= Player.max_lives then
            local is_shielded = Player.give_shield()
            if is_shielded then
                FXManager.spawn_ring(Player.x + Player.size / 2, Player.y + Player.size / 2, 0.25, 0.6, 1, 12, 65, 180)
                love.shake(0.1, 2)
            end
        else
            local is_healed = Player.heal(1)
            if is_healed then
                FXManager.spawn_ring(Player.x + Player.size / 2, Player.y + Player.size / 2, 0, 1, 0.85, 12, 65, 180)
                love.shake(0.1, 2)
            end
        end
    end
end

function love.shake(duration, magnitude)
    shake_duration = duration
    shake_magnitude = magnitude * Cards.get("shake_mult", 1)
end

function love.hitstop(duration)
    hitstop_timer = duration * Cards.get("hitstop_mult", 1)
end

function love.pause()
    Player.pause()
    Enemy.pause()
    ZigzagEnemy.pause()
    Orb.pause()
    VoidOrb.pause()
    Difficulty.pause()
    Boss.pause()
    Projectile.pause()
    Cards.pause()
end

function love.resume()
    Player.resume()
    Enemy.resume()
    ZigzagEnemy.resume()
    Orb.resume()
    VoidOrb.resume()
    Difficulty.resume()
    Boss.resume()
    Projectile.resume()
    Cards.resume()
end

local function restart_game()
    score = 0
    collected_orb_amount = 0
    last_boss_wave = 0
    last_wave_seen = 1
    boss_encounter_index = 0
    current_card_choices = nil
    card_cursor = 1
    Player.reset()
    Enemy.reset()
    ZigzagEnemy.reset()
    Orb.reset()
    VoidOrb.reset()
    FXManager.reset()
    Background.reset()
    Difficulty.reset()
    Boss.reset()
    Projectile.reset()
    HitEffect.reset()
    Cards.reset()
    GameState.set(GameState.PLAYING)
end

local function choose_card(index)
    if not current_card_choices then return end
    local card = current_card_choices[index]
    if not card then return end

    Cards.choose(card.id, Player)
    current_card_choices = nil
    love.resume()
    GameState.set(GameState.PLAYING)
end

local function toggle_pause()
    if GameState.is(GameState.PLAYING) then
        love.pause()
        GameState.set(GameState.PAUSED)
    elseif GameState.is(GameState.PAUSED) then
        love.resume()
        GameState.set(GameState.PLAYING)
    end
end

function love.keypressed(key)
    if key == "escape" then love.event.quit() end

    if key == "f1" then
        Debug.toggle()
        return
    end

    if Debug.enabled and GameState.is(GameState.PLAYING) then
        if key == "f2" then
            trigger_card_select()
            return
        elseif key == "f3" then
            local boss_type = BOSS_SEQUENCE[(debug_boss_test_index % #BOSS_SEQUENCE) + 1]
            debug_boss_test_index = debug_boss_test_index + 1
            Boss.spawn(boss_type)
            return
        elseif key == "f4" then
            Difficulty.skip_wave()
            return
        elseif key == "f5" then
            Debug.toggle_god_mode()
            return
        end
    end

    if GameState.is(GameState.MENU) then
        if key == "space" or key == "return" then
            GameState.set(GameState.PLAYING)
        end
        return
    end

    if GameState.is(GameState.CARD_SELECT) then
        if key == "1" then
            choose_card(1)
        elseif key == "2" then
            choose_card(2)
        elseif key == "3" then
            choose_card(3)
        elseif key == "a" or key == "left" then
            card_cursor = card_cursor - 1
            if card_cursor < 1 then card_cursor = 3 end
        elseif key == "d" or key == "right" then
            card_cursor = card_cursor + 1
            if card_cursor > 3 then card_cursor = 1 end
        elseif key == "return" or key == "space" then
            choose_card(card_cursor)
        end
        return
    end

    if key == "r" and GameState.is(GameState.GAME_OVER) then
        restart_game()
    end

    if key == "p" then
        toggle_pause()
    end

    Player.keypressed(key)
end

function love.gamepadpressed(joystick, button)
    if GameState.is(GameState.MENU) then
        if button == "a" or button == "start" then
            GameState.set(GameState.PLAYING)
        end
        return
    end

    if GameState.is(GameState.CARD_SELECT) then
        if button == "dpleft" then
            card_cursor = card_cursor - 1
            if card_cursor < 1 then card_cursor = 3 end
        elseif button == "dpright" then
            card_cursor = card_cursor + 1
            if card_cursor > 3 then card_cursor = 1 end
        elseif button == "a" then
            choose_card(card_cursor)
        end
        return
    end

    if button == "a" and GameState.is(GameState.GAME_OVER) then
        restart_game()
    end

    if button == "start" then
        toggle_pause()
    end

    Player.gamepadpressed(button)
end

function love.mousepressed(x, y, button)
    if button ~= 1 then return end
    if not GameState.is(GameState.CARD_SELECT) then return end

    local rects = UI.card_layout()
    for i, rect in ipairs(rects) do
        if x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h then
            choose_card(i)
            return
        end
    end
end
