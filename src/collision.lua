local Collision = {}

-- Every entity in the game overlaps the player through one of exactly two
-- shapes: a circle (orbs, projectiles, a mine's blast radius) or an
-- axis-aligned rect with horizontal-only padding (falling hazards, boss
-- bodies). Both were hand-written in seven separate modules before this,
-- which is how a check quietly ends up missing a piece -- see the hazard_*
-- variants below for the piece that actually matters.
--
-- A read-only "service" module like Cards/Debug/FXManager: required directly
-- as a top-level local rather than passed in as a lifecycle dependency.

function Collision.circle_overlaps_player(player, x, y, radius)
    local cx, cy = player.center()
    local dx, dy = cx - x, cy - y
    local reach = player.size / 2 + radius
    -- squared compare -- same result as the distance, without the sqrt
    return (dx * dx + dy * dy) < reach * reach
end

-- `padding` shrinks the rect horizontally only (both hazards and bosses want
-- a slightly forgiving left/right edge but an honest top/bottom one)
function Collision.rect_overlaps_player(player, x, y, w, h, padding)
    padding = padding or 0

    return player.x < (x + w - padding) and (x + padding) < player.x + player.size
        and player.y < y + h and y < player.y + player.size
end

-- Hazard variants: identical, except a dashing player is never hit.
--
-- Dashing is a TRUE phase-through, not just damage immunity -- a hazard the
-- player dashes through isn't consumed, spawns no FX and triggers no hitstop
-- either (Player.take_damage's own dash check is a defensive fallback for
-- anything that calls it anyway). Routing every hazard check through here
-- means a new hazard type can't silently forget that guard.
--
-- Pickups (Orb/VoidOrb) deliberately use the plain overlap tests above
-- instead: dashing into something beneficial should still collect it.
function Collision.hazard_circle_hits_player(player, x, y, radius)
    return not player.is_dashing and Collision.circle_overlaps_player(player, x, y, radius)
end

function Collision.hazard_rect_hits_player(player, x, y, w, h, padding)
    return not player.is_dashing and Collision.rect_overlaps_player(player, x, y, w, h, padding)
end

return Collision
