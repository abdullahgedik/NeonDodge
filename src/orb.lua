local Orb = {}

function Orb.load()
    Orb.list = {}
    Orb.speed = 175
    Orb.spawn_timer = 0
    Orb.radius = 12 -- Dairemizin yarıçapı (size yerine yarıçap isimlendirmesi daha doğru olur)
    Orb.is_paused = false
end

function Orb.update(dt, game_over, player, on_collision, spawn_rate)
    if game_over then return end

    if Orb.is_paused then return end

    Orb.spawn(dt, spawn_rate)
    Orb.move_and_process(dt, player, on_collision)
end

function Orb.draw()
    love.graphics.setColor(1, 0.9, 0.2) -- Parlak neon sarı
    for _, o in ipairs(Orb.list) do
        -- LÖVE daireyi merkez noktasına göre çizer: "fill", merkez_x, merkez_y, yarıçap
        love.graphics.circle("fill", o.x, o.y, o.radius)
    end
end

function Orb.spawn(dt, spawn_rate)
    Orb.spawn_timer = Orb.spawn_timer + dt
    if Orb.spawn_timer > spawn_rate then
        Orb.spawn_timer = 0
        -- Dairenin ekrandan taşmaması için sınırları yarıçapa göre ayarlıyoruz
        local random_x = love.math.random(Orb.radius, love.graphics.getWidth() - Orb.radius)
        -- o.x ve o.y artık doğrudan dairenin MERKEZ noktası olacak
        table.insert(Orb.list, { x = random_x, y = -20, radius = Orb.radius })
    end
end

-- BUG FIX: Tek bir güvenli ters döngüyle tüm mantığı birleştirdik
function Orb.move_and_process(dt, player, on_collision)
    for i = #Orb.list, 1, -1 do
        local o = Orb.list[i]

        -- Hareket ettir
        o.y = o.y + Orb.speed * dt

        -- BUG FIX: Kare (Oyuncu) ile Daire (Orb) arasında merkez tabanlı hassas çarpışma kontrolü
        -- Oyuncunun merkez noktasını buluyoruz
        local player_cx = player.x + player.size / 2
        local player_cy = player.y + player.size / 2

        -- İki merkez arasındaki mesafe (Pisagor)
        local distance = math.sqrt((player_cx - o.x) ^ 2 + (player_cy - o.y) ^ 2)

        -- Eğer mesafe oyuncunun yarıçapı ile orban yarıçapının toplamından küçükse temas vardır
        if distance < (player.size / 2 + o.radius) then
            on_collision(i) -- main.lua'daki callback'i tetikle
            goto continue
        end

        -- Ekrandan çıkma kontrolü
        if o.y > love.graphics.getHeight() + o.radius then
            Orb.remove(i)
        end

        ::continue::
    end
end

function Orb.remove(index)
    table.remove(Orb.list, index)
end

function Orb.pause()
    Orb.is_paused = true
end

function Orb.resume()
    Orb.is_paused = false
end

function Orb.reset()
    Orb.list = {}
    Orb.speed = 175
    Orb.spawn_timer = 0
end

return Orb
