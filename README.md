# Neon Dodge

A project to learn Lua and LÖVE — a top-down dodge/collect arcade game.
Everything is drawn with shapes: no sprites, no audio files, no external
libraries.

It has outgrown "tutorial project", so this file is the **map**: how a frame
runs, where each thing lives, and recipes for the changes you're most likely to
want to make. `CLAUDE.md` next to it is a different document — a running history
of *why* each decision was made. Come here to find your way around; go there
when you want to know why something is the way it is before changing it.

---

## Running it

```bash
love .
```

Window defaults to 1024x768 and is freely resizable; **F11** toggles fullscreen.

| Key | Effect |
| --- | --- |
| WASD / arrows | move (gamepad left stick or d-pad also works) |
| Shift / gamepad A | dash — a short burst that also passes *through* hazards |
| P / gamepad Start | pause |
| **F1** | toggle the debug overlay — everything below needs it on |
| F2 | force the card-select screen open |
| F3 | spawn the next boss in the sequence |
| **1**–**9** | spawn a *specific* boss (the overlay lists which number is which) |
| F4 | skip a whole wave forward |
| F5 | god mode |

F4 plus 1–9 is how you reach any part of the game in seconds instead of playing
to wave 30.

---

## How one frame works

LÖVE doesn't give you a `main()` you write yourself. You define callbacks and
the engine calls them. There are exactly **seven** in this project, all in
`main.lua`:

```
love.load()      -- once, at startup
love.update(dt)  -- every frame; dt = seconds since the last frame
love.draw()      -- every frame, right after update
love.resize()    -- when the window size changes
love.keypressed(key) / love.gamepadpressed(...) / love.mousepressed(...)
```

> **`love.xxx` vs `Game.xxx`** — in `main.lua`, anything named `love.xxx` is a
> callback *the engine calls for us*. Anything named `Game.xxx` is this
> project's own code (`Game.shake`, `Game.increase_score`,
> `Game.on_enemy_player_collision`, ...). If you're looking something up in the
> LÖVE documentation and it starts with `Game.`, it's ours — search this repo
> instead.

Because movement is always `speed * dt`, the game runs at the same real-world
speed regardless of framerate. Movement written *without* `dt` would be faster
on a faster machine.

### What `love.update` does, in order

1. **Bail out early for non-playing states.** `MENU`, `PAUSED` and
   `CARD_SELECT` each handle their own small bit of work and `return`.
2. **Hit-stop / post-boss freeze.** Both work by `return`ing before anything
   simulates — that's the whole trick to freezing the game for a moment.
3. **Tick the systems** — cards, difficulty, wave bookkeeping.
4. **Schedule events** — boss telegraph, storm telegraph, hazard unlocks.
5. **Update the player**, after writing its legal bounds from
   `Boss.get_player_bounds()`.
6. **Update every entity**, handing each one a spawn rate and a collision
   callback.
7. **FX and background** last.

### What `love.draw` does

```
Bloom.begin_scene()      -- start drawing into an off-screen canvas
  Screen.push()          -- scale game coords -> window coords
    background, shake transform, entities (player LAST so it's on top)
  Screen.pop()
Bloom.finish_scene()     -- bright-pass + blur + composite
HitEffect.draw(...)      -- chromatic aberration / vignette, blits to screen
Screen.push()            -- HUD goes back into game coords
  UI.draw(...)  Debug.draw(...)
Screen.pop()
```

---

## Module map

Every file in `src/` returns one table. Most expose the same lifecycle:
`load / update / draw / pause / resume / reset`. `main.lua` owns the lists that
drive those (`LOADABLE_MODULES`, `PAUSABLE_MODULES`, `RESETTABLE_MODULES`) —
they overlap but are deliberately different, see the comments there.

### Core plumbing

| File | What it is |
| --- | --- |
| `main.lua` | the conductor: owns score, timers, event scheduling, input routing. Contains no entity behavior itself |
| `src/screen.lua` | **read this first.** Virtual resolution — the game is authored at a fixed 800x600, the window can be any size |
| `src/game_state.lua` | the five states (`MENU/PLAYING/PAUSED/CARD_SELECT/GAME_OVER`) and nothing else |
| `src/pool.lua` | object pool — reuses tables instead of allocating per spawn |
| `src/collision.lua` | the only two overlap shapes in the game, plus the dash-phase-through rule |
| `src/mathx.lua` | `lerp`, `clamp`, `ease_out` — named so the formulas aren't cryptic inline |

### Entities

| File | What it is |
| --- | --- |
| `src/player.lua` | movement, dash, HP, shield, the bounds rect it's clamped into |
| `src/enemy.lua` | red triangle, falls straight down |
| `src/zigzag_enemy.lua` | sine-waves horizontally while falling |
| `src/mine.lua` | falls, anchors, telegraphs, then explodes in a radius |
| `src/orb.lua` | yellow pickup, +score, every 5th heals or shields |
| `src/void_orb.lua` | purple pickup — *missing* it costs HP |
| `src/projectile.lua` | boss shots, optionally homing (steers toward the player) |

### Bosses

Nine types sharing one engine, split so the part you tune is separate from the
part that runs it:

| File | What it is |
| --- | --- |
| **`src/boss/types.lua`** | **the roster — start here.** One entry per type, holding every number and behavior that makes it itself. Tuning or adding a boss happens here |
| `src/boss.lua` | the engine: the enter → hover → exit lifecycle, body collision, player bounds. Nothing type-specific |
| `src/boss/movement.lua` | the five movement modes (patrol / orbit / bounce / charge / blink) |
| `src/boss/attacks.lua` | how bosses shoot — `spread`, `aimed_shot`, the ring bursts |
| `src/boss/shapes.lua` | one silhouette per type. Pure drawing, no game logic — a safe place to experiment |
| `src/boss/laser.lua` | the laser's beam, as a self-contained subsystem |
| `src/boss/config.lua` | timings shared by all of the above |

### Presentation

| File | What it is |
| --- | --- |
| `src/ui.lua` | HUD, menus, card-select screen |
| `src/fx_manager.lua` | particle bursts and expanding shockwave rings |
| `src/background.lua` | parallax starfield |
| `src/bloom.lua` | the glow shader (bright-pass + blur + additive composite) |
| `src/hit_effect.lua` | on-hit chromatic aberration, low-HP red pulse |

### Systems

| File | What it is |
| --- | --- |
| `src/difficulty.lua` | wave counter and the spawn-rate ramp |
| `src/cards.lua` | the 20 roguelike upgrade cards |
| `src/storms.lua` | the four storm types — a registry, like the boss roster |
| `src/unlocks.lua` | which hazards exist at which stage of the run |
| `src/high_score.lua` | save/load one number to disk |
| `src/debug.lua` | the F1 overlay and its hotkeys |

### Where state lives

Worth knowing before you add a variable to `main.lua`:

- **`run`** — one table holding everything belonging to the current run (score,
  timers, wave bookkeeping, unlock stage). `reset_run_state()` is the only thing
  that clears it, so adding a field to `run` automatically means it gets wiped
  on restart. There is no second list to keep in sync — that used to be ~20
  loose locals plus a hand-written 20-line reset, and forgetting one was a bug
  this project hit twice.
- **module-level locals in `main.lua`** — only `menu_cursor` and
  `reset_confirm_timer`, which belong to menu navigation rather than a run.
- **each module's own table** — `Player.lives`, `Boss.instances`, etc. Wiped by
  that module's `reset()`.

---

## Four rules that will bite you if you don't know them

**1. Ask `Screen`, never `love.graphics`, for dimensions.**

```lua
local x = love.math.random(0, Screen.WIDTH - size)               -- YES
local x = love.math.random(0, love.graphics.getWidth() - size)   -- NO
```

`Screen.WIDTH/HEIGHT` are the fixed 800x600 play area every constant in the
game is tuned against. `love.graphics.getWidth()` is the *window*, which the
player can resize. They used to be the same number, which is exactly why they're
easy to mix up. `src/screen.lua` is the only file that should ask about the
window.

**2. Pools require backward iteration.**

```lua
for i = #active, 1, -1 do        -- MUST be backward
    ...
    if hit then Enemy.remove(i) end
end
```

`Pool:release` fills the removed slot with the *last* element. Iterating
forward would skip whatever got moved into the slot you just vacated.

**3. Hazards must use the `hazard_*` collision helpers.**

```lua
-- hazards: returns false while the player is dashing (phase-through)
Collision.hazard_rect_hits_player(player, x, y, w, h, padding)
Collision.hazard_circle_hits_player(player, x, y, radius)

-- pickups: no dash exception, because dashing into a reward should collect it
Collision.circle_overlaps_player(player, x, y, radius)
```

Dashing is a *true* phase-through: hazards skip the collision check entirely,
so nothing gets consumed and no effects fire. Using the wrong helper silently
breaks that, which is why the rule lives in one file.

**4. `dt` on everything that moves.** See above.

---

## Recipes

### Add a falling hazard

Copy `src/enemy.lua` — it's the simplest complete example. Then:

1. Add a spawn rate to `config` in `src/difficulty.lua`. The number is a
   **period in seconds**, so *smaller = more often*.
2. In `main.lua`: `require` it, add it to `LOADABLE_MODULES`,
   `PAUSABLE_MODULES` and `RESETTABLE_MODULES`, call its `update` in
   `love.update` and its `draw` in `love.draw` (before `Player.draw()`).
3. Give it a collision handler:
   `Game.on_x_player_collision = hazard_collision_handler(X, SHAKE_DURATION, SHAKE_MAGNITUDE)`
4. Use `Collision.hazard_*` for the hit test, not a hand-written one.
5. Pick a color that doesn't clash — the palette list is in `CLAUDE.md`.

### Add a boss type

Only **`src/boss/types.lua`** changes: add an entry to `BOSS_TYPES` and a name
to `SEQUENCE`. The wave cadence and every debug hotkey pick it up
automatically. The engine (`src/boss.lua`) needs no edit at all — that's the
point of the split.

| Field | Meaning |
| --- | --- |
| `width`, `height`, `color_fill`, `color_core` | the body |
| `movement` | where it is each frame. Defaults to the sine patrol; `Movement.orbit` / `.bounce` / `.charge` / `.blink` also exist |
| `patrol_amplitude`, `patrol_speed` | for the default patrol. **Amplitude must be big enough to actually reach both screen edges** or a strip stays permanently safe |
| `fire`, `fire_interval` | optional — the charger has no `fire` at all, its body is the attack |
| `fire_second` | a follow-up volley; it can re-arm itself to chain (see turret/phantom) |
| `player_min_y` | walls off the top of the screen so the boss can't be camped above |
| `encounter_duration` | seconds it hovers. Escalates along `SEQUENCE` — 16s for the first boss up to 24s for the last |

Plus five optional hooks the engine calls if present, which is how a type does
something the generic engine doesn't know about:

| Hook | When |
| --- | --- |
| `update_extra` | extra per-frame work (the laser's beam cycle, the warden's closing arena) |
| `extra_collision` | an extra hit test beyond the body rect |
| `is_encounter_done` | override the default "hover for 14s then leave" exit |
| `draw_extra` | overlay drawn on top of the body |
| `debug_state` | one line of sub-state for the F1 overlay |

The laser uses four of those five, which is why it needs no special-casing
anywhere in the engine.

Every hook is called as `(instance, type_def, ...)`. **Take the `type_def` even
if you think you don't need it** — the charger's `debug_state` once didn't, then
later needed it, and the result was a crash that only fired with the debug
overlay open during a charger encounter.

**The trap to know about:** if your boss only threatens *downward*, a player
standing above it is completely safe. This was found and fixed across four
separate attempts — read items 19–22 in `CLAUDE.md` before designing an attack
pattern.

### Add a card

One entry in `CARD_POOL` in `src/cards.lua`. Either:

- `modifiers = function(stacks, mods) mods.some_key = ... end` — then read it
  wherever it applies with `Cards.get("some_key", default)`, or
- `on_pick = function(player) ... end` for a one-time effect.

`Cards.modifiers` is **recomputed from scratch** on every pick, so never
mutate it incrementally.

### Tune difficulty

- Wave length / spawn ramp: `src/difficulty.lua`
- Boss and storm cadence: `BOSS_WAVE_INTERVAL`, `STORM_WAVE_INTERVAL` in `main.lua`
- Storm composition: `STORM_TYPES` in `main.lua`
- Which hazards exist when: the `UNLOCK_STAGE_*` constants in `main.lua`
- Individual boss numbers: that type's entry in `BOSS_TYPES`

---

## Lua / LÖVE patterns used here

Things in this codebase that aren't obvious if you're still learning the
language:

**A module is a table you return.**

```lua
local Enemy = {}
function Enemy.load() ... end
return Enemy            -- `require("src/enemy")` gives you this table
```

**`local` is resolved by position in the file, not call order.** A function
defined at the bottom is invisible to one at the top. Two ways around it, both
used here:

```lua
-- 1. forward declaration (declare now, assign later)
local trigger_card_select
function love.update() trigger_card_select() end     -- fine
trigger_card_select = function() ... end

-- 2. a table field, looked up when the call actually runs
local Game = {}
function love.update() Game.increase_score(5) end    -- fine
function Game.increase_score(n) ... end
```

**Named arguments via a table.** Lua has no keyword arguments, so a function
needing many values takes one table:

```lua
UI.draw({ state = ..., score = ..., lives = ... })
```

`UI.draw` and `Boss.update` both do this. `UI.draw` previously took sixteen
positional arguments, where adding one meant counting commas at the call site.

**`goto continue`** is Lua's "skip to the next loop iteration" — it needs an
explicit `::continue::` label at the end of the loop body. The entity modules
use it so a hazard that just collided doesn't also get its off-screen check run.

**Multiple return values.** `Player.center()` returns two numbers, and
`local x, y = Player.center()` unpacks them. No table allocated.

**Colors are 0–1, not 0–255.** `love.graphics.setColor(1, 0, 0.2)` is that red
triangle.

---

## Verifying a change

A quick launch-and-close catches syntax and shader errors, because Lua parses a
whole file before running any of it:

```bash
love .
```

But that only exercises the **menu** — it never reaches gameplay, a boss, or the
pause screen. For anything touching those, the pattern used in this project is a
throwaway harness: a scratch folder with a copy of `src/` and its own `main.lua`
that drives the code paths directly and prints pass/fail. That's how "all nine
bosses still complete an encounter" gets checked without playing nine encounters
by hand.

Actual *feel* — is it fun, is it fair, is the difficulty right — can only be
playtested, and no harness substitutes for it.
