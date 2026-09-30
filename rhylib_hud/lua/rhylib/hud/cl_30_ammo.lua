--[[
    Ammo counter, bottom right.

    Rhylib weapons: shots in the magazine, spare magazines and (for cell
    weapons) the power cell charge. Other weapons: clip and reserve.
    Weapons without ammo (physgun, tool gun, hands) show nothing.
]]

local HUD = Rhylib.HUD

Rhylib.Hook.Add("HUDPaint", "hud.ammo", function()
    if HUD.Hidden() then return end
    local ply = LocalPlayer()
    local wep = ply:GetActiveWeapon()
    if not IsValid(wep) then return end

    local clip = wep:Clip1()
    local ammoType = wep:GetPrimaryAmmoType()
    if clip < 0 and ammoType < 0 then return end

    local s = HUD.Scale()
    local C = HUD.Colors
    local pad = math.floor(12 * s)
    local w = math.floor(240 * s)
    local rhylib = wep.IsRhylib
    local cell = rhylib and wep.UsesCell
    local h = pad * 2 + math.floor(62 * s) + (cell and math.floor(26 * s) or 0)
    local x = ScrW() - w - math.floor(24 * s)
    local y = ScrH() - h - math.floor(24 * s)

    HUD.Panel(x, y, w, h)
    local right = x + w - pad

    -- Weapon name
    HUD.Text(wep:GetPrintName() or "", 16, x + pad, y + pad, C.dim)

    -- Shots in the magazine / magazine size
    local maxClip = wep:GetMaxClip1()
    local empty = clip == 0
    local low = maxClip > 0 and clip / maxClip <= 0.2
    local clipCol = empty and C.bad or (low and C.fuel or C.text)
    local by = y + pad + math.floor(22 * s)
    local cw = 0
    if clip >= 0 then
        cw = HUD.Text(tostring(clip), 36, x + pad, by, clipCol)
        if maxClip > 0 then
            HUD.Text("/ " .. maxClip, 18, x + pad + cw + math.floor(6 * s), by + math.floor(15 * s), C.dim)
        end
    end

    -- Spares on the right
    local reserve = ply:GetAmmoCount(ammoType)
    if rhylib then
        HUD.Text(tostring(reserve), 28, right, by + math.floor(2 * s), reserve > 0 and C.text or C.bad, TEXT_ALIGN_RIGHT)
        HUD.Text(reserve == 1 and "magazine" or "magazines", 14, right, by + math.floor(32 * s), C.dim, TEXT_ALIGN_RIGHT)
    elseif ammoType >= 0 then
        HUD.Text(tostring(reserve), 28, right, by + math.floor(2 * s), C.text, TEXT_ALIGN_RIGHT)
    end

    -- Power cell
    if cell then
        local charge = wep:GetCell()
        local lowCell = charge < Rhylib.Config.Get("weapons", "lowCellThreshold")
        local cy = y + h - pad - math.floor(12 * s)
        local cells = ply:GetAmmoCount("rhylib_cell")
        local label = string.format("Cell %d%%", math.ceil(charge * 100))
        HUD.Text(label, 14, x + pad, cy - math.floor(2 * s), lowCell and C.bad or C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
        HUD.Text(cells .. " spare", 14, right, cy - math.floor(2 * s), C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
        HUD.Bar(x + pad, cy + math.floor(2 * s), w - pad * 2, math.floor(6 * s), charge, lowCell and C.bad or C.armor)
    end
end)
