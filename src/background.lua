-- src/background.lua
local Background = {}

function Background.load()
    Background.stars = {}
    Background.max_stars = 40 -- Ekrandaki siber çizgi sayısı

    -- Parallaks efekti için çizgileri oluşturuyoruz
    for i = 1, Background.max_stars do
        table.insert(Background.stars, {
            x = love.math.random(0, love.graphics.getWidth()),
            y = love.math.random(0, love.graphics.getHeight()),
            length = love.math.random(12, 38),  -- Çizgi uzunluğu
            speed = love.math.random(90, 260),  -- Farklı hızlar derinlik (parallaks) hissi verir
            width = love.math.random(1, 2),     -- Çizgi kalınlığı
            alpha = love.math.random(1, 2) / 10 -- Arkada çok sönük kalmaları için saydamlık (0.1 - 0.3 arası)
        })
    end
end

function Background.update(dt)
    -- Çizgileri sadece aşağı doğru akıtıyoruz
    for _, s in ipairs(Background.stars) do
        s.y = s.y + s.speed * dt

        -- Ekranın altına çıkan çizgiyi rastgele bir X koordinatıyla yukarıdan tekrar başlat
        if s.y > love.graphics.getHeight() then
            s.y = -s.length
            s.x = love.math.random(0, love.graphics.getWidth())
        end
    end
end

function Background.draw()
    -- Sabit, koyu ve şık siber arka plan rengi
    love.graphics.clear(0.05, 0.05, 0.1)

    -- Çizgilerin rengi: Oyuncunun şarj rengine yakın ama çok sönük bir camgöbeği/turkuvaz tonu
    for _, s in ipairs(Background.stars) do
        love.graphics.setColor(1, 1, 1, s.alpha)
        love.graphics.setLineWidth(s.width)
        love.graphics.line(s.x, s.y, s.x, s.y + s.length)
    end

    -- Renk ve çizgi ayarlarını sıfırla ki sonraki çizimler etkilenmesin
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
end

function Background.reset()
    -- İhtiyaç halinde konumları tekrar rastgele dağıtabilirsin
    for _, s in ipairs(Background.stars) do
        s.y = love.math.random(0, love.graphics.getHeight())
        s.x = love.math.random(0, love.graphics.getWidth())
    end
end

return Background
