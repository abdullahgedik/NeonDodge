local Player = {}

function Player.load()
    Player.x = love.graphics.getWidth() / 2 - 15
    Player.y = love.graphics.getHeight() - 100
    Player.size = 35
    Player.speed = 325
    Player.lives = 3
    Player.max_lives = 3

    Player.load_particles()
end

function Player.update(dt, game_over)
    if game_over then
        Player.trail:stop()
        return
    end

    Player.move(dt)

    -- Trail güncellemesi
    Player.trail:setPosition(Player.x + Player.size / 2, Player.y + Player.size / 2)
    Player.trail:update(dt)
end

function Player.draw()
    -- Önce trail (arkada kalsın)
    love.graphics.setBlendMode("add")
    love.graphics.draw(Player.trail, 0, 0)
    love.graphics.setBlendMode("alpha")

    -- Sonra oyuncu küpü
    love.graphics.setColor(0, 1, 0.5)
    love.graphics.rectangle("fill", Player.x, Player.y, Player.size, Player.size)
end

function Player.take_damage(amount)
    Player.lives = Player.lives - amount
    if Player.lives < 0 then
        Player.lives = 0
        Player.die()
    end
end

function Player.die()
    game_over = true
end

function Player.load_particles()
    -- Parçacık sistemini de oyuncunun bir alt bileşeni (Component) gibi buraya bağlıyoruz
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
    Player.trail:setColors(0, 1, 0.5, 0.8, 0, 1, 0.5, 0)
end

function Player.input(moveInput)
    if love.keyboard.isDown("left") or love.keyboard.isDown("a") then moveInput.x = moveInput.x - 1 end
    if love.keyboard.isDown("right") or love.keyboard.isDown("d") then moveInput.x = moveInput.x + 1 end
    if love.keyboard.isDown("up") or love.keyboard.isDown("w") then moveInput.y = moveInput.y - 1 end
    if love.keyboard.isDown("down") or love.keyboard.isDown("s") then moveInput.y = moveInput.y + 1 end
end

function Player.bounds()
    -- Ekran sınırları koruması
    if Player.x < 0 then Player.x = 0 end
    if Player.x > love.graphics.getWidth() - Player.size then Player.x = love.graphics.getWidth() - Player.size end
    if Player.y < 0 then Player.y = 0 end
    if Player.y > love.graphics.getHeight() - Player.size then Player.y = love.graphics.getHeight() - Player.size end
end

local function normalizeVector(x, y) --Will be implemented in the future for diagonal movement normalization
    local length = math.sqrt(x * x + y * y)
    if length == 0 then
        return 0, 0
    else
        return x / length, y / length
    end
end

function Player.move(dt)
    -- Yazdığın 8 yönlü hareket kodunu buraya gömdük
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

    Player.x = Player.x + moveVector.x * Player.speed * dt
    Player.y = Player.y + moveVector.y * Player.speed * dt

    Player.bounds() -- Ekran sınırlarını koru
end

function Player.reset()
    Player.x = love.graphics.getWidth() / 2 - 15
    Player.y = love.graphics.getHeight() - 100
    Player.lives = Player.max_lives
    Player.trail:start()
    Player.trail:reset()
end

return Player
