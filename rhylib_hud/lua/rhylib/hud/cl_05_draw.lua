-- Small drawing helpers shared by the HUD files.

local HUD = Rhylib.HUD
local UI = Rhylib.UI

HUD.Colors = {
    panel = Color(20, 22, 20, 170),
    track = Color(255, 255, 255, 28),
    health = Color(214, 88, 76),
    healthLow = Color(255, 60, 50),
    armor = Color(90, 150, 255),
    fuel = Color(239, 159, 39),
    text = UI.Colors.text,
    dim = UI.Colors.textDim,
    accent = UI.Colors.accent,
    bad = UI.Colors.bad,
}

function HUD.Scale()
    return ScrH() / 1080
end

-- A flat bar: dark track with a filled part. frac is 0..1.
function HUD.Bar(x, y, w, h, frac, col, alpha)
    alpha = alpha or 255
    local track = HUD.Colors.track
    surface.SetDrawColor(track.r, track.g, track.b, track.a * alpha / 255)
    surface.DrawRect(x, y, w, h)
    local fw = math.floor(w * math.Clamp(frac, 0, 1) + 0.5)
    if fw > 0 then
        surface.SetDrawColor(col.r, col.g, col.b, alpha)
        surface.DrawRect(x, y, fw, h)
    end
end

-- One reusable colour for faded draws, so nothing is allocated per frame.
local scratch = Color(0, 0, 0, 0)
local function faded(col, alpha)
    scratch.r, scratch.g, scratch.b, scratch.a = col.r, col.g, col.b, col.a * alpha / 255
    return scratch
end

function HUD.Panel(x, y, w, h, alpha)
    local c = HUD.Colors.panel
    if alpha and alpha < 255 then c = faded(c, alpha) end
    draw.RoundedBox(math.floor(6 * HUD.Scale()), x, y, w, h, c)
end

function HUD.Text(text, size, x, y, col, ax, ay, alpha)
    if alpha and alpha < 255 then col = faded(col, alpha) end
    return draw.SimpleText(text, UI.Font(size), x, y, col, ax or TEXT_ALIGN_LEFT, ay or TEXT_ALIGN_TOP)
end

-- Distance from the screen edges for a HUD box. kind: "ammo", "hotbar"
-- or "status". While the helmet visor is showing, the ammo box sits on
-- the lower-right cheek and the hotbar low in the chin opening.
function HUD.Margins(kind)
    if HUD.VisorActive and HUD.VisorActive() then
        if kind == "ammo" then return math.floor(ScrW() * 0.012), math.floor(ScrH() * 0.022) end
        if kind == "hotbar" then return 0, math.floor(ScrH() * 0.03) end
    end
    if kind == "hotbar" then return 0, math.floor(10 * HUD.Scale()) end
    local m = math.floor(24 * HUD.Scale())
    return m, m
end

-- True while something should hide the HUD (camera tool, dead, etc.).
function HUD.Hidden()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return true end
    local wep = ply:GetActiveWeapon()
    return IsValid(wep) and wep:GetClass() == "gmod_camera"
end

--[[
    Third-person corner plate: a dark plate in a bottom corner. Both
    plates are always the same fixed size, whatever they hold. The outer
    edge is a little taller than the inner edge, and the inner side
    slants down to the screen bottom.
    side: -1 = bottom left, 1 = bottom right.
    Returns the content box: x, y, w, h.
]]
local plateVerts = { { x = 0, y = 0 }, { x = 0, y = 0 }, { x = 0, y = 0 }, { x = 0, y = 0 } }
local COL_PLATE = Color(16, 18, 17, 205)
local COL_PLATE_EDGE = Color(0, 0, 0, 220)
local COL_PLATE_HI = Color(170, 176, 180, 90)

HUD.PLATE_W = 300   -- content size at 1080p, same for both plates
HUD.PLATE_H = 100

function HUD.Plate(side)
    local W, H = ScrW(), ScrH()
    local s = HUD.Scale()
    local contentW, contentH = math.floor(HUD.PLATE_W * s), math.floor(HUD.PLATE_H * s)
    local pad = math.floor(14 * s)
    local innerH = contentH + pad * 2
    local drop = math.floor(H * 0.035)   -- outer edge this much taller
    local slant = math.floor(W * 0.03)   -- inner edge leans out this far at the bottom
    local innerX = pad * 2 + contentW

    local function px(x) return side < 0 and x or W - x end
    local ax, ay = px(0), H - innerH - drop
    local bx, by = px(innerX), H - innerH
    local cx, cy = px(innerX + slant), H
    local dx, dy = px(0), H

    -- Winding for surface.DrawPoly: clockwise on screen.
    if side < 0 then
        plateVerts[1].x, plateVerts[1].y = ax, ay
        plateVerts[2].x, plateVerts[2].y = bx, by
        plateVerts[3].x, plateVerts[3].y = cx, cy
        plateVerts[4].x, plateVerts[4].y = dx, dy
    else
        plateVerts[1].x, plateVerts[1].y = bx, by
        plateVerts[2].x, plateVerts[2].y = ax, ay
        plateVerts[3].x, plateVerts[3].y = dx, dy
        plateVerts[4].x, plateVerts[4].y = cx, cy
    end
    draw.NoTexture()
    surface.SetDrawColor(COL_PLATE)
    surface.DrawPoly(plateVerts)

    -- Edges along the top and the slant.
    surface.SetDrawColor(COL_PLATE_EDGE)
    surface.DrawLine(ax, ay, bx, by)
    surface.DrawLine(ax, ay - 1, bx, by - 1)
    surface.DrawLine(bx, by, cx, cy)
    surface.SetDrawColor(COL_PLATE_HI)
    surface.DrawLine(ax, ay + 1, bx, by + 1)

    local x = side < 0 and pad or W - pad - contentW
    return x, H - innerH + pad, contentW, contentH
end
