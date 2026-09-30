-- Hide the default HUD parts that Rhylib replaces.

local HIDE = {
    CHudHealth = true,
    CHudBattery = true,
    CHudAmmo = true,
    CHudSecondaryAmmo = true,
    CHudWeaponSelection = true,
    DarkRP_LocalPlayerHUD = true,  -- DarkRP health, job and money box
    DarkRP_EntityDisplay = true,   -- DarkRP names above heads
}

Rhylib.Hook.Add("HUDShouldDraw", "hud.hide", function(name)
    if HIDE[name] then return false end
end)

-- Sandbox's "name and health when you look at someone" text.
Rhylib.Hook.Add("HUDDrawTargetID", "hud.hide", function()
    return false
end)
