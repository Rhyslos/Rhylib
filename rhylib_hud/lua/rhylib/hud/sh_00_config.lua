--[[
    Rhylib HUD: replaces the default health, armour, ammo and weapon
    selection HUD, and adds player info and voice/typing icons.

    Everything is drawn in HUDPaint (or a world render hook for the
    head icons) with plain surface calls. No panels, no per-frame
    networking. The only server work is sending armour values (see
    sv_10_armor.lua), because the engine doesn't send other players'
    armour to clients.
]]

Rhylib.HUD = Rhylib.HUD or {}

local Config = Rhylib.Config
Config.Register("hud", "targetRange", 700, "How close you must be to see a player's name and health when looking at them")
Config.Register("hud", "iconRange", 1500, "How far away speaking and typing icons are drawn")

-- First-person (helmet visor) layouts for the hotbar and ammo. The server
-- picks one with the admin command rhylib_hud_layout <name>; clients read
-- it from the global "rhylib_hud_layout".
Rhylib.HUD.Layouts = { f4 = "Ammo strip on an even hotbar row", f5 = "Curve tiles over a wide ammo plate", console = "Console plate next to the ammo box" }
Rhylib.HUD.DEFAULT_LAYOUT = "f4"

function Rhylib.HUD.VisorLayout()
    local name = GetGlobal2String("rhylib_hud_layout", Rhylib.HUD.DEFAULT_LAYOUT)
    if not Rhylib.HUD.Layouts[name] then name = Rhylib.HUD.DEFAULT_LAYOUT end
    return name
end
