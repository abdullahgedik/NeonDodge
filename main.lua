-- main.lua
local Player                   = require("src/player")
local Enemy                    = require("src/enemy")
local ZigzagEnemy              = require("src/zigzag_enemy")
local Orb                      = require("src/orb")
local VoidOrb                  = require("src/void_orb")
local Mine                     = require("src/mine")
local UI                       = require("src/ui")
local FXManager                = require("src/fx_manager")
local Background               = require("src/background")
local GameState                = require("src/game_state")
local Difficulty               = require("src/difficulty")
local Bloom                    = require("src/bloom")
local Boss                     = require("src/boss")
local Projectile               = require("src/projectile")
local HitEffect                = require("src/hit_effect")
local HighScore                = require("src/high_score")
local Cards                    = require("src/cards")
local Debug                    = require("src/debug")
local Screen                   = require("src/screen")

-- Three deliberately different module lists, each covering one lifecycle
-- step. They overlap heavily but are NOT interchangeable -- see each note.

-- everything with a .load(), in initialization order. Screen goes first: it
-- resolves the window -> game transform every other module's dimensions are
-- expressed against.
local LOADABLE_MODULES         = {
    Screen, Player, Enemy, ZigzagEnemy, Orb, VoidOrb, Mine, UI, FXManager, Background,
    GameState, Difficulty, Bloom, Boss, Projectile, HitEffect, HighScore, Cards, Debug
}

-- every module whose simulation must halt while the game is paused (pause
-- screen, card select). Deliberately not every module: Background/FXManager
-- keep animating, and Bloom/HitEffect/UI/HighScore have no such state.
local PAUSABLE_MODULES         = {
    Player, Enemy, ZigzagEnemy, Mine, Orb, VoidOrb, Difficulty, Boss, Projectile, Cards
}

-- everything a fresh run wipes. Excludes UI/Bloom (no run state), HighScore
-- (persists by design -- that's the whole point of it) and GameState (the
-- caller sets the target state itself); includes Background/FXManager, which
-- the pause list deliberately skips.
local RESETTABLE_MODULES       = {
    Player, Enemy, ZigzagEnemy, Mine, Orb, VoidOrb, FXManager, Background,
    Difficulty, Boss, Projectile, HitEffect, Cards
}

local score                    = 0
local collected_orb_amount     = 0

local shake_duration           = 0
local shake_magnitude          = 0

local hitstop_timer            = 0

local BOSS_WAVE_INTERVAL       = 6
local last_boss_wave           = 0
local last_wave_seen           = 1
local boss_encounter_index     = 0
local current_card_choices     = nil
local card_cursor              = 1
-- shared cursor for whichever simple menu (main menu / pause) is currently
-- showing -- only one is ever active at once, so one variable is enough;
-- reset to 1 whenever either screen is (re)entered
local menu_cursor              = 1

-- "Reset High Score" arms instead of firing immediately -- a second confirm
-- within RESET_CONFIRM_DELAY seconds actually resets it, so a misclick
-- can't silently erase the record. Disarms on timeout or on navigating the
-- cursor away from that option.
local RESET_CONFIRM_DELAY      = 3
local reset_confirm_timer      = 0
-- index of "Reset High Score" within UI.MAIN_MENU_OPTIONS
local MAIN_MENU_RESET_INDEX    = 2

local CARD_CHOICE_COUNT        = 3

-- transition pacing: three deliberate breathers so the game doesn't slam
-- straight from normal play into a boss, or from a boss into the reward
-- screen, or out of the reward screen back into danger
local BOSS_INCOMING_DELAY      = 1.8 -- telegraph before a boss actually spawns
local POST_BOSS_PAUSE_DURATION = 1.0 -- freeze-beat after a boss dies, before the card screen opens
local CARD_CONFIRM_DELAY       = 0.5 -- holds the card screen after a pick so it reads as confirmed

local boss_incoming_timer      = 0
local pending_boss_type        = nil
local post_boss_pause_timer    = 0
local pending_card_select      = false
local card_confirm_timer       = 0
local chosen_card_index        = nil
local card_select_elapsed      = 0

-- progressive hazard unlocks: instead of every hazard/pickup type being
-- live from wave 1 (only their spawn *rate* ramping), the roster itself
-- grows one event at a time -- each boss defeated or storm survived bumps
-- unlock_stage, and VoidOrb/ZigzagEnemy/Mine each wait for their stage
-- before they're eligible to spawn at all. Enemy and Orb are always on.
local UNLOCK_STAGE_VOID_ORB    = 1
local UNLOCK_STAGE_ZIGZAG      = 2
local UNLOCK_STAGE_MINE        = 3
local MAX_UNLOCK_STAGE         = UNLOCK_STAGE_MINE

local unlock_stage             = 0

-- mid-wave "storm" events: every STORM_WAVE_INTERVAL waves (skipping boss
-- waves), a short burst of much denser hazard spawns, then back to normal --
-- adds rhythm to the wave system beyond its otherwise-smooth difficulty
-- ramp. With BOSS_WAVE_INTERVAL a multiple of this, storms and bosses
-- naturally alternate every STORM_WAVE_INTERVAL waves with no gaps. Unlike
-- the boss telegraph, gameplay stays completely normal during the storm's
-- own telegraph -- the point is "brace yourself", not "calm down"
local STORM_WAVE_INTERVAL      = 3
local STORM_TELEGRAPH_DELAY    = 1.2
local STORM_DURATION           = 10

-- one storm type per hazard, each unlocking alongside the hazard it's built
-- around (see unlock_stage above), so the storm roster grows with the hazard
-- roster instead of every storm being the same event forever.
--
-- `rates` multiplies that hazard's Difficulty.spawn_rate -- which is a
-- *period*, so a value below 1 means "spawns more often" (0.35 ~= 3x) and 1
-- means "unchanged". Any hazard NOT listed is suppressed outright for the
-- storm's duration: an early version sped up every hazard type at once and
-- was unsurvivable in practice, so a storm is deliberately defined by which
-- single hazard it narrows down to, not by piling all of them on.
local STORM_TYPES              = {
    {
        id = "swarm",
        name = "HAZARD STORM",
        color = { 1, 0.5, 0.1 },
        required_unlock_stage = 0,
        rates = { enemy = 0.35, orb = 0.35 },
    },
    {
        -- inverts the game's core instinct: these must be *caught*, and
        -- missing one costs HP, so "dodge everything" actively kills you
        id = "void_rain",
        name = "VOID RAIN",
        color = { 0.75, 0.3, 1 },
        required_unlock_stage = UNLOCK_STAGE_VOID_ORB,
        rates = { void_orb = 0.32, orb = 0.6, enemy = 1 },
    },
    {
        id = "crossfire",
        name = "CROSSFIRE",
        color = { 1, 0.3, 0.05 },
        required_unlock_stage = UNLOCK_STAGE_ZIGZAG,
        rates = { zigzag = 0.3, orb = 0.6, enemy = 1 },
    },
    {
        -- zone denial rather than dodging -- the arena fills with blast
        -- circles and safe space is what keeps moving, not the hazards
        id = "minefield",
        name = "MINEFIELD",
        color = { 0.9, 0.6, 0.2 },
        required_unlock_stage = UNLOCK_STAGE_MINE,
        rates = { mine = 0.3, orb = 0.6, enemy = 1 },
    },
}

local last_storm_wave          = 0
local storm_telegraph_timer    = 0
local storm_timer              = 0
-- the type picked for the current storm, held from the telegraph starting
-- through the storm ending (the banner needs it during the telegraph, when
-- spawn rates are still normal)
local storm_type               = nil
local last_storm_type          = nil

-- forward-declared: love.update (defined next) needs to call these, but
-- they're defined further down as plain local functions
local trigger_card_select
local finish_card_select

-- picks the storm about to run from the types unlocked so far, avoiding an
-- immediate repeat whenever there's more than one to choose from (so the
-- roster growing actually reads as variety instead of the same roll twice)
local function pick_storm_type()
    local eligible = {}
    for _, def in ipairs(STORM_TYPES) do
        if unlock_stage >= def.required_unlock_stage and def ~= last_storm_type then
            table.insert(eligible, def)
        end
    end

    -- only the just-played type is unlocked (i.e. very early on, when swarm
    -- is the whole roster) -- repeating it beats having no storm at all
    if #eligible == 0 then return last_storm_type or STORM_TYPES[1] end

    return eligible[love.math.random(#eligible)]
end

-- resolves one hazard's spawn period for this frame. math.huge means "never
-- spawns", used for all three suppression cases: a boss encounter is on
-- screen, the hazard isn't unlocked yet, or a storm is running that this
-- hazard isn't part of.
local function spawn_rate_for(kind, storm, suppressed, unlocked)
    if suppressed or not unlocked then return math.huge end

    if storm then
        local mult = storm.rates[kind]
        if not mult then return math.huge end
        return Difficulty.spawn_rate(kind) * mult
    end

    return Difficulty.spawn_rate(kind)
end

function love.load()
    for _, module in ipairs(LOADABLE_MODULES) do module.load() end
end

function love.update(dt)
    if GameState.is(GameState.MENU) then
        Background.update(dt)
        if reset_confirm_timer > 0 then
            reset_confirm_timer = reset_confirm_timer - dt
        end
        return
    end

    if GameState.is(GameState.PAUSED) then return end

    if GameState.is(GameState.CARD_SELECT) then
        card_select_elapsed = card_select_elapsed + dt

        if card_confirm_timer > 0 then
            card_confirm_timer = card_confirm_timer - dt
            if card_confirm_timer <= 0 then
                finish_card_select()
            end
        end

        return
    end

    if hitstop_timer > 0 then
        hitstop_timer = hitstop_timer - dt
        return
    end

    -- a short freeze-frame beat after a boss dies, before the card screen
    -- opens -- otherwise the reward screen slams in the instant the boss's
    -- exit animation finishes, with no breathing room at all
    if post_boss_pause_timer > 0 then
        post_boss_pause_timer = post_boss_pause_timer - dt
        if post_boss_pause_timer <= 0 and pending_card_select then
            pending_card_select = false
            trigger_card_select()
        end
        return
    end

    if shake_duration > 0 then
        shake_duration = shake_duration - dt
    else
        shake_magnitude = 0
    end

    HitEffect.update(dt, Player.lives == 1 and not Player.is_dead)

    local is_game_over = GameState.is(GameState.GAME_OVER)

    Cards.update(dt, is_game_over, Player)

    Difficulty.update(dt, is_game_over)

    -- resolved once per frame and reused by the wave-bonus, boss-cadence and
    -- storm-cadence checks below, which each used to call Difficulty.wave()
    -- again for the same answer
    local wave = Difficulty.wave()

    if not is_game_over then
        if wave > last_wave_seen then
            last_wave_seen = wave
            love.increase_score(Cards.get("wave_bonus_score", 0))
        end
    end

    -- telegraph delay before a boss actually appears: existing hazards keep
    -- falling but no new ones spawn while boss_incoming_timer counts down
    -- (see suppress_spawns below), and a warning banner shows, so the wave
    -- doesn't jump straight from "normal" to "boss" with zero warning
    if not is_game_over and not Boss.active and boss_incoming_timer <= 0 then
        if wave > last_boss_wave and wave % BOSS_WAVE_INTERVAL == 0 then
            last_boss_wave = wave
            pending_boss_type = Boss.SEQUENCE[(boss_encounter_index % #Boss.SEQUENCE) + 1]
            boss_encounter_index = boss_encounter_index + 1
            boss_incoming_timer = BOSS_INCOMING_DELAY
        end
    end

    if boss_incoming_timer > 0 then
        boss_incoming_timer = boss_incoming_timer - dt
        if boss_incoming_timer <= 0 then
            Boss.spawn(pending_boss_type)
            pending_boss_type = nil
        end
    end

    -- storm events never overlap a boss encounter or its own telegraph --
    -- they only ever get scheduled on a wave number that isn't also a boss
    -- wave, but this guard also blocks a debug-forced boss from landing
    -- mid-storm
    if not is_game_over and not Boss.active and boss_incoming_timer <= 0
        and storm_timer <= 0 and storm_telegraph_timer <= 0 then
        if wave > last_storm_wave and wave % STORM_WAVE_INTERVAL == 0 and wave % BOSS_WAVE_INTERVAL ~= 0 then
            last_storm_wave = wave
            -- picked at telegraph time (not when the storm itself starts) so
            -- the warning banner can name which storm is coming
            storm_type = pick_storm_type()
            last_storm_type = storm_type
            storm_telegraph_timer = STORM_TELEGRAPH_DELAY
        end
    end

    if storm_telegraph_timer > 0 then
        storm_telegraph_timer = storm_telegraph_timer - dt
        if storm_telegraph_timer <= 0 then
            storm_timer = STORM_DURATION
        end
    elseif storm_timer > 0 then
        storm_timer = storm_timer - dt
        if storm_timer <= 0 then
            storm_timer = 0
            storm_type = nil
            unlock_stage = math.min(unlock_stage + 1, MAX_UNLOCK_STAGE)
        end
    end

    -- the boss encounter (if any) decides how much of the screen is legal
    -- this frame; with none active this resolves to the full screen
    Player.min_x, Player.min_y, Player.max_x, Player.max_y = Boss.get_player_bounds()
    Player.update(dt, is_game_over)

    local suppress_spawns = Boss.active or boss_incoming_timer > 0
    -- only applies once the storm is actually running -- during its telegraph
    -- storm_type is already picked (for the banner) but spawn rates stay normal
    local active_storm = (storm_timer > 0) and storm_type or nil
    local zigzag_unlocked = unlock_stage >= UNLOCK_STAGE_ZIGZAG
    local void_orb_unlocked = unlock_stage >= UNLOCK_STAGE_VOID_ORB
    local mine_unlocked = unlock_stage >= UNLOCK_STAGE_MINE

    Enemy.update(dt, is_game_over, Player,
        function(index) love.on_enemy_player_collision(index) end,
        spawn_rate_for("enemy", active_storm, suppress_spawns, true)
    )

    ZigzagEnemy.update(dt, is_game_over, Player,
        function(index) love.on_zigzag_enemy_player_collision(index) end,
        spawn_rate_for("zigzag", active_storm, suppress_spawns, zigzag_unlocked)
    )

    Mine.update(dt, is_game_over, Player,
        function(index) love.on_mine_player_collision(index) end,
        spawn_rate_for("mine", active_storm, suppress_spawns, mine_unlocked)
    )

    Orb.update(dt, is_game_over, Player,
        function(index) love.on_orb_player_collision(index) end,
        spawn_rate_for("orb", active_storm, suppress_spawns, true)
    )

    VoidOrb.update(dt, is_game_over, Player,
        function(index) love.on_void_orb_player_collision(index) end,
        function(index) love.on_void_orb_miss(index) end,
        spawn_rate_for("void_orb", active_storm, suppress_spawns, void_orb_unlocked)
    )

    Boss.update(dt, is_game_over, Player,
        function() love.on_boss_player_collision() end,
        function(x, y, dir_x, dir_y, homing) Projectile.spawn(x, y, dir_x, dir_y, homing) end,
        function() love.on_boss_encounter_end() end,
        function(type_id)
            if type_id == "homing" then
                Projectile.clear_homing()
            end
        end,
        -- the bomber seeds the arena with real Mine hazards rather than
        -- having its own private bomb entity, so they telegraph, explode and
        -- damage through exactly the same path a wave-spawned mine does
        function(x, y) Mine.spawn_at(x, y) end
    )

    Projectile.update(dt, is_game_over, Player,
        function(index) love.on_projectile_player_collision(index) end
    )

    FXManager.update(dt)
    Background.update(dt)
end

function love.draw()
    Bloom.begin_scene()

    Background.draw()

    love.graphics.push()
    if shake_duration > 0 then
        local dx = love.math.random(-shake_magnitude, shake_magnitude)
        local dy = love.math.random(-shake_magnitude, shake_magnitude)
        love.graphics.translate(dx, dy)
    end

    FXManager.draw()

    if not GameState.is(GameState.MENU) then
        -- player drawn last so it's always visually on top of whatever it's
        -- overlapping, instead of getting hidden behind a hazard's shape
        Enemy.draw()
        ZigzagEnemy.draw()
        Mine.draw()
        Orb.draw()
        VoidOrb.draw()
        Boss.draw()
        Projectile.draw()
        Player.draw()
    end

    love.graphics.pop()

    Bloom.finish_scene()

    local storm_phase = nil
    if storm_timer > 0 then
        storm_phase = "active"
    elseif storm_telegraph_timer > 0 then
        storm_phase = "incoming"
    end

    -- Everything above rendered into Bloom's canvases, which are sized to the
    -- game's own 800x600 -- so the whole scene is drawn in game coordinates
    -- and is completely independent of how big the window happens to be.
    --
    -- From here we're drawing to the real window, so the transform goes on:
    -- the finished frame scales up to fit, letterboxed to keep 4:3. UI and
    -- Debug draw inside the same transform deliberately -- outside it they'd
    -- stay 800x600-sized and shrink into a corner of a large window instead
    -- of scaling with the game. Whatever the letterbox leaves over stays the
    -- window's black background, which reads as a frame rather than as part
    -- of the play area.
    Screen.push()

    HitEffect.draw(Bloom.final_canvas)

    UI.draw(GameState.current, score, Player.lives, collected_orb_amount, Difficulty.wave(), Boss.active,
        HighScore.value, current_card_choices, card_cursor,
        boss_incoming_timer > 0, card_select_elapsed, chosen_card_index,
        storm_type, storm_phase, menu_cursor, reset_confirm_timer > 0)

    Debug.draw(Player, Boss, unlock_stage, MAX_UNLOCK_STAGE, storm_type, storm_phase)

    Screen.pop()
end

-- fired by LOVE whenever the window is resized (including entering/leaving
-- fullscreen) -- nothing else needs to react, since game coordinates never
-- change, only the transform that maps them onto the window
function love.resize()
    Screen.update_scale()
end

local function apply_player_hit(hit_shake_duration, hit_shake_magnitude, death_shake_duration, death_shake_magnitude)
    local p_cx, p_cy = Player.center()

    local result = Player.take_damage(1, function()
        GameState.set(GameState.GAME_OVER)
        HighScore.try_save(score)

        FXManager.spawn("player_death", p_cx, p_cy, 60)

        love.hitstop(0.12)
        love.shake(death_shake_duration or 0.4, death_shake_magnitude or 12)
    end)

    if result == "dodged" then
        FXManager.spawn_ring(p_cx, p_cy, 1, 1, 1, 15, 55, 200)
        love.hitstop(0.03)
        love.shake(0.05, 2)
        return
    end

    if result == "shielded" then
        FXManager.spawn_ring(p_cx, p_cy, 0.25, 0.6, 1, 20, 70, 260)
        love.hitstop(0.05)
        love.shake(0.1, 4)
        return
    end

    if result == "revived" then
        FXManager.spawn_ring(p_cx, p_cy, 1, 0.85, 0.2, 25, 90, 280)
        FXManager.spawn("player_damage", p_cx, p_cy, 30)
        Player.flicker_timer = 0.6
        love.hitstop(0.15)
        love.shake(0.35, 14)
        return
    end

    HitEffect.trigger()

    if result == "dead" then
        return
    end

    Player.flicker_timer = 0.25

    FXManager.spawn("player_damage", p_cx, p_cy, 15)

    love.hitstop(0.06)
    love.shake(hit_shake_duration, hit_shake_magnitude)
end

-- every hazard's collision handler is the same three steps -- consume the
-- hazard, bail if the player is already dead, apply the hit -- differing only
-- in which module owns it and how hard the screen shakes. Building them from
-- one factory keeps them from drifting apart the way the hand-copied
-- void-orb-miss handler once did (it silently lost the player flicker and the
-- is_dead guard). `module` is nil for the boss, which has nothing to remove.
local function hazard_collision_handler(module, shake_duration, shake_magnitude)
    return function(index)
        if module then module.remove(index) end

        if Player.is_dead or GameState.is(GameState.GAME_OVER) then return end

        apply_player_hit(shake_duration, shake_magnitude)
    end
end

local HAZARD_SHAKE_DURATION = 0.15
local HAZARD_SHAKE_MAGNITUDE = 6
-- a boss touch and a mine detonation are both bigger events than a simple
-- hazard touch, so they share a heavier shake
local HEAVY_SHAKE_DURATION = 0.2
local HEAVY_SHAKE_MAGNITUDE = 8

love.on_enemy_player_collision = hazard_collision_handler(Enemy, HAZARD_SHAKE_DURATION, HAZARD_SHAKE_MAGNITUDE)
love.on_zigzag_enemy_player_collision = hazard_collision_handler(ZigzagEnemy, HAZARD_SHAKE_DURATION,
    HAZARD_SHAKE_MAGNITUDE)
love.on_projectile_player_collision = hazard_collision_handler(Projectile, HAZARD_SHAKE_DURATION, HAZARD_SHAKE_MAGNITUDE)
love.on_mine_player_collision = hazard_collision_handler(Mine, HEAVY_SHAKE_DURATION, HEAVY_SHAKE_MAGNITUDE)
love.on_boss_player_collision = hazard_collision_handler(nil, HEAVY_SHAKE_DURATION, HEAVY_SHAKE_MAGNITUDE)

trigger_card_select = function()
    -- defensive: clears any stale pending-freeze state regardless of
    -- whether this was reached via the post-boss delay or triggered
    -- directly (e.g. debug F2), so the two paths can't step on each other
    post_boss_pause_timer = 0
    pending_card_select = false

    local choices = Cards.roll_choices(CARD_CHOICE_COUNT)
    -- every card at max_stacks (only reachable after a very long run, or via
    -- debug F2 spam) -- skip the screen instead of opening it with nothing
    -- pickable, which would otherwise soft-lock CARD_SELECT with no escape
    if #choices == 0 then return end

    current_card_choices = choices
    card_cursor = 1
    chosen_card_index = nil
    card_confirm_timer = 0
    card_select_elapsed = 0
    love.pause()
    GameState.set(GameState.CARD_SELECT)
end

finish_card_select = function()
    current_card_choices = nil
    chosen_card_index = nil
    card_select_elapsed = 0
    love.resume()
    GameState.set(GameState.PLAYING)
end

function love.on_boss_encounter_end()
    love.increase_score(50 + Cards.get("boss_bonus_score_add", 0))
    unlock_stage = math.min(unlock_stage + 1, MAX_UNLOCK_STAGE)
    -- don't open the card screen immediately -- let post_boss_pause_timer
    -- (ticked in love.update) give the player a beat first
    post_boss_pause_timer = POST_BOSS_PAUSE_DURATION
    pending_card_select = true
end

function love.on_orb_player_collision(index)
    Orb.remove(index)

    love.increase_score(5 + Cards.get("orb_score_bonus", 0))
    love.increase_orb_count(1)
end

function love.on_void_orb_player_collision(index)
    VoidOrb.remove(index)
    love.increase_score(10 + Cards.get("void_orb_score_bonus", 0))
    love.shake(0.15, 4)
end

function love.on_void_orb_miss(index)
    VoidOrb.remove(index)

    if Cards.get("void_orb_miss_safe", false) then
        return
    end

    if Player.is_dead or GameState.is(GameState.GAME_OVER) then return end

    apply_player_hit(0.5, 15, 0.6, 20)
end

function love.increase_score(amount)
    local mult = Cards.get("score_mult", 1)
    if Player.lives == 1 then
        mult = mult * Cards.get("low_hp_score_mult", 1)
    end
    score = score + math.floor(amount * mult + 0.5)
end

function love.increase_orb_count(amount)
    collected_orb_amount = collected_orb_amount + amount

    if (collected_orb_amount % 5 == 0) then
        love.increase_score(Cards.get("orb_milestone_bonus", 0))

        local p_cx, p_cy = Player.center()

        -- at full HP the milestone grants a shield instead of a wasted heal
        if Player.lives >= Player.max_lives then
            if Player.give_shield() then
                FXManager.spawn_ring(p_cx, p_cy, 0.25, 0.6, 1, 12, 65, 180)
                love.shake(0.1, 2)
            end
        elseif Player.heal(1) then
            FXManager.spawn_ring(p_cx, p_cy, 0, 1, 0.85, 12, 65, 180)
            love.shake(0.1, 2)
        end
    end
end

function love.shake(duration, magnitude)
    shake_duration = duration
    shake_magnitude = magnitude * Cards.get("shake_mult", 1)
end

function love.hitstop(duration)
    hitstop_timer = duration * Cards.get("hitstop_mult", 1)
end

function love.pause()
    for _, module in ipairs(PAUSABLE_MODULES) do module.pause() end
end

function love.resume()
    for _, module in ipairs(PAUSABLE_MODULES) do module.resume() end
end

local function restart_game(target_state)
    -- restarting/quitting from a paused run abandons whatever score was in
    -- progress -- save it first so a good run isn't silently lost just for
    -- using this instead of dying normally (harmless no-op from the normal
    -- game-over path, which already saved the same score at death time)
    HighScore.try_save(score)
    -- also undoes love.pause(), which a paused-state restart/quit would
    -- otherwise leave stuck on every module (is_paused would never clear,
    -- silently freezing the "fresh" run); harmless when already resumed
    love.resume()

    score = 0
    collected_orb_amount = 0
    last_boss_wave = 0
    last_wave_seen = 1
    boss_encounter_index = 0
    current_card_choices = nil
    card_cursor = 1
    boss_incoming_timer = 0
    pending_boss_type = nil
    post_boss_pause_timer = 0
    pending_card_select = false
    card_confirm_timer = 0
    chosen_card_index = nil
    card_select_elapsed = 0
    last_storm_wave = 0
    storm_telegraph_timer = 0
    storm_timer = 0
    storm_type = nil
    last_storm_type = nil
    unlock_stage = 0

    for _, module in ipairs(RESETTABLE_MODULES) do module.reset() end

    GameState.set(target_state or GameState.PLAYING)
end

local function quit_to_menu()
    menu_cursor = 1
    reset_confirm_timer = 0
    restart_game(GameState.MENU)
end

local function choose_card(index)
    if not current_card_choices then return end
    if card_confirm_timer > 0 then return end -- a pick is already locked in
    local card = current_card_choices[index]
    if not card then return end

    Cards.choose(card.id, Player)
    -- hold on the card screen a beat, with this card visually confirmed,
    -- instead of snapping straight back into danger (finish_card_select
    -- actually resumes once card_confirm_timer runs out, in love.update)
    chosen_card_index = index
    card_confirm_timer = CARD_CONFIRM_DELAY
end

local function toggle_pause()
    if GameState.is(GameState.PLAYING) then
        love.pause()
        menu_cursor = 1
        GameState.set(GameState.PAUSED)
    elseif GameState.is(GameState.PAUSED) then
        love.resume()
        GameState.set(GameState.PLAYING)
    end
end

-- dispatch tables for the shared simple-menu widget (see src/ui.lua) --
-- indices match UI.MAIN_MENU_OPTIONS / UI.PAUSE_MENU_OPTIONS order
local function select_main_menu_option(index)
    if index == 1 then
        GameState.set(GameState.PLAYING)
    elseif index == MAIN_MENU_RESET_INDEX then
        if reset_confirm_timer > 0 then
            HighScore.reset()
            reset_confirm_timer = 0
        else
            reset_confirm_timer = RESET_CONFIRM_DELAY
        end
    elseif index == 3 then
        love.event.quit()
    end
end

local function select_pause_menu_option(index)
    if index == 1 then
        toggle_pause()
    elseif index == 2 then
        restart_game()
    elseif index == 3 then
        quit_to_menu()
    end
end

-- wrapping cursor step, shared by every cursor-driven screen across both the
-- keyboard and gamepad input paths so the wraparound arithmetic lives in one
-- place instead of being spelled out at each of them
local function step_cursor(cursor, delta, count)
    return (cursor - 1 + delta) % count + 1
end

local function move_main_menu_cursor(delta)
    menu_cursor = step_cursor(menu_cursor, delta, #UI.MAIN_MENU_OPTIONS)
    -- navigating off "Reset High Score" disarms it
    if menu_cursor ~= MAIN_MENU_RESET_INDEX then reset_confirm_timer = 0 end
end

local function move_pause_menu_cursor(delta)
    menu_cursor = step_cursor(menu_cursor, delta, #UI.PAUSE_MENU_OPTIONS)
end

local function move_card_cursor(delta)
    card_cursor = step_cursor(card_cursor, delta, CARD_CHOICE_COUNT)
end

function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
        return
    end

    if key == "f11" then
        Screen.toggle_fullscreen()
        return
    end

    if key == "f1" then
        Debug.toggle()
        return
    end

    if Debug.enabled and GameState.is(GameState.PLAYING) then
        if key == "f2" then
            trigger_card_select()
            return
        elseif key == "f3" then
            Boss.spawn(Debug.cycle_boss(Boss.SEQUENCE))
            return
        elseif key == "f4" then
            Difficulty.skip_wave()
            return
        elseif key == "f5" then
            Debug.toggle_god_mode()
            return
        end

        -- 1-9 spawn a *specific* boss straight away. Cycling with F3 alone
        -- meant reaching the 9th type took nine presses (each replacing the
        -- last mid-encounter), which made testing any one of them tedious.
        -- Safe to take these keys here: this branch only runs while PLAYING,
        -- and the digits are otherwise only used on the card-select screen.
        local boss_type = Debug.select_boss(tonumber(key), Boss.SEQUENCE)
        if boss_type then
            Boss.spawn(boss_type)
            return
        end
    end

    if GameState.is(GameState.MENU) then
        if key == "up" or key == "w" then
            move_main_menu_cursor(-1)
        elseif key == "down" or key == "s" then
            move_main_menu_cursor(1)
        elseif key == "space" or key == "return" then
            select_main_menu_option(menu_cursor)
        end
        return
    end

    if GameState.is(GameState.CARD_SELECT) then
        if key == "1" then
            choose_card(1)
        elseif key == "2" then
            choose_card(2)
        elseif key == "3" then
            choose_card(3)
        elseif key == "a" or key == "left" then
            move_card_cursor(-1)
        elseif key == "d" or key == "right" then
            move_card_cursor(1)
        elseif key == "return" or key == "space" then
            choose_card(card_cursor)
        end
        return
    end

    if GameState.is(GameState.PAUSED) then
        if key == "up" or key == "w" then
            move_pause_menu_cursor(-1)
        elseif key == "down" or key == "s" then
            move_pause_menu_cursor(1)
        elseif key == "return" or key == "space" then
            select_pause_menu_option(menu_cursor)
        end
    end

    if key == "r" and (GameState.is(GameState.GAME_OVER) or GameState.is(GameState.PAUSED)) then
        restart_game()
    end

    if key == "m" and GameState.is(GameState.PAUSED) then
        quit_to_menu()
    end

    if key == "p" then
        toggle_pause()
    end

    Player.keypressed(key)
end

function love.gamepadpressed(joystick, button)
    if GameState.is(GameState.MENU) then
        if button == "dpup" then
            move_main_menu_cursor(-1)
        elseif button == "dpdown" then
            move_main_menu_cursor(1)
        elseif button == "a" or button == "start" then
            select_main_menu_option(menu_cursor)
        end
        return
    end

    if GameState.is(GameState.CARD_SELECT) then
        if button == "dpleft" then
            move_card_cursor(-1)
        elseif button == "dpright" then
            move_card_cursor(1)
        elseif button == "a" then
            choose_card(card_cursor)
        end
        return
    end

    if GameState.is(GameState.PAUSED) then
        if button == "dpup" then
            move_pause_menu_cursor(-1)
        elseif button == "dpdown" then
            move_pause_menu_cursor(1)
        elseif button == "a" then
            select_pause_menu_option(menu_cursor)
        elseif button == "b" then
            quit_to_menu()
        end
    end

    if button == "a" and GameState.is(GameState.GAME_OVER) then
        restart_game()
    end

    if button == "start" then
        toggle_pause()
    end

    Player.gamepadpressed(button)
end

-- shared point-in-rects hit-test, used for card select and the two simple
-- menus -- returns the index of the first rect containing (x, y), or nil
local function hit_index(x, y, rects)
    for i, rect in ipairs(rects) do
        if x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h then
            return i
        end
    end
    return nil
end

function love.mousepressed(x, y, button)
    if button ~= 1 then return end

    -- LOVE reports window coordinates; every layout below (UI.card_layout,
    -- the two menu layouts) is expressed in game coordinates. Converting once
    -- here means those layouts stay the single source of truth for both
    -- drawing and hit-testing exactly as before, at any window size.
    x, y = Screen.to_game(x, y)

    if GameState.is(GameState.CARD_SELECT) then
        local index = hit_index(x, y, UI.card_layout())
        if index then choose_card(index) end
    elseif GameState.is(GameState.MENU) then
        local index = hit_index(x, y, UI.main_menu_layout())
        if index then select_main_menu_option(index) end
    elseif GameState.is(GameState.PAUSED) then
        local index = hit_index(x, y, UI.pause_menu_layout())
        if index then select_pause_menu_option(index) end
    end
end
