# Neon Dodge — Project Notes

A LÖVE2D (Lua) project the user is building specifically **to learn LÖVE and Lua**. Not a shipping product — every feature is chosen for what it teaches, so lean toward explaining/using idiomatic LÖVE patterns over the fastest hack. This file exists because the coding session this project was being developed in was rooted in an unrelated repo (`kensan_app`, a Flutter project) and couldn't be switched — start fresh sessions with this file's directory (`NeonDodge/`) as the actual working directory/root so tools resolve paths correctly.

**Claude Code sessions do not sync across the user's machines** (confirmed — session history is local/per-install, not account-synced even in the desktop app). This file is the actual continuity mechanism between machines/sessions: keep it current. See the last working agreement below.

## What the game is

Top-down dodge/collect arcade game, 800x600 window, no resize.
- Player: cyan square. Move with WASD/arrows or a gamepad's left stick/d-pad. Shift or gamepad A dashes (0.1s burst, 0.75s cooldown, both tunable by cards).
- HP: 3 max by default, shown as hearts top-left. Max HP can change at runtime via cards (Vitality +1, Glass Cannon -1).
- Red triangles ("Enemy") fall from top → touching one costs 1 HP. Speed ramps +5 per miss, capped (`Enemy.max_speed`) so it can't run away unbounded.
- Orange/red-ish diamond ("ZigzagEnemy") — same damage rule and capped ramp as Enemy, but sine-waves horizontally while falling. Fill `(1, 0.4, 0.05)` with a dark red `(0.7, 0, 0)` outline for readability against the yellow orb.
- Yellow circles ("Orb") → +5 score. Every 5th orb: heals +1 HP if not at max HP, otherwise **grants a one-hit shield instead** (only if not already shielded).
- Purple orbs ("VoidOrb") → +10 score on catch; **missing** one costs 1 HP (unless the Void Ward card is active).
- Shield: one-hit block, blue ring wrapping the player, quick pop-in animation then holds fixed size/alpha (no continuous pulsing).
- Boss: spawns every 3rd wave (`BOSS_WAVE_INTERVAL` in `main.lua`), patrols and fires a projectile spread for ~14s then leaves on its own (game is pure-dodge, no player attack, so it's a survive-the-encounter set piece, not a fight). Touching its body costs 1 HP, gated by a hit-cooldown so overlap doesn't melt HP every frame. Surviving it awards bonus score and opens the card-select screen.
- **Roguelike card system**: after every boss encounter, gameplay pauses and offers 3 of 20 cards (see `src/cards.lua`) — pick via mouse click, number keys 1/2/3, WASD/arrows + Enter/Space, or gamepad d-pad + A. Effects span survivability (+max HP, auto-shield/regen ticking, dodge chance, banked extra-life revives, Void Ward), score (flat bonuses, multipliers, low-HP double-score), mobility (move speed, dash cooldown/duration), and hazard-easing (fall speed, enemy speed-ramp, hitstop/shake intensity).
- Wave-based difficulty: spawn rates ramp over ~2 minutes via `src/difficulty.lua`; `Difficulty.wave()` (ticks every 20s) drives both the boss cadence and the UI wave counter.
- Screen-space shaders, always layered: bloom/glow (`src/bloom.lua`) on the whole scene, plus an on-hit chromatic-aberration + vignette pulse and an automatic red "heartbeat" vignette while at 1 HP (`src/hit_effect.lua`).
- Persistent high score via `love.filesystem` (`src/high_score.lua`), shown on the menu and game-over screens.
- Debug mode (**F1** to toggle) — bottom-screen overlay of state/wave/boss/player HP/active card modifiers/owned cards. While enabled: **F2** forces a card-select screen, **F3** force-spawns the boss, **F4** skips a full wave forward, **F5** toggles god mode (no damage).
- Game states: `menu` → `playing` → `paused` (P / gamepad Start) → `card_select` (after every boss) → `game_over` (R / gamepad A to restart).

## Architecture

Module-per-entity pattern in `src/`, each module is a table returned from its file, generally exposing `load/update/draw/pause/resume/reset`. Modules receive sibling modules as parameters where practical (e.g. `Enemy.update(dt, game_over, player, on_collision, spawn_rate)`); a few modules (`Cards`, `Debug`, `FXManager`) are `require`d directly by others since they're read-only "service" lookups rather than entities needing lifecycle wiring — this is an established, intentional exception, not drift to fix.

- `main.lua` — owns score, orb count, screen-shake state, hit-stop timer, wave/boss/card trigger bookkeeping; wires modules together via callback functions passed into each module's `update`. Centralizes card-modifier application for anything that isn't naturally owned by one module (`love.shake`/`love.hitstop` multiply by `shake_mult`/`hitstop_mult`; `love.increase_score` applies `score_mult`/`low_hp_score_mult` and rounds to an integer — a fractional multiplier like Glass Cannon's 1.5x will otherwise leave float scores).
- `src/game_state.lua` — explicit state machine: `GameState.MENU/PLAYING/PAUSED/CARD_SELECT/GAME_OVER`, `.set()`/`.is()`. Single source of truth for game state — don't reintroduce parallel booleans or per-module mirrors of the same flag.
- `src/pool.lua` — generic object pool (`Pool.new(factory)`, `:spawn(init)`, `:release(index)`, `:clear()`). O(1) swap-and-pop removal, **safe specifically because callers iterate backward** (`for i = #active, 1, -1`) and only ever release at the *current* loop index. Re-verify that invariant before reusing this pattern for a differently-iterated entity type.
- `src/player.lua`, `src/enemy.lua`, `src/zigzag_enemy.lua`, `src/orb.lua`, `src/void_orb.lua`, `src/boss.lua` (singleton, not pooled), `src/projectile.lua` — entity modules. `Player.take_damage` returns one of `"damaged"/"dead"/"shielded"/"dodged"/"revived"` and callers (`main.lua`) branch on all five.
- `src/fx_manager.lua` — particle-system templates + expanding "ring" shockwave effect (`spawn_ring`). `FXManager.spawn(name, ...)` silently no-ops on an unknown template name.
- `src/background.lua` — parallax starfield.
- `src/ui.lua` — HUD + menu/pause/game-over/card-select overlay text, driven by `GameState.current`. `UI.card_layout()` is the single source of truth for the 3 card rectangles, shared with `main.lua`'s mouse-click hit-testing so visuals and click boxes can't drift.
- `src/difficulty.lua` — wave counter + spawn-rate lerp; `Difficulty.skip_wave()` exists for the debug hotkey.
- `src/bloom.lua` — render scene to a canvas, bright-pass threshold + separable gaussian blur, additive composite into `Bloom.final_canvas`. **The threshold shader uses max-channel brightness, not perceptual luminance** — perceptual weights (favoring green) unfairly discount saturated reds/blues/purples, so a fully-lit red or purple shape would never bloom under the "correct-looking" luma formula. Keep this in mind when picking colors for new entities (e.g. future boss variants) if you want them to glow.
- `src/hit_effect.lua` — post-processes `Bloom.final_canvas` before it hits the screen: `hit_strength` (decaying, triggered on damage) drives chromatic aberration + vignette; `danger_strength` (continuous, driven by `Player.lives == 1`) drives an independent red-tint pulse. Two separate uniforms so the two effects can stack without fighting.
- `src/high_score.lua` — `love.filesystem` read/write, simple "only overwrite if higher" save.
- `src/cards.lua` — the roguelike layer. `CARD_POOL` (20 defs: `id/name/description/max_stacks/on_pick/modifiers`), `Cards.owned` (stack counts), `Cards.modifiers` (flat table, **fully recomputed from `owned` on every pick** — declarative, not incrementally mutated). `Cards.get(key, default)` is the read API every other module uses. Two cards (Guardian Aura, Regeneration) tick continuously via `Cards.update` and "bank" their trigger — if the condition (shieldless / missing HP) isn't met when the timer completes, it holds at cap and fires the instant the condition becomes true, rather than needing exact timing.
- `src/debug.lua` — F1-toggle overlay + hotkeys; reads `Cards.modifiers`/`Cards.owned` directly for the readout.

No assets/sprites/audio — everything is drawn procedurally. User explicitly doesn't want music.

### Color palette (avoid clashes when adding new entities, e.g. future boss variants)
Player = cyan `(0,1,0.85)` · Enemy = red `(1,0,0.2)` · ZigzagEnemy = red-orange `(1,0.4,0.05)` w/ dark red outline · Orb = yellow `(1,0.9,0.2)` · VoidOrb = purple `(0.7,0.2,1)` · Boss = magenta/pink `(1,0.1,0.6)` · Shield = blue `(0.3,0.65,1)` · Projectile = pink `(1,0.2,0.6)`. White/silver was tried for zigzag and explicitly set aside for a *future* power-up — don't reuse it for a hazard.

## Progress so far

Roughly in order:
1. **Game state machine**, **hit-stop juice**, **object pooling** (incl. a fixed pre-existing void-orb double-removal bug).
2. **ZigzagEnemy** — sine-wave hazard (roadmap item 4). Recolored twice based on feedback before landing on the current red-orange + dark-red-outline combo.
3. **Wave-based difficulty** (`src/difficulty.lua`) replacing flat spawn-rate constants.
4. **Bloom/glow shader** (`src/bloom.lua`).
5. **Boss + projectiles** (`src/boss.lua`, `src/projectile.lua`) — fixed an entry-phase "zip" bug where the patrol sine wave's phase reference wasn't reset when hover began.
6. **Speed-ramp caps** on Enemy/ZigzagEnemy — the miss-based `speed += 5` was unbounded and compounded badly right after a boss fight (player's attention split, more misses); capped both.
7. **Shield mechanic** — one-hit block via the 5-orb milestone at full HP; visual redone from a continuous pulse to a one-shot pop-in that then holds fixed.
8. **Damage-hit shader** (`src/hit_effect.lua`) — chromatic aberration + vignette on hit; later extended with the always-on low-HP red heartbeat pulse.
9. **Persistent high score** (`src/high_score.lua`).
10. **Gamepad support** — movement/dash/menu/pause/restart, alongside keyboard.
11. **Bloom fix for saturated colors** — void orb (and enemy/boss) weren't blooming because the threshold shader used perceptual luminance; switched to max-channel brightness.
12. **Roguelike card system + debug mode** (this was the big one): `src/cards.lua` (20 cards), `src/debug.lua`, new `CARD_SELECT` game state. Iterated through several bugs after initial ship: a free card offered at game start (wave-counter off-by-one), perks not resetting between runs (`Player.reset()` never restored `max_lives`, so Vitality/Glass Cannon picks leaked across deaths), trigger moved from "every wave" to "every boss" per feedback, WASD card selection added to match the gamepad cursor flow, and a fractional-score bug from Glass Cannon's 1.5x multiplier (score is now rounded on every `increase_score` call).

## Remaining roadmap

- **Distinct boss visuals/patterns** — multiple boss types with different attack patterns, replacing the single current boss. *(next up, user's stated plan)*
- Previously considered and explicitly set aside (not rejected, just deprioritized — fair game to revisit): score combo/multiplier system, a slow-motion power-up.

## Working agreements

- **Update this file (CLAUDE.md) after finishing each feature or meaningful edit**, keeping "What the game is" / "Architecture" / "Progress so far" accurate to the current code — not just appending, actually correct the sections that changed. This is now the primary continuity mechanism across the user's machines/sessions, since Claude Code sessions don't sync. Do not run any git commands as part of this — the user handles commits/pushes themselves.
- **Don't launch the game to test changes** beyond a quick launch-and-close sanity check (catches syntax/shader errors — Lua parses whole files upfront, so a clean load already rules those out across every touched file). Manual playtesting and reporting back is the user's job, not something to narrate doing.
- Prefer small, focused diffs per feature; incidental refactors are welcome *only* when directly required by the feature being built (e.g. the four near-identical collision handlers were consolidated into one `apply_player_hit` helper specifically because adding shield-handling to each copy separately would have triplicated the same branch) — call these out explicitly rather than folding them in silently.
- No music/audio work wanted at the moment.
- When a repeated back-and-forth happens on something purely aesthetic (e.g. zigzag's color took three tries), consider just asking directly rather than guessing again.
- Only create git commits when the user explicitly asks; write a commit message proactively after each completed feature/fix regardless, but never run the `git commit` command unprompted.
