--[[
    Ammo counter, bottom right.

    Rhylib weapons: shots in the magazine, spare magazines and (for cell
    weapons) the power cell charge. Other weapons: clip and reserve.
    Weapons without ammo (physgun, tool gun, hands) show nothing.

    Layout, top to bottom, each on its own row:
        weapon name
        big shot count / magazine size        spare count + "magazines"
        Cell 73%                               1 spare      (cell weapons)
        cell bar                                             (cell weapons)
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
    local rhylib = wep.IsRhylib
    local cell = rhylib and wep.UsesCell

    local pad = math.floor(12 * s)
    local nameH = math.floor(20 * s)
    local countH = math.floor(46 * s)
    local cellH = math.floor(34 * s)
    local w = math.floor(240 * s)
    local h = pad * 2 + nameH + countH + (cell and cellH or 0)

    local mx, my = HUD.Margins("ammo")
    local x = ScrW() - w - mx
    local y = ScrH() - h - my
    local right = x + w - pad

    HUD.Panel(x, y, w, h)

    -- Row 1: weapon name
    local rowY = y + pad
    HUD.Text(wep:GetPrintName() or "", 16, x + pad, rowY, C.dim)
    rowY = rowY + nameH

    -- Row 2: shots / magazine size on the left, spares on the right
    local maxClip = wep:GetMaxClip1()
    local low = maxClip > 0 and clip / maxClip <= 0.2
    local clipCol = clip == 0 and C.bad or (low and C.fuel or C.text)
    if clip >= 0 then
        local cw = HUD.Text(tostring(clip), 36, x + pad, rowY + countH * 0.5, clipCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        if maxClip > 0 then
            HUD.Text("/ " .. maxClip, 18, x + pad + cw + math.floor(6 * s), rowY + countH * 0.5 + math.floor(6 * s), C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end

    local reserve = ply:GetAmmoCount(ammoType)
    if rhylib then
        HUD.Text(tostring(reserve), 24, right, rowY + math.floor(2 * s), reserve > 0 and C.text or C.bad, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
        HUD.Text(reserve == 1 and "magazine" or "magazines", 13, right, rowY + countH - math.floor(2 * s), C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
    elseif ammoType >= 0 then
        HUD.Text(tostring(reserve), 24, right, rowY + countH * 0.5, C.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end
    rowY = rowY + countH

    -- Rows 3 and 4: power cell
    if cell then
        local charge = wep:GetCell()
        local lowCell = charge < Rhylib.Config.Get("weapons", "lowCellThreshold")
        local cells = ply:GetAmmoCount("rhylib_cell")
        local textY = rowY + math.floor(4 * s)
        HUD.Text(string.format("Cell %d%%", math.ceil(charge * 100)), 14, x + pad, textY, lowCell and C.bad or C.dim)
        HUD.Text(cells .. " spare", 14, right, textY, C.dim, TEXT_ALIGN_RIGHT)
        HUD.Bar(x + pad, rowY + cellH - math.floor(10 * s), w - pad * 2, math.floor(6 * s), charge, lowCell and C.bad or C.armor)
    end
end)
