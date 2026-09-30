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

function HUD.Panel(x, y, w, h, alpha)
    local c = HUD.Colors.panel
    draw.RoundedBox(math.floor(6 * HUD.Scale()), x, y, w, h, Color(c.r, c.g, c.b, c.a * (alpha or 255) / 255))
end

function HUD.Text(text, size, x, y, col, ax, ay, alpha)
    if alpha and alpha < 255 then col = Color(col.r, col.g, col.b, alpha) end
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
