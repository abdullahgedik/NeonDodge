-- src/fx_manager.lua
local FXManager = {}

function FXManager.load()
    FXManager.active_particles = {}
    FXManager.active_rings = {}

    -- Saf Kırmızı Düşman Patlama Şablonu için 6x6 beyaz kare dokusu
    local p_data = love.image.newImageData(6, 6)
    for y = 0, 5 do for x = 0, 5 do p_data:setPixel(x, y, 1, 1, 1, 1) end end
    local p_img = love.graphics.newImage(p_data)

    -- Şablon Yapısı: İleride buraya "player_death", "orb_collect" gibi yeni şablonlar ekleyebiliriz
    FXManager.templates = {
        enemy_explosion = {
            image = p_img,
            buffer = 400,
            setup = function(ps)
                ps:setParticleLifetime(0.5, 0.8)
                ps:setSpeed(0)
                ps:setLinearAcceleration(-750, -750, 750, 750)
                ps:setEmissionArea("normal", 4, 4) -- Güncel LÖVE versiyonu fonksiyonu
                ps:setColors(
                    1, 0, 0, 1,                    -- Doğuşta saf kırmızı
                    1, 0, 0, 1,                    -- Ömrünün ortasında saf kırmızı
                    1, 0, 0, 0                     -- Sönerken saydam
                )
                ps:setSizeVariation(0.6)
            end
        },
        -- YENİ: Büyük Mor/Eflatun Void Orb Kaçırma Patlaması
        void_explosion = {
            image = p_img,
            buffer = 600,                        -- Daha büyük bir patlama için maksimum partikül tamponunu artırdık
            setup = function(ps)
                ps:setParticleLifetime(0.7, 1.2) -- Havada kalma süresini ciddi oranda uzattık
                ps:setSpeed(0)
                -- İvmelenmeyi çok daha yüksek vererek parçaların devasa bir çapa yayılmasını sağlıyoruz
                ps:setLinearAcceleration(-1000, -1000, 1000, 1000)
                ps:setEmissionArea("normal", 10, 10) -- Çıkış alanını biraz daha genişleterek hacim kattık

                -- RENK: VoidOrb'un kendi renk paleti (Neon Mor / Eflatun: 0.7, 0.2, 1)
                -- Uzun süre bu renkte kalıp son anlarda sönüyorlar
                ps:setColors(
                    0.7, 0.2, 1, 1,      -- Doğuşta parlak mor
                    0.6, 0.0, 1, 1,      -- Ömrünün ortasında derin eflatun
                    0.5, 0.0, 0.8, 0     -- Sönerken saydamlaşma
                )
                ps:setSizeVariation(0.8) -- Parça boyutlarındaki çeşitliliği artırdık (büyük/küçük parçalar bir arada)
            end
        },
        player_damage = {
            image = p_img,
            buffer = 100,
            setup = function(ps)
                ps:setParticleLifetime(0.15, 0.35)
                ps:setSpeed(0)
                ps:setLinearAcceleration(-500, -500, 500, 500)
                ps:setEmissionArea("normal", 2, 2)
                ps:setColors(0, 1, 0.85, 1, 0, 0.6, 0.3, 1, 0, 1, 0.3, 0) -- Turkuvazdan yeşile sönen sızıntı
                ps:setSizeVariation(0.4)
            end
        },

        -- SİBER ÖLÜM PATLAMASI (Yeni Şarjlı Renk Tonu)
        player_death = {
            image = p_img,
            buffer = 800,
            setup = function(ps)
                ps:setParticleLifetime(0.8, 1.5)
                ps:setSpeed(0)
                ps:setLinearAcceleration(-1200, -1200, 1200, 1200)
                ps:setEmissionArea("normal", 15, 15)
                ps:setColors(
                    0, 1, 0.85, 1,  -- Patlama anı parlak şarj rengi
                    0, 0.6, 0.3, 1, -- Dağılırken dijital camgöbeği
                    0, 0.3, 0.2, 0  -- Sönerken karanlık siber yeşil
                )
                ps:setSizeVariation(0.7)
            end
        }
    }
end

-- Yeni bir patlama efekti tetiklemek için bu fonksiyonu çağıracağız
function FXManager.spawn(template_name, x, y, count)
    local template = FXManager.templates[template_name]
    if not template then return end

    -- Her patlama için bağımsız bir ParticleSystem oluşturuyoruz
    local ps = love.graphics.newParticleSystem(template.image, template.buffer)
    template.setup(ps)
    ps:setPosition(x, y)
    ps:emit(count or 25)

    table.insert(FXManager.active_particles, ps)
end

-- YENİ: Şok dalgası halkası oluşturma fonksiyonu
function FXManager.spawn_ring(x, y, r, g, b, start_radius, max_radius, expand_speed)
    local ring = {
        x = x,
        y = y,
        r = r,
        g = g,
        b = b, -- Halkanın rengi (RGB)
        current_radius = start_radius or 10,
        max_radius = max_radius or 60,
        expand_speed = expand_speed or 150, -- Saniyede kaç piksel büyüyeceği
        alpha = 1.0
    }
    table.insert(FXManager.active_rings, ring)
end

function FXManager.update(dt)
    -- 1. Partikülleri Güncelle (Aynı kalıyor)
    for i = #FXManager.active_particles, 1, -1 do
        local ps = FXManager.active_particles[i]
        ps:update(dt)
        if ps:getCount() == 0 then table.remove(FXManager.active_particles, i) end
    end

    -- 2. YENİ: Şok Dalgası Halkalarını Güncelle
    for i = #FXManager.active_rings, 1, -1 do
        local ring = FXManager.active_rings[i]

        -- Halkayı büyüt
        ring.current_radius = ring.current_radius + ring.expand_speed * dt

        -- Görünmezliğe (Alpha = 0) doğru doğrusal sönümleme yapıyoruz
        local progress = (ring.current_radius - 10) / (ring.max_radius - 10)
        ring.alpha = 1.0 - progress

        -- Eğer halka maksimum boyuta ulaştıysa veya tamamen söndüyse sil
        if ring.current_radius >= ring.max_radius or ring.alpha <= 0 then
            table.remove(FXManager.active_rings, i)
        end
    end
end

function FXManager.draw()
    -- 1. Partikülleri Çiz (Aynı kalıyor)
    love.graphics.setColor(1, 1, 1, 1)
    for _, ps in ipairs(FXManager.active_particles) do
        love.graphics.draw(ps, 0, 0)
    end

    -- 2. YENİ: Şok Dalgası Halkalarını Çiz
    love.graphics.setLineWidth(3) -- Çizgi kalınlığını 3 piksel yaparak neonu belirginleştiriyoruz
    for _, ring in ipairs(FXManager.active_rings) do
        love.graphics.setColor(ring.r, ring.g, ring.b, ring.alpha)
        -- "line" parametresi sayesinde içi boş, sadece dış çeperi olan daire çizilir
        love.graphics.circle("line", ring.x, ring.y, ring.current_radius)
    end
    love.graphics.setLineWidth(1) -- Çizgi kalınlığını normale geri çekiyoruz (başka çizimleri bozmasın)
end

function FXManager.reset()
    FXManager.active_particles = {}
    FXManager.active_rings = {} -- Reset anında halkaları da temizle
end

return FXManager
