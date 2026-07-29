-- Boss silhouettes.
--
-- Every type used to draw the identical rounded rectangle with only its colors
-- changed, so nine bosses read as one boss in nine paints -- and colour alone
-- is the weakest way to tell things apart mid-fight, when you're looking at
-- the arena rather than at the enemy. Each type now has a shape that says
-- something about what it does:
--
--   sentinel  wide angular gunship, barrels along the bottom edge
--   charger   heavy downward wedge -- it points where it's about to slam
--   homing    forward-leaning dart with a single seeking eye
--   bomber    round-bellied hull with bomb ports underneath
--   laser     flat emitter bar with a focusing lens
--   phantom   soft, uneven, hollow -- barely there
--   splitter  one body with a visible seam down the middle
--   warden    fortress octagon with inward-facing brackets
--   turret    ring with radial barrels, no "front" at all
--   bouncer   riveted wrecking ball with a molten core
--   splitter_hunter  (post-split) stretched arrowhead, fast and pointed
--   splitter_sentry  (post-split) small ringed post, planted and watching
--
-- Each function draws a complete body at (x, y, w, h) in `fill`/`core` colors
-- at `alpha`. They're plain drawing -- no state, no game logic -- so this file
-- is safe to experiment in.
local Shapes = {}

local function set(color, alpha, mul)
    mul = mul or 1
    love.graphics.setColor(color[1] * mul, color[2] * mul, color[3] * mul, alpha)
end

-- ---------------------------------------------------------------------------
-- sentinel: a wide gunship. Angled front corners and a row of barrels along
-- the bottom, which is where its 7-shot fan actually comes from.
-- ---------------------------------------------------------------------------
function Shapes.sentinel(x, y, w, h, fill, core, alpha)
    local cut = w * 0.16
    set(fill, alpha)
    love.graphics.polygon("fill",
        x + cut, y,
        x + w - cut, y,
        x + w, y + h * 0.45,
        x + w - cut * 0.7, y + h,
        x + cut * 0.7, y + h,
        x, y + h * 0.45)

    -- cockpit
    set(core, alpha)
    love.graphics.polygon("fill",
        x + w * 0.30, y + h * 0.18,
        x + w * 0.70, y + h * 0.18,
        x + w * 0.62, y + h * 0.55,
        x + w * 0.38, y + h * 0.55)

    -- barrels, evenly spaced like the fan they fire
    for i = 0, 4 do
        local bx = x + w * (0.18 + i * 0.16)
        love.graphics.rectangle("fill", bx - w * 0.02, y + h * 0.78, w * 0.04, h * 0.22)
    end
end

-- ---------------------------------------------------------------------------
-- charger: a downward wedge. The whole body is the attack, so it's shaped like
-- the thing it does -- a heavy point aimed at the floor.
-- ---------------------------------------------------------------------------
function Shapes.charger(x, y, w, h, fill, core, alpha)
    set(fill, alpha)
    love.graphics.polygon("fill",
        x, y,
        x + w, y,
        x + w * 0.82, y + h * 0.55,
        x + w * 0.5, y + h,
        x + w * 0.18, y + h * 0.55)

    -- weight at the top, so it reads as falling nose-first
    set(core, alpha)
    love.graphics.rectangle("fill", x + w * 0.14, y + h * 0.10, w * 0.72, h * 0.26, 4, 4)

    -- impact point
    set(core, alpha, 0.85)
    love.graphics.polygon("fill",
        x + w * 0.5, y + h * 0.95,
        x + w * 0.35, y + h * 0.55,
        x + w * 0.65, y + h * 0.55)
end

-- ---------------------------------------------------------------------------
-- homing: a dart, leaning forward, with one eye. Reads as "it is looking at
-- you", which is exactly what its shots do.
-- ---------------------------------------------------------------------------
function Shapes.homing(x, y, w, h, fill, core, alpha)
    set(fill, alpha)
    love.graphics.polygon("fill",
        x + w * 0.5, y + h,
        x + w, y + h * 0.42,
        x + w * 0.78, y,
        x + w * 0.22, y,
        x, y + h * 0.42)

    -- swept-back fins
    set(fill, alpha, 0.7)
    love.graphics.polygon("fill", x, y + h * 0.42, x + w * 0.20, y + h * 0.30, x + w * 0.14, y + h * 0.66)
    love.graphics.polygon("fill", x + w, y + h * 0.42, x + w * 0.80, y + h * 0.30, x + w * 0.86, y + h * 0.66)

    -- the eye
    set(core, alpha)
    love.graphics.circle("fill", x + w * 0.5, y + h * 0.44, h * 0.20)
    set(fill, alpha, 0.35)
    love.graphics.circle("fill", x + w * 0.5, y + h * 0.44, h * 0.09)
end

-- ---------------------------------------------------------------------------
-- bomber: heavy round-bellied hull with ports underneath, so the mines it
-- drops look like they come from somewhere.
-- ---------------------------------------------------------------------------
function Shapes.bomber(x, y, w, h, fill, core, alpha)
    -- swept wings first, behind the fuselage
    set(fill, alpha, 0.6)
    love.graphics.polygon("fill",
        x, y + h * 0.30, x + w * 0.36, y + h * 0.32, x + w * 0.30, y + h * 0.62, x + w * 0.06, y + h * 0.55)
    love.graphics.polygon("fill",
        x + w, y + h * 0.30, x + w * 0.64, y + h * 0.32, x + w * 0.70, y + h * 0.62, x + w * 0.94, y + h * 0.55)

    -- fuselage: blunt nose, tapering tail
    set(fill, alpha)
    love.graphics.polygon("fill",
        x + w * 0.30, y,
        x + w * 0.70, y,
        x + w * 0.80, y + h * 0.35,
        x + w * 0.68, y + h * 0.72,
        x + w * 0.32, y + h * 0.72,
        x + w * 0.20, y + h * 0.35)

    -- cockpit
    set(core, alpha)
    love.graphics.rectangle("fill", x + w * 0.38, y + h * 0.10, w * 0.24, h * 0.18, 3, 3)

    -- open bomb bay, dark so it actually reads as a hole the mines drop from
    love.graphics.setColor(0.05, 0.04, 0.02, alpha)
    love.graphics.rectangle("fill", x + w * 0.34, y + h * 0.58, w * 0.32, h * 0.30, 3, 3)

    set(core, alpha, 0.9)
    for i = 0, 2 do
        love.graphics.circle("fill", x + w * (0.40 + i * 0.10), y + h * 0.73, h * 0.07)
    end
end

-- ---------------------------------------------------------------------------
-- laser: a flat wide emitter. Deliberately the least "creature-like" of the
-- nine -- it's a piece of equipment, and the lens is the only feature.
-- ---------------------------------------------------------------------------
function Shapes.laser(x, y, w, h, fill, core, alpha)
    set(fill, alpha)
    love.graphics.rectangle("fill", x, y + h * 0.18, w, h * 0.64, 4, 4)

    -- heavy end caps
    set(fill, alpha, 0.75)
    love.graphics.rectangle("fill", x, y, w * 0.16, h, 3, 3)
    love.graphics.rectangle("fill", x + w * 0.84, y, w * 0.16, h, 3, 3)

    -- focusing lens
    set(core, alpha)
    love.graphics.circle("fill", x + w * 0.5, y + h * 0.5, h * 0.30)
    set(fill, alpha, 0.4)
    love.graphics.circle("fill", x + w * 0.5, y + h * 0.5, h * 0.15)
end

-- ---------------------------------------------------------------------------
-- phantom: soft, uneven and hollow. The only body drawn as an outline rather
-- than a solid, because "barely there" is the whole identity -- and it already
-- fades via alpha, so the shape has to survive being half-transparent.
-- ---------------------------------------------------------------------------
function Shapes.phantom(x, y, w, h, fill, core, alpha)
    local cx = x + w * 0.5
    local dome_r = w * 0.5
    local dome_cy = y + h * 0.46

    -- a rounded dome sweeping into three wavy lobes -- built as one point list
    -- so the fill and the outline can't disagree
    local pts = {}
    for i = 0, 16 do
        local a = math.pi + (i / 16) * math.pi -- left -> right over the top
        pts[#pts + 1] = cx + math.cos(a) * dome_r
        pts[#pts + 1] = dome_cy + math.sin(a) * (h * 0.46)
    end
    -- tail: down-up-down-up-down across the bottom
    local lobes = { 1.0, 0.72, 1.0, 0.72, 1.0 }
    for i, depth in ipairs(lobes) do
        local t = 1 - (i - 1) / (#lobes - 1) -- right back to left
        pts[#pts + 1] = x + w * (0.04 + t * 0.92)
        pts[#pts + 1] = y + h * (0.46 + 0.54 * depth)
    end

    -- deliberately translucent: this one is drawn hollow rather than solid,
    -- because "barely there" is the whole identity -- and it already fades via
    -- alpha, so the silhouette has to survive being half-transparent
    set(fill, alpha, 0.45)
    love.graphics.polygon("fill", pts)

    set(core, alpha * 0.9)
    love.graphics.setLineWidth(2)
    love.graphics.polygon("line", pts)
    love.graphics.setLineWidth(1)

    -- two dark hollow eyes, which is what makes it read as a face rather than
    -- a blob at a glance
    love.graphics.setColor(0.06, 0.06, 0.09, alpha)
    love.graphics.circle("fill", cx - w * 0.16, y + h * 0.34, h * 0.13)
    love.graphics.circle("fill", cx + w * 0.16, y + h * 0.34, h * 0.13)
end

-- ---------------------------------------------------------------------------
-- splitter: one body with an obvious seam down the middle, so the split reads
-- as something it was always going to do rather than a surprise.
-- ---------------------------------------------------------------------------
function Shapes.splitter(x, y, w, h, fill, core, alpha)
    local gap = w * 0.03
    local half = w * 0.5 - gap

    set(fill, alpha)
    love.graphics.polygon("fill",
        x, y + h * 0.25, x + half, y, x + half, y + h, x, y + h * 0.75)
    love.graphics.polygon("fill",
        x + w, y + h * 0.25, x + w - half, y, x + w - half, y + h, x + w, y + h * 0.75)

    -- the seam itself
    set(core, alpha, 0.6)
    love.graphics.rectangle("fill", x + w * 0.5 - gap * 0.5, y + h * 0.1, gap, h * 0.8)

    set(core, alpha)
    love.graphics.circle("fill", x + half * 0.55, y + h * 0.5, h * 0.16)
    love.graphics.circle("fill", x + w - half * 0.55, y + h * 0.5, h * 0.16)
end

-- ---------------------------------------------------------------------------
-- splitter_hunter: what one half of the split becomes -- a swept-wing blade,
-- notched at the shoulders so it reads as cutting forward rather than just a
-- blocky arrow. Deliberately not another dart-with-fins-and-eye like homing:
-- angular where homing is rounded, and the bright spine (not a circular eye)
-- is what carries its identity.
-- ---------------------------------------------------------------------------
function Shapes.splitter_hunter(x, y, w, h, fill, core, alpha)
    set(fill, alpha)
    love.graphics.polygon("fill",
        x + w * 0.5, y,                  -- nose
        x + w * 0.68, y + h * 0.4,        -- right shoulder
        x + w, y + h * 0.62,              -- right wingtip
        x + w * 0.6, y + h * 0.56,        -- right notch (in from the wingtip)
        x + w * 0.6, y + h,                -- right tail
        x + w * 0.4, y + h,                -- left tail
        x + w * 0.4, y + h * 0.56,         -- left notch
        x, y + h * 0.62,                    -- left wingtip
        x + w * 0.32, y + h * 0.4)         -- left shoulder

    -- a darker underlayer along the wing edges, so the notch reads as a fold
    -- in the body rather than a flat cutout
    set(fill, alpha, 0.6)
    love.graphics.polygon("fill", x + w * 0.6, y + h * 0.56, x + w, y + h * 0.62, x + w * 0.6, y + h)
    love.graphics.polygon("fill", x + w * 0.4, y + h * 0.56, x, y + h * 0.62, x + w * 0.4, y + h)

    -- the bright spine down the middle -- the line it tracks along
    set(core, alpha)
    love.graphics.rectangle("fill", x + w * 0.46, y + h * 0.14, w * 0.08, h * 0.72, 2, 2)
    love.graphics.circle("fill", x + w * 0.5, y + h * 0.16, h * 0.11)
end

-- ---------------------------------------------------------------------------
-- splitter_sentry: the other half -- a ringed post rather than a creature,
-- since it drifts in a small circle rather than actively hunting. Four ticks
-- around the rim echo the full ring it fires, rather than turret's eight
-- barrels along one -- smaller and plainer so the two don't read as the same
-- boss at a glance.
-- ---------------------------------------------------------------------------
function Shapes.splitter_sentry(x, y, w, h, fill, core, alpha)
    local cx, cy = x + w * 0.5, y + h * 0.5
    local r = math.min(w, h) * 0.5

    set(fill, alpha, 0.55)
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", cx, cy, r * 0.95)
    love.graphics.setLineWidth(1)

    set(fill, alpha)
    love.graphics.circle("fill", cx, cy, r * 0.7)

    set(core, alpha)
    love.graphics.circle("fill", cx, cy, r * 0.3)

    set(core, alpha, 0.8)
    for i = 0, 3 do
        local a = i / 4 * math.pi * 2
        local tx, ty = cx + math.cos(a) * r * 0.95, cy + math.sin(a) * r * 0.95
        love.graphics.circle("fill", tx, ty, r * 0.12)
    end
end

-- ---------------------------------------------------------------------------
-- warden: a fortress octagon with brackets that face inward, echoing the walls
-- it closes around the player.
-- ---------------------------------------------------------------------------
function Shapes.warden(x, y, w, h, fill, core, alpha)
    local cw, ch = w * 0.22, h * 0.28

    set(fill, alpha)
    love.graphics.polygon("fill",
        x + cw, y, x + w - cw, y,
        x + w, y + ch, x + w, y + h - ch,
        x + w - cw, y + h, x + cw, y + h,
        x, y + h - ch, x, y + ch)

    -- inward brackets: the squeeze, drawn on the body
    set(core, alpha)
    love.graphics.setLineWidth(3)
    love.graphics.line(x + w * 0.22, y + h * 0.26, x + w * 0.34, y + h * 0.26, x + w * 0.34, y + h * 0.74,
        x + w * 0.22, y + h * 0.74)
    love.graphics.line(x + w * 0.78, y + h * 0.26, x + w * 0.66, y + h * 0.26, x + w * 0.66, y + h * 0.74,
        x + w * 0.78, y + h * 0.74)
    love.graphics.setLineWidth(1)

    set(core, alpha, 0.8)
    love.graphics.rectangle("fill", x + w * 0.44, y + h * 0.40, w * 0.12, h * 0.20, 2, 2)
end

-- ---------------------------------------------------------------------------
-- turret: a ring with radial barrels and no front at all, because it fires
-- full circles and orbits rather than facing anywhere.
-- ---------------------------------------------------------------------------
function Shapes.turret(x, y, w, h, fill, core, alpha)
    local cx, cy = x + w * 0.5, y + h * 0.5
    local r = math.min(w, h) * 0.5

    -- barrels first, so the hub sits on top of them
    set(fill, alpha, 0.8)
    for i = 0, 7 do
        local a = i / 8 * math.pi * 2
        local bx, by = cx + math.cos(a) * r * 0.95, cy + math.sin(a) * r * 0.95
        love.graphics.circle("fill", bx, by, r * 0.16)
    end

    set(fill, alpha)
    love.graphics.circle("fill", cx, cy, r * 0.78)

    set(core, alpha)
    love.graphics.circle("fill", cx, cy, r * 0.42)
    set(fill, alpha, 0.5)
    love.graphics.circle("fill", cx, cy, r * 0.18)
end

-- ---------------------------------------------------------------------------
-- bouncer: a solid riveted ball, since it IS the projectile -- a heavy
-- wrecking ball rather than a creature, distinct from turret's hollow ring
-- of barrels despite both being round.
-- ---------------------------------------------------------------------------
function Shapes.bouncer(x, y, w, h, fill, core, alpha)
    local cx, cy = x + w * 0.5, y + h * 0.5
    local r = math.min(w, h) * 0.5

    set(fill, alpha)
    love.graphics.circle("fill", cx, cy, r)

    -- inset rivets, not barrels sticking out -- reads as a battered solid
    -- shell rather than a gun platform
    set(fill, alpha, 0.55)
    for i = 0, 5 do
        local a = i / 6 * math.pi * 2
        love.graphics.circle("fill", cx + math.cos(a) * r * 0.68, cy + math.sin(a) * r * 0.68, r * 0.1)
    end

    -- molten core, glowing through the shell
    set(core, alpha)
    love.graphics.circle("fill", cx, cy, r * 0.4)
    set(fill, alpha, 0.5)
    love.graphics.circle("fill", cx, cy, r * 0.2)
end

-- the shared fallback, and what every type used to look like
function Shapes.default(x, y, w, h, fill, core, alpha)
    set(fill, alpha)
    love.graphics.rectangle("fill", x, y, w, h, 10, 10)

    set(core, alpha)
    love.graphics.rectangle("fill", x + w * 0.16, y + h * 0.25, w * 0.68, h * 0.5, 6, 6)
end

return Shapes
