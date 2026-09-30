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
