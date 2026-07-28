local Cards = require("src/cards")
local Debug = require("src/debug")
local Screen = require("src/screen")
local Mathx = require("src/mathx")

local Player = {}

local SHIELD_ANIM_DURATION = 0.35
local STICK_DEADZONE = 0.25
local BASE_MAX_LIVES = 3
local SIZE = 35
-- how far above the bottom edge a run starts
local START_HEIGHT = 100

-- Everything a fresh run resets, shared by load() and reset(). These were two
-- separate hand-written lists that had already drifted apart once: reset() was
-- missing max_lives, so a Vitality or Glass Cannon pick leaked into the next
-- run. One function means they cannot disagree again.
local function reset_run_state()
    -- centered: SIZE/2, not a hardcoded 15 (which left the player 2.5px off)
    Player.x = Screen.WIDTH / 2 - SIZE / 2
    Player.y = Screen.HEIGHT - START_HEIGHT

    Player.max_lives = BASE_MAX_LIVES
    Player.lives = BASE_MAX_LIVES
    Player.is_dead = false

    Player.dash_timer = 0
    Player.dash_time_left = 0
    Player.is_dashing = false

    Player.flicker_timer = 0
    Player.has_shield = false
    Player.shield_anim_timer = SHIELD_ANIM_DURATION

    Player.reset_bounds()
end

local function first_gamepad()
    for _, joystick in ipairs(love.joystick.getJoysticks()) do
        if joystick:isGamepad() then
            return joystick
        end
    end
    return nil
end

local function get_move_vector()
    local moveInput = { x = 0, y = 0 }
    Player.input(moveInput)

    local moveVector = { x = 0, y = 0 }
    local len = math.sqrt(moveInput.x * moveInput.x + moveInput.y * moveInput.y)
    if len > 0 then
        moveVector.x = moveInput.x / len
        moveVector.y = moveInput.y / len
    end

    return moveVector
end

-- The tunables that never change during a run live here; everything that
-- resets per-run is in reset_run_state above.
function Player.load()
    Player.size = SIZE
    Player.speed = 325
    Player.is_paused = false

    Player.dash_speed = 900
    Player.dash_duration = 0.10
    Player.dash_cooldown = 0.75
    -- overwritten on every dash; only needs to exist before the first one
    Player.dash_dir = { x = 0, y = 0 }

    reset_run_state()
    Player.load_particles()
end

-- the rect Player.bounds() clamps into. Defaults to the whole screen; some
-- boss encounters narrow it (a top-of-screen wall so they can't be camped
-- above, or the warden's closing arena) by writing these every frame from
-- Boss.get_player_bounds. Player itself doesn't know or care why.
function Player.reset_bounds()
    Player.min_x = 0
    Player.min_y = 0
    Player.max_x = Screen.WIDTH
    Player.max_y = Screen.HEIGHT
end

-- the player's center point. Nearly every collision test and FX spawn wants
-- this rather than the top-left corner, so it lived hand-written at a dozen
-- call sites; src/collision.lua and every `player`-shaped call site now go
-- through here instead.
function Player.center()
    return Player.x + Player.size / 2, Player.y + Player.size / 2
end

function Player.update(dt, game_over)
    if Player.is_dead or game_over then
        Player.trail:stop()
        return
    end

    if Player.is_paused then return end

    if Player.flicker_timer > 0 then
        Player.flicker_timer = Player.flicker_timer - dt
    end

    if Player.has_shield and Player.shield_anim_timer < SHIELD_ANIM_DURATION then
        Player.shield_anim_timer = Player.shield_anim_timer + dt
    end

    if Player.dash_timer > 0 then
        Player.dash_timer = Player.dash_timer - dt
    end

    Player.move(dt)

    if Player.dash_timer <= 0 then
        Player.trail:setColors(0, 1, 0.85, 0.5, 0, 1, 0.85, 0)
    else
        Player.trail:setColors(0, 0.6, 0.3, 0.5, 0, 0.6, 0.3, 0)
    end

    Player.trail:setPosition(Player.center())
    Player.trail:update(dt)
end

local function dashed_line(x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    local length = math.sqrt(dx * dx + dy * dy)
    if length == 0 then return end

    local step_x, step_y = dx / length, dy / length
    local dash, gap, travelled = 14, 8, 0

    while travelled < length do
        local segment = math.min(dash, length - travelled)
        love.graphics.line(
            x1 + step_x * travelled, y1 + step_y * travelled,
            x1 + step_x * (travelled + segment), y1 + step_y * (travelled + segment)
        )
        travelled = travelled + dash + gap
    end
end

-- draws a dashed line along each edge of the bounds rect that's actually
-- been pushed in from the screen edge, so a restriction is always visible
-- rather than an invisible wall the player discovers by bumping into it
function Player.draw_walls()
    local width = Screen.WIDTH
    local height = Screen.HEIGHT

    love.graphics.setColor(1, 0.2, 0.6, 0.35)
    love.graphics.setLineWidth(2)

    if Player.min_y > 0 then dashed_line(Player.min_x, Player.min_y, Player.max_x, Player.min_y) end
    if Player.max_y < height then dashed_line(Player.min_x, Player.max_y, Player.max_x, Player.max_y) end
    if Player.min_x > 0 then dashed_line(Player.min_x, Player.min_y, Player.min_x, Player.max_y) end
    if Player.max_x < width then dashed_line(Player.max_x, Player.min_y, Player.max_x, Player.max_y) end

    love.graphics.setLineWidth(1)
end

function Player.draw()
    if Player.is_dead then return end

    Player.draw_walls()

    love.graphics.setColor(1, 1, 1, 1)

    love.graphics.setBlendMode("add")
    love.graphics.draw(Player.trail, 0, 0)
    love.graphics.setBlendMode("alpha")

    if Player.flicker_timer > 0 and math.floor(Player.flicker_timer * 20) % 2 == 0 then
        love.graphics.setColor(1, 0, 0.2)
    else
        if Player.dash_timer <= 0 then
            love.graphics.setColor(0, 1, 0.85)
        else
            love.graphics.setColor(0, 0.6, 0.3)
        end
    end

    love.graphics.rectangle("fill", Player.x, Player.y, Player.size, Player.size)

    if Player.has_shield then
        local player_cx, player_cy = Player.center()

        local t = math.min(Player.shield_anim_timer / SHIELD_ANIM_DURATION, 1)
        local eased = Mathx.ease_out(t)

        love.graphics.setLineWidth(4)
        love.graphics.setColor(0.3, 0.65, 1, 0.9 * eased)
        love.graphics.circle("line", player_cx, player_cy, Player.size * 0.85 * eased)
        love.graphics.setLineWidth(1)
    end

    if Player.dash_timer > 0 then
        local ratio = Player.dash_timer / Player.dash_cooldown
        local max_size = Player.size * 2.0
        local current_ind_size = Player.size + (max_size - Player.size) * ratio

        local player_cx, player_cy = Player.center()
        local ind_x = player_cx - current_ind_size / 2
        local ind_y = player_cy - current_ind_size / 2

        love.graphics.setColor(1, 1, 1, 0.04 * ratio)
        love.graphics.rectangle("fill", ind_x, ind_y, current_ind_size, current_ind_size)

        love.graphics.setLineWidth(1.2)
        love.graphics.setColor(1, 1, 1, 0.18 * ratio)
        love.graphics.rectangle("line", ind_x, ind_y, current_ind_size, current_ind_size)
        love.graphics.setLineWidth(1)
    end
end

function Player.take_damage(amount, on_death_callback)
    if Debug.god_mode then
        return "dodged"
    end

    if Player.is_dashing then
        return "dodged"
    end

    local dodge_chance = Cards.get("dodge_chance", 0)
    if dodge_chance > 0 and love.math.random() < dodge_chance then
        return "dodged"
    end

    if Player.has_shield then
        Player.has_shield = false
        return "shielded"
    end

    Player.lives = Player.lives - amount
    if Player.lives <= 0 then
        if Cards.consume_extra_life() then
            Player.lives = 1
            return "revived"
        end

        if on_death_callback then
            Player.die(on_death_callback)
            return "dead"
        end
    end

    return "damaged"
end

function Player.die(on_death_callback)
    Player.is_dead = true
    if on_death_callback then
        on_death_callback()
    end
end

function Player.heal(amount)
    if Player.lives >= Player.max_lives then return false end
    Player.lives = math.min(Player.lives + amount, Player.max_lives)
    return true
end

function Player.give_shield()
    if Player.has_shield then return false end
    Player.has_shield = true
    Player.shield_anim_timer = 0
    return true
end

function Player.load_particles()
    local p_data = love.image.newImageData(32, 32)
    for y = 0, 31 do
        for x = 0, 31 do
            local dx = x - 15.5
            local dy = y - 15.5
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist <= 15.5 then
                local alpha = (15.5 - dist) / 15.5
                p_data:setPixel(x, y, 1, 1, 1, alpha)
            end
        end
    end
    local particle_img = love.graphics.newImage(p_data)

    Player.trail = love.graphics.newParticleSystem(particle_img, 1000)
    Player.trail:setParticleLifetime(0.2, 0.4)
    Player.trail:setEmissionRate(60)
    Player.trail:setSizeVariation(0.5)

    Player.trail:setColors(0, 1, 0.85, 0.8, 0, 1, 0.85, 0)
end

function Player.input(moveInput)
    if love.keyboard.isDown("left") or love.keyboard.isDown("a") then moveInput.x = moveInput.x - 1 end
    if love.keyboard.isDown("right") or love.keyboard.isDown("d") then moveInput.x = moveInput.x + 1 end
    if love.keyboard.isDown("up") or love.keyboard.isDown("w") then moveInput.y = moveInput.y - 1 end
    if love.keyboard.isDown("down") or love.keyboard.isDown("s") then moveInput.y = moveInput.y + 1 end

    local gamepad = first_gamepad()
    if not gamepad then return end

    local stick_x = gamepad:getGamepadAxis("leftx")
    local stick_y = gamepad:getGamepadAxis("lefty")

    if math.abs(stick_x) > STICK_DEADZONE then moveInput.x = moveInput.x + stick_x end
    if math.abs(stick_y) > STICK_DEADZONE then moveInput.y = moveInput.y + stick_y end

    if gamepad:isGamepadDown("dpleft") then moveInput.x = moveInput.x - 1 end
    if gamepad:isGamepadDown("dpright") then moveInput.x = moveInput.x + 1 end
    if gamepad:isGamepadDown("dpup") then moveInput.y = moveInput.y - 1 end
    if gamepad:isGamepadDown("dpdown") then moveInput.y = moveInput.y + 1 end
end

function Player.bounds()
    if Player.x < Player.min_x then Player.x = Player.min_x end
    if Player.x > Player.max_x - Player.size then Player.x = Player.max_x - Player.size end
    if Player.y < Player.min_y then Player.y = Player.min_y end
    if Player.y > Player.max_y - Player.size then Player.y = Player.max_y - Player.size end
end

function Player.move(dt)
    local moveVector = get_move_vector()

    if Player.is_dashing then
        Player.x = Player.x + Player.dash_dir.x * Player.dash_speed * dt
        Player.y = Player.y + Player.dash_dir.y * Player.dash_speed * dt

        Player.dash_time_left = Player.dash_time_left - dt

        if Player.dash_time_left <= 0 then
            Player.is_dashing = false
            Player.dash_timer = Player.dash_cooldown * Cards.get("dash_cooldown_mult", 1)
            Player.trail:setEmissionRate(60)
        end
    else
        local speed = Player.speed * Cards.get("move_speed_mult", 1)
        Player.x = Player.x + moveVector.x * speed * dt
        Player.y = Player.y + moveVector.y * speed * dt
    end

    Player.bounds()
end

function Player.try_dash()
    if Player.is_paused or Player.lives <= 0 then return end
    if Player.dash_timer > 0 or Player.is_dashing then return end

    local moveVector = get_move_vector()

    if moveVector.x ~= 0 or moveVector.y ~= 0 then
        Player.is_dashing = true
        Player.dash_time_left = Player.dash_duration * Cards.get("dash_duration_mult", 1)
        Player.dash_dir.x = moveVector.x
        Player.dash_dir.y = moveVector.y
        Player.trail:setEmissionRate(300)
    end
end

function Player.keypressed(key)
    if key == "lshift" or key == "rshift" then
        Player.try_dash()
    end
end

function Player.gamepadpressed(button)
    if button == "a" then
        Player.try_dash()
    end
end

function Player.pause()
    Player.is_paused = true
    Player.trail:stop()
end

function Player.resume()
    Player.is_paused = false
    Player.trail:start()
end

function Player.reset()
    reset_run_state()

    Player.trail:reset()
    Player.trail:start()
    Player.trail:setEmissionRate(60)
end

return Player
