local HighScore = {}

local SAVE_FILE = "highscore.txt"

function HighScore.load()
    HighScore.value = 0

    if love.filesystem.getInfo(SAVE_FILE) then
        local contents = love.filesystem.read(SAVE_FILE)
        local parsed = tonumber(contents)
        if parsed then
            HighScore.value = parsed
        end
    end
end

function HighScore.try_save(score)
    if score > HighScore.value then
        HighScore.value = score
        love.filesystem.write(SAVE_FILE, tostring(score))
        return true
    end

    return false
end

return HighScore
