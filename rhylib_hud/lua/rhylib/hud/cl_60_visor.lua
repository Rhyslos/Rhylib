--[[
    Clone helmet visor, first person only.

    The see-through area is a T shape: wide across the top, narrowing to
    a chin opening at the bottom centre. Around it: a curved brow along
    the top and two cheek pieces in the lower corners.

    On the left edge: four transparent blue blocks for armour. On the
    right edge: four transparent red blocks for health. Each block is
    always 25%; a partly used block fills from the bottom. The ammo
    counter sits on the lower-right cheek (cl_30_ammo.lua).

    Hidden in third person, in vehicles and while dead.
    Toggle: rhylib_hud_visor 0/1.

    The shape is built once per screen size as cached triangles, so each
    frame is only a few dozen cheap draw calls.
]]

local HUD = Rhylib.HUD
local visorVar = CreateClientConVar("rhylib_hud_visor", "1", true, false, "Clone helmet visor in first person (0/1)")

local COL_SHELL = Color(12, 14, 16, 250)
local COL_EDGE_DARK = Color(0, 0, 0, 230)
local COL_EDGE_LIGHT = Color(170, 176, 180, 120)

local COL_ARMOR_FILL = Color(60, 140, 255, 110)
local COL_ARMOR_LINE = Color(90, 160, 255, 170)
local COL_HEALTH_FILL = Color(230, 60, 50, 110)
local COL_HEALTH_LINE = Color(240, 90, 80, 170)
local COL_EMPTY_ALPHA = 45

-- Shape, as shares of the screen (0..1). Mirrored left/right.
local BROW_EDGE = 0.022      -- brow depth at the screen sides
local BROW_CENTRE = 0.07     -- brow depth in the middle
local CHEEK_TOP = 0.75       -- where the cheek meets the screen side
local CHIN_HALF = 0.1        -- half the chin opening width (0.1 = 20% of the screen)
local CURVE_STEPS = 32

-- Armour / health blocks.
local BLOCK_X = 0.004        -- distance from the screen side
local BLOCK_W = 0.04
local BLOCK_TOP = 0.2
local BLOCK_H = 0.105
local BLOCK_GAP = 0.013

function HUD.VisorActive()
    if not visorVar:GetBool() then return false end
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() or ply:InVehicle() or ply:ShouldDrawLocalPlayer() then return false end
    local wep = ply:GetActiveWeapon()
    return not (IsValid(wep) and wep:GetClass() == "gmod_camera")
end

-- One triangle with the winding surface.DrawPoly needs.
local function tri(ax, ay, bx, by, cx, cy)
    if (bx - ax) * (cy - ay) - (by - ay) * (cx - ax) < 0 then
        bx, by, cx, cy = cx, cy, bx, by
    end
    return { { x = ax, y = ay }, { x = bx, y = by }, { x = cx, y = cy } }
end

-- Fill a region as a fan of triangles from one anchor point.
local function fan(list, ax, ay, points)
    for i = 1, #points - 1 do
        local p, q = points[i], points[i + 1]
        list[#list + 1] = tri(ax, ay, p[1], p[2], q[1], q[2])
    end
end

local function bezier(t, p0, p1, p2, p3)
    local u = 1 - t
    return u * u * u * p0 + 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t * p3
end

local cache = { w = 0, h = 0 }

local function build(W, H)
    cache = { w = W, h = H, tris = {}, edges = {}, blocks = {} }

    -- Brow: a smooth sag, deepest in the middle.
    local brow = {}
    for i = 0, CURVE_STEPS do
        local f = i / CURVE_STEPS
        local sag = math.sin(f * math.pi)
        brow[#brow + 1] = { f * W, (BROW_EDGE + (BROW_CENTRE - BROW_EDGE) * sag) * H }
    end
    local browShape = { { 0, 0 } }
    for _, p in ipairs(brow) do browShape[#browShape + 1] = p end
    browShape[#browShape + 1] = { W, 0 }
    fan(cache.tris, W * 0.5, 0, browShape)
    cache.edges[#cache.edges + 1] = brow

    -- Cheeks: from the screen side, sweeping down into the chin opening.
    for _, side in ipairs({ -1, 1 }) do
        local function sx(f) return side < 0 and f * W or (1 - f) * W end
        local x0, x1, x2, x3 = 0, 0.3, 0.5 - CHIN_HALF - 0.01, 0.5 - CHIN_HALF
        local y0, y1, y2, y3 = CHEEK_TOP, CHEEK_TOP + 0.05, 0.86, 1.0
        local curve = {}
        for i = 0, CURVE_STEPS do
            local t = i / CURVE_STEPS
            curve[#curve + 1] = { sx(bezier(t, x0, x1, x2, x3)), bezier(t, y0, y1, y2, y3) * H }
        end
        local shape = { { sx(0), H } }
        for _, p in ipairs(curve) do shape[#shape + 1] = p end
        -- Fan from the bottom corner, which sees every point on the curve.
        local corner = { sx(0), H }
        local pts = {}
        for i = 2, #shape do pts[#pts + 1] = shape[i] end
        fan(cache.tris, corner[1], corner[2], pts)
        cache.edges[#cache.edges + 1] = curve
    end

    -- Block rectangles, bottom block first.
    for _, side in ipairs({ -1, 1 }) do
        local list = {}
        local bw = BLOCK_W * W
        local x = side < 0 and BLOCK_X * W or W - BLOCK_X * W - bw
        for k = 4, 1, -1 do
            local y = (BLOCK_TOP + (k - 1) * (BLOCK_H + BLOCK_GAP)) * H
            list[#list + 1] = { x, y, bw, BLOCK_H * H }
        end
        cache.blocks[side] = list
    end
end

-- Four blocks for a 0..1 value, each block 25%, filling from the bottom.
local function drawBlocks(list, frac, fill, line)
    local thick = math.max(1, math.floor(ScrH() / 540))
    for k, r in ipairs(list) do
        local part = math.Clamp(frac * 4 - (k - 1), 0, 1)
        local x, y, w, h = r[1], r[2], r[3], r[4]
        if part > 0 then
            local fh = math.floor(h * part + 0.5)
            surface.SetDrawColor(fill)
            surface.DrawRect(x, y + h - fh, w, fh)
            surface.SetDrawColor(line)
        else
            surface.SetDrawColor(line.r, line.g, line.b, COL_EMPTY_ALPHA)
        end
        surface.DrawOutlinedRect(x, y, w, h, thick)
    end
end

-- Drawn before the other HUD parts (priority -10), so they sit on top.
Rhylib.Hook.Add("HUDPaint", "hud.visor", function()
    if not HUD.VisorActive() then return end
    local W, H = ScrW(), ScrH()
    if cache.w ~= W or cache.h ~= H then build(W, H) end

    draw.NoTexture()
    surface.SetDrawColor(COL_SHELL)
    for _, t in ipairs(cache.tris) do surface.DrawPoly(t) end

    -- Edges: a dark line with a faint light line on the see-through side.
    for _, edge in ipairs(cache.edges) do
        for i = 1, #edge - 1 do
            local p, q = edge[i], edge[i + 1]
            surface.SetDrawColor(COL_EDGE_DARK)
            surface.DrawLine(p[1], p[2], q[1], q[2])
            surface.DrawLine(p[1], p[2] - 1, q[1], q[2] - 1)
            surface.SetDrawColor(COL_EDGE_LIGHT)
            surface.DrawLine(p[1], p[2] - 2, q[1], q[2] - 2)
        end
    end

    local ply = LocalPlayer()
    local maxAr = ply.GetMaxArmor and ply:GetMaxArmor() or 100
    if maxAr <= 0 then maxAr = 100 end
    drawBlocks(cache.blocks[-1], ply:Armor() / maxAr, COL_ARMOR_FILL, COL_ARMOR_LINE)
    drawBlocks(cache.blocks[1], math.max(ply:Health(), 0) / math.max(ply:GetMaxHealth(), 1), COL_HEALTH_FILL, COL_HEALTH_LINE)
end, -10)
