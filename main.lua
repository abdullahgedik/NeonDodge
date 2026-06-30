-- Oyun ilk açıldığında bir kez çalışır (Tanımlamalar burada yapılır)
function love.load()
    -- Oyuncu değişkenleri
    player = {
        x = 400,
        y = 500,
        size = 30,
        speed = 300
    }
end

-- Oyun döngüsü (Saniyede onlarca kez çalışır, mantık ve hareket buradadır)
-- dt: 'delta time' demektir. Bilgisayar hızından bağımsız sabit hızda hareket sağlar.
function love.update(dt)
    -- Sola hareket
    if love.keyboard.isDown("left") or love.keyboard.isDown("a") then
        player.x = player.x - player.speed * dt
    end
    -- Sağa hareket
    if love.keyboard.isDown("right") or love.keyboard.isDown("d") then
        player.x = player.x + player.speed * dt
    end
end

-- Ekrana çizim yapma fonksiyonu (Her karede yenilenir)
function love.draw()
    -- Arka planı koyu gri yapalım
    love.graphics.clear(0.1, 0.1, 0.1)

    -- Oyuncuyu neon yeşili bir kare olarak çizelim
    love.graphics.setColor(0, 1, 0.5)
    love.graphics.rectangle("fill", player.x, player.y, player.size, player.size)
end
