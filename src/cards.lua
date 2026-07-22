local Cards = {}

local CARD_POOL = {
    -- Survivability
    {
        id = "vitality",
        name = "Vitality",
        description = "+1 Max HP",
        max_stacks = 10,
        on_pick = function(player)
            player.max_lives = player.max_lives + 1
            player.lives = player.lives + 1
        end,
    },
    {
        id = "guardian_aura",
        name = "Guardian Aura",
        description = "Auto-shield every 12s if you have none (stacks shorten it)",
        max_stacks = 4,
        modifiers = function(stacks, mods)
            mods.auto_shield_interval = math.max(12 - (stacks - 1) * 2, 5)
        end,
    },
    {
        id = "extra_life",
        name = "Extra Life",
        description = "Banked revive: survive your next fatal hit with 1 HP",
        max_stacks = 5,
    },
    {
        id = "regeneration",
        name = "Regeneration",
        description = "Heal 1 HP every 30s if missing HP (stacks shorten it)",
        max_stacks = 4,
        modifiers = function(stacks, mods)
            mods.regen_interval = math.max(30 - (stacks - 1) * 5, 15)
        end,
    },
    {
        id = "void_ward",
        name = "Void Ward",
        description = "Missing a void orb no longer costs HP",
        max_stacks = 1,
        modifiers = function(_, mods)
            mods.void_orb_miss_safe = true
        end,
    },
    {
        id = "evasion",
        name = "Evasion",
        description = "Chance to fully negate a hit (stacks add more)",
        max_stacks = 5,
        modifiers = function(stacks, mods)
            mods.dodge_chance = math.min(stacks * 0.08, 0.4)
        end,
    },
    {
        id = "steady_hands",
        name = "Steady Hands",
        description = "-50% screen shake from hits",
        max_stacks = 1,
        modifiers = function(_, mods)
            mods.shake_mult = 0.5
        end,
    },

    -- Offense / score
    {
        id = "adrenaline",
        name = "Adrenaline",
        description = "Score gained while at 1 HP is doubled",
        max_stacks = 1,
        modifiers = function(_, mods)
            mods.low_hp_score_mult = 2
        end,
    },
    {
        id = "orb_magnet",
        name = "Orb Magnet",
        description = "+2 score per orb",
        max_stacks = 10,
        modifiers = function(stacks, mods)
            mods.orb_score_bonus = stacks * 2
        end,
    },
    {
        id = "void_hunter",
        name = "Void Hunter",
        description = "+5 score per void orb",
        max_stacks = 10,
        modifiers = function(stacks, mods)
            mods.void_orb_score_bonus = stacks * 5
        end,
    },
    {
        id = "bounty_hunter",
        name = "Bounty Hunter",
        description = "+50 bonus score on boss defeat",
        max_stacks = 5,
        modifiers = function(stacks, mods)
            mods.boss_bonus_score_add = stacks * 50
        end,
    },
    {
        id = "wave_bonus",
        name = "Wave Bonus",
        description = "+10 score every wave",
        max_stacks = 10,
        modifiers = function(stacks, mods)
            mods.wave_bonus_score = stacks * 10
        end,
    },
    {
        id = "glass_cannon",
        name = "Glass Cannon",
        description = "+50% score, -1 Max HP",
        max_stacks = 1,
        on_pick = function(player)
            player.max_lives = math.max(player.max_lives - 1, 1)
            if player.lives > player.max_lives then
                player.lives = player.max_lives
            end
        end,
        modifiers = function(_, mods)
            mods.score_mult = 1.5
        end,
    },
    {
        id = "fortunes_favor",
        name = "Fortune's Favor",
        description = "+20 bonus score on every 5-orb milestone",
        max_stacks = 5,
        modifiers = function(stacks, mods)
            mods.orb_milestone_bonus = stacks * 20
        end,
    },

    -- Mobility
    {
        id = "nimble",
        name = "Nimble",
        description = "+15% move speed",
        max_stacks = 5,
        modifiers = function(stacks, mods)
            mods.move_speed_mult = 1 + stacks * 0.15
        end,
    },
    {
        id = "quick_dash",
        name = "Quick Dash",
        description = "-15% dash cooldown",
        max_stacks = 4,
        modifiers = function(stacks, mods)
            mods.dash_cooldown_mult = math.max(1 - stacks * 0.15, 0.25)
        end,
    },
    {
        id = "long_dash",
        name = "Long Dash",
        description = "+20% dash duration",
        max_stacks = 4,
        modifiers = function(stacks, mods)
            mods.dash_duration_mult = 1 + stacks * 0.2
        end,
    },

    -- Hazard easing
    {
        id = "slow_fall",
        name = "Slow Fall",
        description = "-8% hazard fall speed",
        max_stacks = 5,
        modifiers = function(stacks, mods)
            mods.hazard_speed_mult = math.max(1 - stacks * 0.08, 0.6)
        end,
    },
    {
        id = "iron_will",
        name = "Iron Will",
        description = "-40% enemy speed ramp per miss",
        max_stacks = 1,
        modifiers = function(_, mods)
            mods.enemy_ramp_mult = 0.6
        end,
    },
    {
        id = "calm_mind",
        name = "Calm Mind",
        description = "-30% hitstop duration",
        max_stacks = 1,
        modifiers = function(_, mods)
            mods.hitstop_mult = 0.7
        end,
    },
}

local CARD_BY_ID = {}
for _, card in ipairs(CARD_POOL) do
    CARD_BY_ID[card.id] = card
end

function Cards.load()
    Cards.owned = {}
    Cards.modifiers = {}
    Cards.auto_shield_timer = 0
    Cards.regen_timer = 0
    Cards.is_paused = false
end

function Cards.get(key, default)
    local value = Cards.modifiers[key]
    if value == nil then
        return default
    end
    return value
end

function Cards.recompute()
    local mods = {}
    for id, stacks in pairs(Cards.owned) do
        if stacks > 0 then
            local card = CARD_BY_ID[id]
            if card and card.modifiers then
                card.modifiers(stacks, mods)
            end
        end
    end
    Cards.modifiers = mods
end

function Cards.roll_choices(n)
    local available = {}
    for _, card in ipairs(CARD_POOL) do
        local stacks = Cards.owned[card.id] or 0
        if not card.max_stacks or stacks < card.max_stacks then
            table.insert(available, card)
        end
    end

    local choices = {}
    for _ = 1, math.min(n, #available) do
        local index = love.math.random(1, #available)
        table.insert(choices, available[index])
        table.remove(available, index)
    end

    return choices
end

function Cards.choose(id, player)
    local card = CARD_BY_ID[id]
    if not card then return end

    Cards.owned[id] = (Cards.owned[id] or 0) + 1

    if card.on_pick then
        card.on_pick(player)
    end

    Cards.recompute()
end

function Cards.consume_extra_life()
    local stacks = Cards.owned["extra_life"] or 0
    if stacks <= 0 then return false end

    Cards.owned["extra_life"] = stacks - 1
    Cards.recompute()
    return true
end

function Cards.update(dt, game_over, player)
    if game_over or Cards.is_paused then return end

    local shield_interval = Cards.get("auto_shield_interval", math.huge)
    if shield_interval < math.huge then
        Cards.auto_shield_timer = math.min(Cards.auto_shield_timer + dt, shield_interval)
        if Cards.auto_shield_timer >= shield_interval and not player.has_shield then
            player.give_shield()
            Cards.auto_shield_timer = 0
        end
    end

    local regen_interval = Cards.get("regen_interval", math.huge)
    if regen_interval < math.huge then
        Cards.regen_timer = math.min(Cards.regen_timer + dt, regen_interval)
        if Cards.regen_timer >= regen_interval and player.lives < player.max_lives then
            player.heal(1)
            Cards.regen_timer = 0
        end
    end
end

function Cards.pause() Cards.is_paused = true end

function Cards.resume() Cards.is_paused = false end

function Cards.reset()
    Cards.owned = {}
    Cards.modifiers = {}
    Cards.auto_shield_timer = 0
    Cards.regen_timer = 0
end

return Cards
