local Player = {}

local SHIELD_ANIM_DURATION = 0.35

function Player.load()
    Player.x = love.graphics.getWidth() / 2 - 15
    Player.y = love.graphics.getHeight() - 100
    Player.size = 35
    Player.speed = 325
    Player.lives = 3
    Player.max_lives = 3
    Player.is_paused = false

    Player.dash_speed = 900
    Player.dash_duration = 0.10
    Player.dash_cooldown = 0.75
    Player.dash_timer = 0
    Player.dash_time_left = 0
    Player.is_dashing = false
    Player.dash_dir = { x = 0, y = 0 }

    Player.flicker_timer = 0
    Player.is_dead = false

    Player.has_shield = false
    Player.shield_anim_timer = SHIELD_ANIM_DURATION

    Player.load_particles()
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

    Player.trail:setPosition(Player.x + Player.size / 2, Player.y + Player.size / 2)
    Player.trail:update(dt)
end

function Player.draw()
    if Player.is_dead then return end

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
        local player_cx = Player.x + Player.size / 2
        local player_cy = Player.y + Player.size / 2

        local t = math.min(Player.shield_anim_timer / SHIELD_ANIM_DURATION, 1)
        local eased = 1 - (1 - t) * (1 - t)

        love.graphics.setLineWidth(4)
        love.graphics.setColor(0.3, 0.65, 1, 0.9 * eased)
        love.graphics.circle("line", player_cx, player_cy, Player.size * 0.85 * eased)
        love.graphics.setLineWidth(1)
    end

    if Player.dash_timer > 0 then
        local ratio = Player.dash_timer / Player.dash_cooldown
        local max_size = Player.size * 2.0
        local current_ind_size = Player.size + (max_size - Player.size) * ratio

        local player_cx = Player.x + Player.size / 2
        local player_cy = Player.y + Player.size / 2
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
    if Player.has_shield then
        Player.has_shield = false
        return "shielded"
    end

    Player.lives = Player.lives - amount
    if Player.lives <= 0 and on_death_callback then
        Player.die(on_death_callback)
        return "dead"
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
end

function Player.bounds()
    if Player.x < 0 then Player.x = 0 end
    if Player.x > love.graphics.getWidth() - Player.size then Player.x = love.graphics.getWidth() - Player.size end
    if Player.y < 0 then Player.y = 0 end
    if Player.y > love.graphics.getHeight() - Player.size then Player.y = love.graphics.getHeight() - Player.size end
end

function Player.move(dt)
    local moveInput = { x = 0, y = 0 }
    local moveVector = { x = 0, y = 0 }

    Player.input(moveInput)

    if (math.abs(moveInput.x) == 1 and math.abs(moveInput.y) == 1) then
        moveVector.x = moveInput.x / math.sqrt(2)
        moveVector.y = moveInput.y / math.sqrt(2)
    else
        moveVector.x = moveInput.x
        moveVector.y = moveInput.y
    end

    if Player.is_dashing then
        Player.x = Player.x + Player.dash_dir.x * Player.dash_speed * dt
        Player.y = Player.y + Player.dash_dir.y * Player.dash_speed * dt

        Player.dash_time_left = Player.dash_time_left - dt

        if Player.dash_time_left <= 0 then
            Player.is_dashing = false
            Player.dash_timer = Player.dash_cooldown
            Player.trail:setEmissionRate(60)
        end
    else
        Player.x = Player.x + moveVector.x * Player.speed * dt
        Player.y = Player.y + moveVector.y * Player.speed * dt
    end

    Player.bounds()
end

function Player.keypressed(key)
    if Player.is_paused or Player.lives <= 0 then return end

    if (key == "lshift" or key == "rshift") and Player.dash_timer <= 0 and not Player.is_dashing then
        local moveInput = { x = 0, y = 0 }
        Player.input(moveInput)

        local moveVector = { x = 0, y = 0 }
        if (math.abs(moveInput.x) == 1 and math.abs(moveInput.y) == 1) then
            moveVector.x = moveInput.x / math.sqrt(2)
            moveVector.y = moveInput.y / math.sqrt(2)
        else
            moveVector.x = moveInput.x
            moveVector.y = moveInput.y
        end

        if moveVector.x ~= 0 or moveVector.y ~= 0 then
            Player.is_dashing = true
            Player.dash_time_left = Player.dash_duration
            Player.dash_dir.x = moveVector.x
            Player.dash_dir.y = moveVector.y
            Player.trail:setEmissionRate(300)
        end
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
    Player.is_dead = false
    Player.x = love.graphics.getWidth() / 2 - 15
    Player.y = love.graphics.getHeight() - 100
    Player.lives = Player.max_lives
    Player.dash_timer = 0
    Player.is_dashing = false
    Player.flicker_timer = 0
    Player.has_shield = false
    Player.shield_anim_timer = SHIELD_ANIM_DURATION
    Player.trail:reset()
    Player.trail:start()
    Player.trail:setEmissionRate(60)
end

return Player
