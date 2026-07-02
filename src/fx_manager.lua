-- src/fx_manager.lua
local FXManager = {}

function FXManager.load()
    FXManager.active_particles = {}

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

function FXManager.update(dt)
    for i = #FXManager.active_particles, 1, -1 do
        local ps = FXManager.active_particles[i]
        ps:update(dt)

        -- Eğer partikül sistemindeki tüm parçacıklar ömrünü tamamladıysa sistem temizlenir
        if ps:getCount() == 0 then
            table.remove(FXManager.active_particles, i)
        end
    end
end

function FXManager.draw()
    -- Partiküllerin kendi saf renkleriyle maskelenmeden çizilmesi için rengi beyaza çekiyoruz
    love.graphics.setColor(1, 1, 1, 1)
    for _, ps in ipairs(FXManager.active_particles) do
        love.graphics.draw(ps, 0, 0)
    end
end

function FXManager.reset()
    FXManager.active_particles = {}
end

return FXManager
