# Neon Dodge — Project Notes

A LÖVE2D (Lua) project the user is building specifically **to learn LÖVE and Lua**. Not a shipping product — every feature is chosen for what it teaches, so lean toward explaining/using idiomatic LÖVE patterns over the fastest hack. This file exists because the coding session this project was being developed in was rooted in an unrelated repo (`kensan_app`, a Flutter project) and couldn't be switched — start fresh sessions with this file's directory (`NeonDodge/`) as the actual working directory/root so tools resolve paths correctly.

## What the game is

Top-down dodge/collect arcade game, 800x600 window, no resize.
- Player: cyan square, WASD/arrows to move, Shift+direction to dash (0.1s burst, 0.75s cooldown).
- 3 HP max, shown as hearts top-left.
- Red triangles ("Enemy") fall from top → touching one costs 1 HP. Enemy speed ramps +5 every time one is missed (falls off bottom).
- Yellow circles ("Orb") fall from top → collect for +5 score; every 5th one collected heals +1 HP (capped at max).
- Purple orbs ("VoidOrb") fall from top → catch for +10 score; **missing** one (lets it fall off bottom) costs 1 HP.
- Score and orb-progress (`Orbs: n/5`) shown top-center/top-right.
- Game states: menu → playing → paused (P) → game_over (R to restart back to playing).

## Architecture

Module-per-entity pattern in `src/`, each module is a table returned from its file, generally exposing `load/update/draw/pause/resume/reset`:

- `main.lua` — owns score, orb count, screen-shake state, hit-stop timer; wires modules together via callback functions (`on_enemy_player_collision`, `on_orb_player_collision`, etc.) passed into each module's `update`.
- `src/game_state.lua` — explicit state machine: `GameState.MENU/PLAYING/PAUSED/GAME_OVER`, `.set()`/`.is()`. Single source of truth for game state — don't reintroduce parallel booleans (`is_paused`, `game_over` locals) or per-module mirrors of the same flag.
- `src/pool.lua` — generic object pool (`Pool.new(factory)`, `:spawn(init)`, `:release(index)`, `:clear()`). Reuses dead-object tables instead of allocating; removal is O(1) swap-and-pop (swap with last active element, pop tail). **Safe specifically because callers iterate backward** (`for i = #active, 1, -1`) and only ever release at the *current* loop index — that combination is what makes swap-pop non-skipping. If a future pooled entity type iterates differently, re-verify that invariant before reusing this pattern blindly.
- `src/player.lua`, `src/enemy.lua`, `src/orb.lua`, `src/void_orb.lua` — entity modules; the latter three hold a `.pool` (via `Pool`) instead of a raw list.
- `src/fx_manager.lua` — particle-system templates (`enemy_explosion`, `void_explosion`, `player_damage`, `player_death`) + expanding "ring" shockwave effect (`spawn_ring`). `FXManager.spawn(name, ...)` silently no-ops on an unknown template name — no error if you typo a template key, worth remembering when debugging "missing" FX.
- `src/background.lua` — parallax starfield.
- `src/ui.lua` — HUD (hearts/score/orb counter) + menu/pause/game-over overlay text, driven by `GameState.current`.

No assets/sprites/audio — everything is drawn procedurally (rects/triangles/circles + generated particle textures). User explicitly doesn't want music for now. Not currently considered a problem; only worth revisiting if aiming for a stronger visual identity (e.g. a bloom/glow shader would likely buy more than swapping in sprites).

## Progress so far

Completed, in order:
1. **Game state machine** — replaced scattered `game_over`/`is_paused` booleans (there were three separate copies: two locals in `main.lua` plus a mirrored `UI.is_paused`) with `src/game_state.lua`. Added a real menu screen ("NEON DODGE" / "Press SPACE to start") as the initial state — game no longer auto-starts into play.
2. **Hit-stop juice** — `love.hitstop(duration)` freezes `dt` (skips the whole update) for a short window on damage: 0.06s on non-lethal hits, 0.12s on the killing blow. Layered before/with the existing screen-shake and particle FX.
3. **Object pooling** — `src/pool.lua` used by `Enemy`/`Orb`/`VoidOrb` instead of raw `table.insert`/`table.remove` lists. While doing this, fixed a **pre-existing double-removal bug** in `void_orb.lua`: the miss-handling path called `VoidOrb.remove(index)` twice for the same event (once via the `on_miss` callback into `main.lua`, once directly after) — with `table.remove`'s shifting semantics this silently deleted an unrelated, already-alive void orb every time one was missed. Fixed by removing the redundant direct call.

Also removed one dead line early on: `main.lua`'s heal-on-every-5th-orb path called `FXManager.spawn("player_heal", ...)` but no such template exists in `fx_manager.lua` (leftover from before the user switched to the ring-shockwave heal effect) — it was a silent no-op, now deleted. The ring effect (`FXManager.spawn_ring`) is the actual heal visual and stays as-is.

## Remaining roadmap (user's own idea list, said "all of them seem fun", doing them one at a time)

4. **New hazard type with non-linear movement** — e.g. homing or zigzag enemy; exercise in vector math / easing. *(next up)*
5. **Persistent high score** via `love.filesystem.write`/`read`.
6. **Wave-based difficulty curve** — replace the flat `enemy_spawn_rate`/`orb_spawn_rate`/`void_orb_spawn_rate` constants in `main.lua` with a timed wave/lerp system.

Order isn't fixed in stone — the user picks what sounds fun next each time, this is just the suggested queue.

## Working agreements

- **Don't launch the game to test changes.** The user plays it themselves via LÖVE and reports back what happened. (A quick launch-and-verify-no-crash-then-close is fine if genuinely needed for sanity, but manual playtesting is the user's job, not something to narrate doing.)
- Prefer small, focused diffs per feature; this is a learning project, so incidental refactors are welcome *only* when they're directly in the code already being touched for the current feature (see the void-orb bug fix above) — call them out explicitly rather than folding them in silently.
- No music/audio work wanted at the moment.
