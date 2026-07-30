-- Persistent best for Boss Rush mode (bosses cleared), same shape as
-- src/high_score.lua but its own save file -- the two modes track completely
-- different things (survival score vs. a boss-gauntlet clear count), so they
-- don't share a record.
local BossRushScore = {}

local SAVE_FILE = "bossrush.txt"

function BossRushScore.load()
    BossRushScore.value = 0

    if love.filesystem.getInfo(SAVE_FILE) then
        local contents = love.filesystem.read(SAVE_FILE)
        local parsed = tonumber(contents)
        if parsed then
            BossRushScore.value = parsed
        end
    end
end

function BossRushScore.try_save(cleared)
    if cleared > BossRushScore.value then
        BossRushScore.value = cleared
        love.filesystem.write(SAVE_FILE, tostring(cleared))
        return true
    end

    return false
end

function BossRushScore.reset()
    BossRushScore.value = 0
    love.filesystem.write(SAVE_FILE, "0")
end

return BossRushScore
