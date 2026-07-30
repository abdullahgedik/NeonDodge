-- main.lua -- the conductor.
--
-- It owns no entity behavior: it holds the run's state, decides when events
-- happen, wires the modules together, and routes input. Everything else lives
-- in src/. See README.md for the map and for how one frame flows.
local Player                    = require("src/player")
local Enemy                     = require("src/enemy")
local ZigzagEnemy               = require("src/zigzag_enemy")
local Orb                       = require("src/orb")
local VoidOrb                   = require("src/void_orb")
local Mine                      = require("src/mine")
local UI                        = require("src/ui")
local FXManager                 = require("src/fx_manager")
local Background                = require("src/background")
local GameState                 = require("src/game_state")
local Difficulty                = require("src/difficulty")
local Bloom                     = require("src/bloom")
local Boss                      = require("src/boss")
local Projectile                = require("src/projectile")
local HitEffect                 = require("src/hit_effect")
local HighScore                 = require("src/high_score")
local BossRushScore             = require("src/boss_rush_score")
local Cards                     = require("src/cards")
local Debug                     = require("src/debug")
local Screen                    = require("src/screen")
local Storms                    = require("src/storms")
local Unlocks                   = require("src/unlocks")

-- This file's own helpers and event handlers live on `Game`, NOT on `love`.
-- The distinction matters when reading the file: everything named `love.xxx`
-- here is a callback LÖVE itself calls for us (there are exactly seven --
-- load, update, draw, resize, keypressed, gamepadpressed, mousepressed), and
-- everything named `Game.xxx` is ours. These used to sit on `love` too, which
-- made `Game.shake(...)` look like an engine feature you could go read the
-- LÖVE docs for; it isn't, and there was no way to tell from the name.
--
-- A table (rather than plain locals) because Lua resolves `local` by where it
-- appears in the source: love.update sits near the top of this file but calls
-- handlers defined near the bottom, and a table field is looked up when the
-- call actually runs, so the ordering stops mattering.
local Game                      = {}

-- ===========================================================================
-- Module lifecycle lists
-- ===========================================================================
-- Three deliberately different lists, each covering one lifecycle step. They
-- overlap heavily but are NOT interchangeable -- see each note.

-- everything with a .load(), in initialization order. Screen goes first: it
-- resolves the window -> game transform every other module's dimensions are
-- expressed against.
local LOADABLE_MODULES          = {
    Screen, Player, Enemy, ZigzagEnemy, Orb, VoidOrb, Mine, UI, FXManager, Background,
    GameState, Difficulty, Bloom, Boss, Projectile, HitEffect, HighScore, BossRushScore, Cards, Debug
}

-- every module whose simulation must halt while the game is paused (pause
-- screen, card select). Deliberately not every module: Background/FXManager
-- keep animating, and Bloom/HitEffect/UI/HighScore have no such state.
local PAUSABLE_MODULES          = {
    Player, Enemy, ZigzagEnemy, Mine, Orb, VoidOrb, Difficulty, Boss, Projectile, Cards
}

-- everything a fresh run wipes. Excludes UI/Bloom (no run state), HighScore
-- (persists by design -- that's the whole point of it) and GameState (the
-- caller sets the target state itself); includes Background/FXManager, which
-- the pause list deliberately skips.
local RESETTABLE_MODULES        = {
    Player, Enemy, ZigzagEnemy, Mine, Orb, VoidOrb, FXManager, Background,
    Difficulty, Boss, Projectile, HitEffect, Cards
}

-- ===========================================================================
-- Tunables -- constants, never written at runtime
-- ===========================================================================

-- a boss every Nth wave; a storm every Nth wave that isn't a boss wave. With
-- BOSS_WAVE_INTERVAL a multiple of STORM_WAVE_INTERVAL the two never collide
-- -- two storms then a boss every 6-wave block (waves 2, 4, 6-is-boss-instead,
-- 8, 10, 12-is-boss-instead, ...). Storms alone were sped up to twice their
-- old frequency without touching boss cadence, since bosses already run close
-- to or longer than a full wave and needed the recovery room more than storms did.
local BOSS_WAVE_INTERVAL        = 6
local STORM_WAVE_INTERVAL       = 2
local STORM_TELEGRAPH_DELAY     = 1.2
local STORM_DURATION            = 10

-- transition pacing: three deliberate breathers so the game doesn't slam
-- straight from normal play into a boss, or from a boss into the reward
-- screen, or out of the reward screen back into danger
local BOSS_INCOMING_DELAY       = 1.8 -- telegraph before a boss actually spawns
local POST_BOSS_PAUSE_DURATION  = 1.0 -- freeze-beat after a boss dies, before the card screen opens
local CARD_CONFIRM_DELAY        = 0.5 -- holds the card screen after a pick so it reads as confirmed

local CARD_CHOICE_COUNT         = 3

-- score used to be purely cosmetic outside of the high-score comparison --
-- bosses were the only source of cards, and with encounters now longer and
-- spaced every 6 waves, that's a long stretch of a run with nothing to show
-- for good play. A flat score milestone grants a bonus card on top of the
-- boss ones; it stays flat rather than scaling up, so score-boosting cards
-- (Wave Bonus, Orb Magnet, score multipliers) naturally make these come
-- faster as a run snowballs, instead of being tuned against a moving target.
local SCORE_PER_CARD            = 200

-- "Reset High Score" arms instead of firing immediately -- a second confirm
-- within this many seconds actually resets it, so a misclick can't silently
-- erase the record.
local RESET_CONFIRM_DELAY       = 3

-- indices into UI.MAIN_MENU_OPTIONS / UI.PAUSE_MENU_OPTIONS. Named because the
-- dispatch functions below branch on them and `index == 3` on its own tells you
-- nothing about which button that is.
local MAIN_MENU_START_INDEX     = 1
local MAIN_MENU_BOSS_RUSH_INDEX = 2
local MAIN_MENU_RESET_INDEX     = 3
local MAIN_MENU_QUIT_INDEX      = 4
local PAUSE_MENU_RESUME_INDEX   = 1
local PAUSE_MENU_RESTART_INDEX  = 2
local PAUSE_MENU_QUIT_INDEX     = 3

-- Boss Rush: a fixed gauntlet through Boss.SEQUENCE, no cards, a heal (or
-- shield if already full) between fights is the only thing carrying over.
-- Clearing a full lap of all ten types wraps back to the start and bumps
-- run.rush_difficulty_mult by this much -- see Boss.spawn's optional second
-- argument and how Movement.charge/.bouncer and the engine's fire-interval
-- check read it.
local RUSH_DIFFICULTY_STEP      = 0.15

-- ===========================================================================
-- Run state
-- ===========================================================================
-- Everything that belongs to the current run lives in this one table, and
-- reset_run_state() is the only thing that clears it. That used to be ~20 loose
-- locals plus a hand-written list of 20 assignments inside restart_game, which
-- is the exact shape of bug this project has already hit twice (a variable
-- added to the top and forgotten in the reset). Now adding a field to `run`
-- automatically means it gets wiped, because there's one list, not two.
--
-- Deliberately NOT in here: menu_cursor and reset_confirm_timer, which belong
-- to menu navigation rather than a run and are reset when a menu is entered.
local run                       = {}

local function reset_run_state()
    run.score = 0
    run.collected_orbs = 0

    -- which ruleset is active. "survival" is the default every reset lands
    -- on; start_boss_rush() flips it after resetting (see below). Not a
    -- GameState -- it's a different axis (which rules apply within PLAYING),
    -- not a screen.
    run.mode = "survival"
    run.rush_boss_index = 1
    run.rush_lap = 1
    run.rush_cleared = 0
    run.rush_difficulty_mult = 1
    run.pending_next_rush_boss = false

    -- screen shake and hit-stop. Included so restarting mid-shake or
    -- mid-hitstop doesn't leak either into the fresh run.
    run.shake_duration = 0
    run.shake_magnitude = 0
    run.hitstop_timer = 0

    -- wave / boss bookkeeping
    run.last_wave_seen = 1
    run.last_boss_wave = 0
    run.boss_encounter_index = 0

    -- boss transition timers
    run.boss_incoming_timer = 0
    run.pending_boss_type = nil
    run.post_boss_pause_timer = 0
    run.pending_card_select = false

    -- score-milestone bonus cards (see Game.increase_score)
    run.next_score_card = SCORE_PER_CARD
    run.pending_score_card = false

    -- card select
    run.card_choices = nil
    run.card_cursor = 1
    run.chosen_card = nil
    run.card_elapsed = 0
    run.card_confirm_timer = 0

    -- storms. storm_type is held from the telegraph starting through the storm
    -- ending, because the banner needs it during the telegraph too.
    run.last_storm_wave = 0
    run.storm_telegraph_timer = 0
    run.storm_timer = 0
    run.storm_type = nil
    run.last_storm_type = nil

    -- how much of the hazard roster is live (see src/unlocks.lua)
    run.unlock_stage = 0
end

reset_run_state()

-- menu navigation state, which outlives any single run
local menu_cursor         = 1
local reset_confirm_timer = 0

-- forward-declared: the update helpers below need to call these, but they're
-- defined further down as plain local functions
local trigger_card_select
local finish_card_select

-- ===========================================================================
-- Spawn rates
-- ===========================================================================

-- Resolves one hazard's spawn period for this frame. math.huge means "never
-- spawns", and covers all three suppression cases: a boss encounter is on
-- screen, this hazard isn't unlocked yet, or a storm is running that this
-- hazard isn't part of.
local function spawn_rate_for(kind, storm, suppressed, unlock_stage)
    if suppressed or not Unlocks.is_unlocked(unlock_stage, kind) then return math.huge end

    if storm then
        local mult = storm.rates[kind]
        if not mult then return math.huge end
        return Difficulty.spawn_rate(kind) * mult
    end

    return Difficulty.spawn_rate(kind)
end

-- ===========================================================================
-- love.load
-- ===========================================================================

function love.load()
    for _, module in ipairs(LOADABLE_MODULES) do module.load() end
end

-- ===========================================================================
-- love.update, split into the steps it actually performs
-- ===========================================================================

-- The screens that replace normal play. Returns true when the frame is fully
-- handled and nothing else should run.
local function update_blocking_screens(dt)
    if GameState.is(GameState.MENU) then
        Background.update(dt)
        if reset_confirm_timer > 0 then
            reset_confirm_timer = reset_confirm_timer - dt
        end
        return true
    end

    if GameState.is(GameState.PAUSED) then return true end

    if GameState.is(GameState.CARD_SELECT) then
        run.card_elapsed = run.card_elapsed + dt

        if run.card_confirm_timer > 0 then
            run.card_confirm_timer = run.card_confirm_timer - dt
            if run.card_confirm_timer <= 0 then
                finish_card_select()
            end
        end

        return true
    end

    return false
end

-- The two ways the world holds still: the brief hit-stop on damage, and the
-- longer freeze-frame beat after a boss dies. Both work by returning early
-- before anything simulates -- that's the whole trick. Returns true if frozen.
local function update_freeze_timers(dt)
    if run.hitstop_timer > 0 then
        run.hitstop_timer = run.hitstop_timer - dt
        return true
    end

    -- ...and once the beat is over, this is what actually opens the card
    -- screen (survival) or arms the next fight's telegraph (Boss Rush) --
    -- mutually exclusive, only one of the two pending flags is ever set
    if run.post_boss_pause_timer > 0 then
        run.post_boss_pause_timer = run.post_boss_pause_timer - dt
        if run.post_boss_pause_timer <= 0 then
            if run.pending_card_select then
                run.pending_card_select = false
                trigger_card_select()
            elseif run.pending_next_rush_boss then
                run.pending_next_rush_boss = false
                run.boss_incoming_timer = BOSS_INCOMING_DELAY
            end
        end
        return true
    end

    return false
end

-- Schedules the boss telegraph, then spawns the boss once it elapses. During
-- the telegraph existing hazards keep falling but no new ones spawn (see
-- suppress_spawns in update_entities), so it reads as things calming down
-- rather than a hard stop.
-- The wave-triggered half is survival-only -- Boss Rush drives
-- run.boss_incoming_timer/run.pending_boss_type itself (see Game.rush_advance
-- and start_boss_rush). The countdown-then-spawn half underneath is shared:
-- it doesn't care why the timer got armed, so both modes reuse it as-is.
local function update_boss_schedule(dt, wave, is_game_over)
    if run.mode ~= "boss_rush" and not is_game_over and not Boss.active and run.boss_incoming_timer <= 0 then
        if wave > run.last_boss_wave and wave % BOSS_WAVE_INTERVAL == 0 then
            run.last_boss_wave = wave
            run.pending_boss_type = Boss.SEQUENCE[(run.boss_encounter_index % #Boss.SEQUENCE) + 1]
            run.boss_encounter_index = run.boss_encounter_index + 1
            run.boss_incoming_timer = BOSS_INCOMING_DELAY
        end
    end

    if run.boss_incoming_timer > 0 then
        run.boss_incoming_timer = run.boss_incoming_timer - dt
        if run.boss_incoming_timer <= 0 then
            -- rush_difficulty_mult stays 1 outside Boss Rush, so this is a
            -- no-op for survival
            Boss.spawn(run.pending_boss_type, run.rush_difficulty_mult)
            run.pending_boss_type = nil
        end
    end
end

-- Same shape as the boss schedule: telegraph, then the event itself. A storm
-- can never land on a boss wave (the modulo guard), and never overlaps a boss
-- encounter even a debug-forced one (the Boss.active guard).
local function update_storm_schedule(dt, wave, is_game_over)
    -- no storms in Boss Rush -- it's a pure boss gauntlet, nothing else on screen
    if run.mode == "boss_rush" then return end

    if not is_game_over and not Boss.active and run.boss_incoming_timer <= 0
        and run.storm_timer <= 0 and run.storm_telegraph_timer <= 0 then
        if wave > run.last_storm_wave and wave % STORM_WAVE_INTERVAL == 0
            and wave % BOSS_WAVE_INTERVAL ~= 0 then
            run.last_storm_wave = wave
            -- picked at telegraph time (not when the storm itself starts) so
            -- the warning banner can name which storm is coming
            run.storm_type = Storms.pick(run.unlock_stage, run.last_storm_type)
            run.last_storm_type = run.storm_type
            run.storm_telegraph_timer = STORM_TELEGRAPH_DELAY
        end
    end

    if run.storm_telegraph_timer > 0 then
        run.storm_telegraph_timer = run.storm_telegraph_timer - dt
        if run.storm_telegraph_timer <= 0 then
            run.storm_timer = STORM_DURATION
        end
    elseif run.storm_timer > 0 then
        run.storm_timer = run.storm_timer - dt
        if run.storm_timer <= 0 then
            run.storm_timer = 0
            run.storm_type = nil
            -- surviving the storm is what unlocks the next hazard
            run.unlock_stage = Unlocks.advance(run.unlock_stage)
        end
    end
end

-- Opens the score-milestone card screen (see Game.increase_score) once it's
-- actually safe to: no boss active or about to be, no boss reward already
-- queued, no storm telegraphing or running. Returns true the frame it
-- actually fires, so the caller can bail out of the rest of love.update the
-- same way update_freeze_timers already does when it opens the boss's card
-- screen -- GameState just changed out from under the rest of the frame.
local function update_score_card_trigger(is_game_over)
    -- Boss Rush has no cards at all -- run.score never moves there, so
    -- pending_score_card should never be true, but this stays explicit rather
    -- than relying on that
    if is_game_over or run.mode == "boss_rush" or not run.pending_score_card then return false end
    if Boss.active or run.boss_incoming_timer > 0 or run.pending_card_select then return false end
    if run.storm_telegraph_timer > 0 or run.storm_timer > 0 then return false end

    run.pending_score_card = false
    trigger_card_select()
    return true
end

local function update_entities(dt, is_game_over)
    -- Boss Rush never spawns ordinary hazards -- it's boss encounters back
    -- to back with nothing else on screen
    local suppress = run.mode == "boss_rush" or Boss.active or run.boss_incoming_timer > 0
    -- only applies once the storm is actually running -- during its telegraph
    -- storm_type is already picked (for the banner) but spawn rates stay normal
    local storm = (run.storm_timer > 0) and run.storm_type or nil
    local stage = run.unlock_stage

    Enemy.update(dt, is_game_over, Player, Game.on_enemy_player_collision,
        spawn_rate_for("enemy", storm, suppress, stage))

    ZigzagEnemy.update(dt, is_game_over, Player, Game.on_zigzag_enemy_player_collision,
        spawn_rate_for("zigzag", storm, suppress, stage))

    Mine.update(dt, is_game_over, Player, Game.on_mine_player_collision,
        spawn_rate_for("mine", storm, suppress, stage))

    Orb.update(dt, is_game_over, Player, Game.on_orb_player_collision,
        spawn_rate_for("orb", storm, suppress, stage))

    VoidOrb.update(dt, is_game_over, Player,
        Game.on_void_orb_player_collision, Game.on_void_orb_miss,
        spawn_rate_for("void_orb", storm, suppress, stage))

    Boss.update(dt, is_game_over, Player, {
        on_player_hit    = Game.on_boss_player_collision,
        spawn_projectile = Projectile.spawn,
        on_encounter_end = Game.on_boss_encounter_end,
        on_type_exit     = function(type_id)
            if type_id == "homing" then
                Projectile.clear_homing()
            end
        end,
        -- the bomber seeds the arena with real Mine hazards rather than having
        -- its own private bomb entity, so they telegraph, explode and damage
        -- through exactly the same path a wave-spawned mine does
        spawn_mine       = Mine.spawn_at,
    })

    Projectile.update(dt, is_game_over, Player, Game.on_projectile_player_collision)
end

function love.update(dt)
    if update_blocking_screens(dt) then return end
    if update_freeze_timers(dt) then return end

    if run.shake_duration > 0 then
        run.shake_duration = run.shake_duration - dt
    else
        run.shake_magnitude = 0
    end

    HitEffect.update(dt, Player.lives == 1 and not Player.is_dead)

    local is_game_over = GameState.is(GameState.GAME_OVER)

    Cards.update(dt, is_game_over, Player)
    Difficulty.update(dt, is_game_over)

    -- resolved once and reused by all three checks below, which each used to
    -- call Difficulty.wave() again for the same answer
    local wave = Difficulty.wave()

    -- wave/score are a survival-only concept; Boss Rush tracks bosses
    -- cleared instead (see Game.rush_advance)
    if not is_game_over and run.mode ~= "boss_rush" and wave > run.last_wave_seen then
        run.last_wave_seen = wave
        Game.increase_score(Cards.get("wave_bonus_score", 0))
    end

    update_boss_schedule(dt, wave, is_game_over)
    update_storm_schedule(dt, wave, is_game_over)

    if update_score_card_trigger(is_game_over) then return end

    -- the boss encounter (if any) decides how much of the screen is legal this
    -- frame; with none active this resolves to the full screen
    Player.min_x, Player.min_y, Player.max_x, Player.max_y = Boss.get_player_bounds()
    Player.update(dt, is_game_over)

    update_entities(dt, is_game_over)

    FXManager.update(dt)
    Background.update(dt)
end

-- ===========================================================================
-- love.draw
-- ===========================================================================

-- "incoming" while the telegraph runs, "active" once it does, nil otherwise
local function current_storm_phase()
    if run.storm_timer > 0 then return "active" end
    if run.storm_telegraph_timer > 0 then return "incoming" end
    return nil
end

local function draw_scene()
    Background.draw()

    love.graphics.push()
    if run.shake_duration > 0 then
        local dx = love.math.random(-run.shake_magnitude, run.shake_magnitude)
        local dy = love.math.random(-run.shake_magnitude, run.shake_magnitude)
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
end

function love.draw()
    Bloom.begin_scene()

    -- The scene is described in game coordinates but rasterizes at the window's
    -- true resolution: the transform goes on *before* anything is drawn, so
    -- every shape is generated at full size rather than drawn small and
    -- stretched afterwards. Nothing here is a sprite -- it's all rectangles,
    -- circles, polygons and lines -- so this costs nothing and is the
    -- difference between crisp and blurry at any window size.
    Screen.push()
    draw_scene()
    Screen.pop()

    Bloom.finish_scene()

    -- Bloom's final canvas already matches the window, so this is a straight
    -- 1:1 blit with no resampling -- deliberately outside the transform.
    HitEffect.draw(Bloom.final_canvas)

    -- The HUD and overlays go back into game coordinates so all their layout
    -- math stays in the 960x540 space the click hit-testing uses. Their shapes
    -- are vector and their fonts are built at the scaled pixel size (see
    -- Screen.new_font), so this stays crisp too.
    Screen.push()

    local storm_phase = current_storm_phase()

    UI.draw({
        state         = GameState.current,
        mode          = run.mode,
        score         = run.score,
        lives         = Player.lives,
        orbs          = run.collected_orbs,
        wave          = Difficulty.wave(),
        high_score    = HighScore.value,
        rush_cleared  = run.rush_cleared,
        rush_lap      = run.rush_lap,
        rush_best     = BossRushScore.value,

        boss_active   = Boss.active,
        boss_incoming = run.boss_incoming_timer > 0,
        storm_type    = run.storm_type,
        storm_phase   = storm_phase,

        cards         = run.card_choices,
        card_cursor   = run.card_cursor,
        card_elapsed  = run.card_elapsed,
        chosen_card   = run.chosen_card,

        menu_cursor   = menu_cursor,
        reset_armed   = reset_confirm_timer > 0,
    })

    Debug.draw({
        player               = Player,
        boss                 = Boss,
        unlock_stage         = run.unlock_stage,
        max_unlock_stage     = Unlocks.MAX,
        storm_type           = run.storm_type,
        storm_phase          = storm_phase,
        -- lets the overlay show which boss the *run* will spawn next, which is
        -- a different counter from the one F3 advances
        boss_encounter_index = run.boss_encounter_index,
        score                = run.score,
        next_score_card      = run.next_score_card,
        mode                 = run.mode,
        rush_cleared         = run.rush_cleared,
        rush_lap             = run.rush_lap,
        rush_difficulty_mult = run.rush_difficulty_mult,
    })

    Screen.pop()
end

-- fired by LOVE whenever the window is resized (including entering/leaving
-- fullscreen). Game coordinates never change -- only how many real pixels they
-- map onto, which is why the three things that rasterize per-pixel (Bloom's
-- scene canvases, and the two fonts) have to be rebuilt, and nothing else in
-- the project has to care at all.
function love.resize()
    Screen.update_scale()
    Bloom.resize()
    UI.refresh_fonts()
    Debug.refresh_font()
end

-- ===========================================================================
-- Taking damage
-- ===========================================================================

local function apply_player_hit(hit_shake_duration, hit_shake_magnitude, death_shake_duration, death_shake_magnitude)
    local p_cx, p_cy = Player.center()

    local result = Player.take_damage(1, function()
        GameState.set(GameState.GAME_OVER)
        HighScore.try_save(run.score)
        -- harmless no-op outside Boss Rush: run.rush_cleared is always 0 in
        -- survival, and 0 never beats an existing best
        BossRushScore.try_save(run.rush_cleared)

        FXManager.spawn("player_death", p_cx, p_cy, 60)

        Game.hitstop(0.12)
        Game.shake(death_shake_duration or 0.4, death_shake_magnitude or 12)
    end)

    if result == "dodged" then
        FXManager.spawn_ring(p_cx, p_cy, 1, 1, 1, 15, 55, 200)
        Game.hitstop(0.03)
        Game.shake(0.05, 2)
        return
    end

    if result == "shielded" then
        FXManager.spawn_ring(p_cx, p_cy, 0.25, 0.6, 1, 20, 70, 260)
        Game.hitstop(0.05)
        Game.shake(0.1, 4)
        return
    end

    if result == "revived" then
        FXManager.spawn_ring(p_cx, p_cy, 1, 0.85, 0.2, 25, 90, 280)
        FXManager.spawn("player_damage", p_cx, p_cy, 30)
        Player.flicker_timer = 0.6
        Game.hitstop(0.15)
        Game.shake(0.35, 14)
        return
    end

    HitEffect.trigger()

    if result == "dead" then
        return
    end

    Player.flicker_timer = 0.25

    FXManager.spawn("player_damage", p_cx, p_cy, 15)

    Game.hitstop(0.06)
    Game.shake(hit_shake_duration, hit_shake_magnitude)
end

-- Every hazard's collision handler is the same three steps -- consume the
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

local HAZARD_SHAKE_DURATION           = 0.15
local HAZARD_SHAKE_MAGNITUDE          = 6
-- a boss touch and a mine detonation are both bigger events than a simple
-- hazard touch, so they share a heavier shake
local HEAVY_SHAKE_DURATION            = 0.2
local HEAVY_SHAKE_MAGNITUDE           = 8

Game.on_enemy_player_collision        = hazard_collision_handler(Enemy, HAZARD_SHAKE_DURATION,
    HAZARD_SHAKE_MAGNITUDE)
Game.on_zigzag_enemy_player_collision = hazard_collision_handler(ZigzagEnemy, HAZARD_SHAKE_DURATION,
    HAZARD_SHAKE_MAGNITUDE)
Game.on_projectile_player_collision   = hazard_collision_handler(Projectile, HAZARD_SHAKE_DURATION,
    HAZARD_SHAKE_MAGNITUDE)
Game.on_mine_player_collision         = hazard_collision_handler(Mine, HEAVY_SHAKE_DURATION, HEAVY_SHAKE_MAGNITUDE)
Game.on_boss_player_collision         = hazard_collision_handler(nil, HEAVY_SHAKE_DURATION, HEAVY_SHAKE_MAGNITUDE)

-- ===========================================================================
-- Pickups and scoring
-- ===========================================================================

function Game.on_orb_player_collision(index)
    Orb.remove(index)

    Game.increase_score(5 + Cards.get("orb_score_bonus", 0))
    Game.increase_orb_count(1)
end

function Game.on_void_orb_player_collision(index)
    VoidOrb.remove(index)
    Game.increase_score(10 + Cards.get("void_orb_score_bonus", 0))
    Game.shake(0.15, 4)
end

function Game.on_void_orb_miss(index)
    VoidOrb.remove(index)

    if Cards.get("void_orb_miss_safe", false) then
        return
    end

    if Player.is_dead or GameState.is(GameState.GAME_OVER) then return end

    apply_player_hit(0.5, 15, 0.6, 20)
end

function Game.increase_score(amount)
    local mult = Cards.get("score_mult", 1)
    if Player.lives == 1 then
        mult = mult * Cards.get("low_hp_score_mult", 1)
    end
    -- rounded: a fractional multiplier (Glass Cannon's 1.5x) would otherwise
    -- leave the score a float
    run.score = run.score + math.floor(amount * mult + 0.5)

    -- deferred (run.pending_score_card) rather than opening the card screen
    -- right here -- this can run mid-boss-fight (a void orb caught during an
    -- encounter) or mid-storm, neither of which is a safe moment to pause
    -- into a card pick. A `while` rather than an `if` so one big score jump
    -- (a boss kill, a multiplier) can't skip past a threshold without ever
    -- actually crossing it.
    while run.score >= run.next_score_card do
        run.next_score_card = run.next_score_card + SCORE_PER_CARD
        run.pending_score_card = true
    end
end

local ORB_MILESTONE = 5

function Game.increase_orb_count(amount)
    run.collected_orbs = run.collected_orbs + amount

    if run.collected_orbs % ORB_MILESTONE ~= 0 then return end

    Game.increase_score(Cards.get("orb_milestone_bonus", 0))

    local p_cx, p_cy = Player.center()

    -- at full HP the milestone grants a shield instead of a wasted heal
    if Player.lives >= Player.max_lives then
        if Player.give_shield() then
            FXManager.spawn_ring(p_cx, p_cy, 0.25, 0.6, 1, 12, 65, 180)
            Game.shake(0.1, 2)
        end
    elseif Player.heal(1) then
        FXManager.spawn_ring(p_cx, p_cy, 0, 1, 0.85, 12, 65, 180)
        Game.shake(0.1, 2)
    end
end

-- ===========================================================================
-- Juice
-- ===========================================================================

function Game.shake(duration, magnitude)
    run.shake_duration = duration
    run.shake_magnitude = magnitude * Cards.get("shake_mult", 1)
end

function Game.hitstop(duration)
    run.hitstop_timer = duration * Cards.get("hitstop_mult", 1)
end

-- ===========================================================================
-- Lifecycle: pause, restart, card select
-- ===========================================================================

function Game.pause()
    for _, module in ipairs(PAUSABLE_MODULES) do module.pause() end
end

function Game.resume()
    for _, module in ipairs(PAUSABLE_MODULES) do module.resume() end
end

local function restart_game(target_state)
    -- restarting/quitting from a paused run abandons whatever score was in
    -- progress -- save it first so a good run isn't silently lost just for
    -- using this instead of dying normally (harmless no-op from the normal
    -- game-over path, which already saved the same score at death time)
    HighScore.try_save(run.score)
    BossRushScore.try_save(run.rush_cleared)
    -- also undoes Game.pause(), which a paused-state restart/quit would
    -- otherwise leave stuck on every module (is_paused would never clear,
    -- silently freezing the "fresh" run); harmless when already resumed
    Game.resume()

    local was_boss_rush = run.mode == "boss_rush"

    reset_run_state()
    for _, module in ipairs(RESETTABLE_MODULES) do module.reset() end

    GameState.set(target_state or GameState.PLAYING)

    -- restarting mid-Boss-Rush starts another Boss Rush attempt, not a
    -- silent drop back to survival -- but only when actually resuming play;
    -- quit_to_menu wants a genuinely clean slate, which reset_run_state's
    -- "survival" default above already gives it
    if was_boss_rush and (target_state == nil or target_state == GameState.PLAYING) then
        run.mode = "boss_rush"
        run.pending_boss_type = Boss.SEQUENCE[run.rush_boss_index]
        run.boss_incoming_timer = BOSS_INCOMING_DELAY
    end
end

-- Entry point for the main menu's "Boss Rush" option. Deliberately not a call
-- to restart_game() -- the menu is only ever reached from an already-reset
-- state (either the initial load or quit_to_menu, both of which call
-- reset_run_state()), so this just arms Boss Rush on top of that guaranteed
-- baseline instead of resetting twice.
local function start_boss_rush()
    run.mode = "boss_rush"
    run.pending_boss_type = Boss.SEQUENCE[run.rush_boss_index]
    run.boss_incoming_timer = BOSS_INCOMING_DELAY
    GameState.set(GameState.PLAYING)
end

local function quit_to_menu()
    menu_cursor = 1
    reset_confirm_timer = 0
    restart_game(GameState.MENU)
end

trigger_card_select = function()
    -- defensive: clears any stale pending-freeze state regardless of whether
    -- this was reached via the post-boss delay or triggered directly (e.g.
    -- debug F2), so the two paths can't step on each other
    run.post_boss_pause_timer = 0
    run.pending_card_select = false

    local choices = Cards.roll_choices(CARD_CHOICE_COUNT)
    -- every card at max_stacks (only reachable after a very long run, or via
    -- debug F2 spam) -- skip the screen instead of opening it with nothing
    -- pickable, which would otherwise soft-lock CARD_SELECT with no escape
    if #choices == 0 then return end

    run.card_choices = choices
    run.card_cursor = 1
    run.chosen_card = nil
    run.card_confirm_timer = 0
    run.card_elapsed = 0
    Game.pause()
    GameState.set(GameState.CARD_SELECT)
end

finish_card_select = function()
    run.card_choices = nil
    run.chosen_card = nil
    run.card_elapsed = 0
    Game.resume()
    GameState.set(GameState.PLAYING)
end

function Game.on_boss_encounter_end()
    if run.mode == "boss_rush" then
        Game.rush_advance()
        return
    end

    Game.increase_score(50 + Cards.get("boss_bonus_score_add", 0))
    -- surviving the boss is what unlocks the next hazard
    run.unlock_stage = Unlocks.advance(run.unlock_stage)
    -- don't open the card screen immediately -- let the freeze-beat in
    -- update_freeze_timers give the player a moment first
    run.post_boss_pause_timer = POST_BOSS_PAUSE_DURATION
    run.pending_card_select = true
end

-- Boss Rush's version of the boss-defeated reward: no card, just a heal (or
-- a shield if already at full HP) -- the only thing carrying over between
-- fights in an otherwise card-free gauntlet. Then queues the next boss in
-- Boss.SEQUENCE, wrapping back to the start and bumping
-- run.rush_difficulty_mult once a full lap of all ten types is cleared.
function Game.rush_advance()
    run.rush_cleared = run.rush_cleared + 1

    local p_cx, p_cy = Player.center()
    if Player.lives >= Player.max_lives then
        if Player.give_shield() then
            FXManager.spawn_ring(p_cx, p_cy, 0.25, 0.6, 1, 12, 65, 180)
            Game.shake(0.1, 2)
        end
    elseif Player.heal(1) then
        FXManager.spawn_ring(p_cx, p_cy, 0, 1, 0.85, 12, 65, 180)
        Game.shake(0.1, 2)
    end

    run.rush_boss_index = run.rush_boss_index + 1
    if run.rush_boss_index > #Boss.SEQUENCE then
        run.rush_boss_index = 1
        run.rush_lap = run.rush_lap + 1
        run.rush_difficulty_mult = run.rush_difficulty_mult + RUSH_DIFFICULTY_STEP
    end

    run.pending_boss_type = Boss.SEQUENCE[run.rush_boss_index]
    -- same freeze-beat survival uses before opening its card screen; here it
    -- ends with update_freeze_timers arming the next boss's telegraph instead
    run.post_boss_pause_timer = POST_BOSS_PAUSE_DURATION
    run.pending_next_rush_boss = true
end

local function choose_card(index)
    if not run.card_choices then return end
    if run.card_confirm_timer > 0 then return end -- a pick is already locked in
    local card = run.card_choices[index]
    if not card then return end

    Cards.choose(card.id, Player)
    -- hold on the card screen a beat, with this card visually confirmed,
    -- instead of snapping straight back into danger (finish_card_select
    -- actually resumes once the timer runs out, in update_blocking_screens)
    run.chosen_card = index
    run.card_confirm_timer = CARD_CONFIRM_DELAY
end

local function toggle_pause()
    if GameState.is(GameState.PLAYING) then
        Game.pause()
        menu_cursor = 1
        GameState.set(GameState.PAUSED)
    elseif GameState.is(GameState.PAUSED) then
        Game.resume()
        GameState.set(GameState.PLAYING)
    end
end

-- ===========================================================================
-- Menu dispatch -- one place per menu where its behavior is defined, reached
-- identically from keyboard, gamepad and mouse
-- ===========================================================================

local function select_main_menu_option(index)
    if index == MAIN_MENU_START_INDEX then
        GameState.set(GameState.PLAYING)
    elseif index == MAIN_MENU_BOSS_RUSH_INDEX then
        start_boss_rush()
    elseif index == MAIN_MENU_RESET_INDEX then
        -- first select arms, a second one within the window confirms
        if reset_confirm_timer > 0 then
            HighScore.reset()
            reset_confirm_timer = 0
        else
            reset_confirm_timer = RESET_CONFIRM_DELAY
        end
    elseif index == MAIN_MENU_QUIT_INDEX then
        love.event.quit()
    end
end

local function select_pause_menu_option(index)
    if index == PAUSE_MENU_RESUME_INDEX then
        toggle_pause()
    elseif index == PAUSE_MENU_RESTART_INDEX then
        restart_game()
    elseif index == PAUSE_MENU_QUIT_INDEX then
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
    run.card_cursor = step_cursor(run.card_cursor, delta, CARD_CHOICE_COUNT)
end

-- ===========================================================================
-- Input
-- ===========================================================================

-- Returns true if the key was a debug hotkey and has been handled. Only live
-- while the overlay is on and the game is actually playing.
local function handle_debug_keys(key)
    if not (Debug.enabled and GameState.is(GameState.PLAYING)) then return false end

    if key == "f2" then
        trigger_card_select()
        return true
    elseif key == "f3" then
        Boss.spawn(Debug.cycle_boss(Boss.SEQUENCE))
        return true
    elseif key == "f4" then
        Difficulty.skip_wave()
        return true
    elseif key == "f5" then
        Debug.toggle_god_mode()
        return true
    end

    -- 1-9 spawn a *specific* boss straight away. Cycling with F3 alone meant
    -- reaching the 9th type took nine presses (each replacing the last
    -- mid-encounter), which made testing any one of them tedious. Safe to take
    -- these keys here: this branch only runs while PLAYING, and the digits are
    -- otherwise only used on the card-select screen.
    local boss_type = Debug.select_boss(tonumber(key), Boss.SEQUENCE)
    if boss_type then
        Boss.spawn(boss_type)
        return true
    end

    return false
end

function love.keypressed(key)
    if key == "f11" then
        Screen.toggle_fullscreen()
        return
    end

    if key == "f1" then
        Debug.toggle()
        return
    end

    if handle_debug_keys(key) then return end

    -- Each state handles its own keys and then returns, so no key is ever
    -- processed twice by two different branches.
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
            choose_card(run.card_cursor)
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
            -- the direct shortcuts from before the pause menu existed, kept
            -- working so existing muscle memory still does the right thing
        elseif key == "p" or key == "escape" then
            toggle_pause()
        elseif key == "r" then
            restart_game()
        elseif key == "m" then
            quit_to_menu()
        end
        return
    end

    if GameState.is(GameState.GAME_OVER) then
        if key == "r" then restart_game() end
        return
    end

    -- PLAYING from here down
    if key == "p" or key == "escape" then
        toggle_pause()
        return
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
            choose_card(run.card_cursor)
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
            -- Start unpauses, mirroring the keyboard's P. Handled here rather
            -- than left to fall through to the toggle below, now that each
            -- state returns.
        elseif button == "start" then
            toggle_pause()
        end
        return
    end

    if GameState.is(GameState.GAME_OVER) then
        if button == "a" then restart_game() end
        return
    end

    if button == "start" then
        toggle_pause()
        return
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

    -- LOVE reports window coordinates; every layout below (UI.card_layout, the
    -- two menu layouts) is expressed in game coordinates. Converting once here
    -- means those layouts stay the single source of truth for both drawing and
    -- hit-testing exactly as before, at any window size.
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
