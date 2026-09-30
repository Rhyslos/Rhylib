--[[
    Ammo counter.
      Third person: on a plate in the bottom-right corner.
      Helmet visor: a box on the lower-right cheek.

    Rhylib weapons: shots in the magazine, spare magazines and (for cell
    weapons) the power cell charge. Other weapons: clip and reserve.
    Weapons without ammo (physgun, tool gun, hands) show nothing.

    Rows, top to bottom:
        weapon name
        big shot count / magazine size        spare count + "magazines"
        Cell 73%                               1 spare      (cell weapons)
        cell bar                                             (cell weapons)
]]

local HUD = Rhylib.HUD

local function drawContent(ply, wep, x, y, w, sizes)
    local s = HUD.Scale()
    local C = HUD.Colors
    local right = x + w
    local clip = wep:Clip1()
    local ammoType = wep:GetPrimaryAmmoType()

    -- Weapon name
    HUD.Text(wep:GetPrintName() or "", 16, x, y, C.dim)
    y = y + sizes.name

    -- Shots / magazine size, spares on the right
    local maxClip = wep:GetMaxClip1()
    local low = maxClip > 0 and clip / maxClip <= 0.2
    local clipCol = clip == 0 and C.bad or (low and C.fuel or C.text)
    local mid = y + sizes.count * 0.5
    if clip >= 0 then
        local cw = HUD.Text(tostring(clip), 36, x, mid, clipCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        if maxClip > 0 then
            HUD.Text("/ " .. maxClip, 18, x + cw + math.floor(6 * s), mid + math.floor(6 * s), C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end

    local reserve = ply:GetAmmoCount(ammoType)
    if wep.IsRhylib then
        HUD.Text(tostring(reserve), 24, right, y + math.floor(2 * s), reserve > 0 and C.text or C.bad, TEXT_ALIGN_RIGHT)
        HUD.Text(reserve == 1 and "magazine" or "magazines", 13, right, y + sizes.count - math.floor(2 * s), C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
    elseif ammoType >= 0 then
        HUD.Text(tostring(reserve), 24, right, mid, C.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end
    y = y + sizes.count

    -- Power cell
    if sizes.cell > 0 then
        local charge = wep:GetCell()
        local lowCell = charge < Rhylib.Config.Get("weapons", "lowCellThreshold")
        local cells = ply:GetAmmoCount("rhylib_cell")
        HUD.Text(string.format("Cell %d%%", math.ceil(charge * 100)), 14, x, y + math.floor(4 * s), lowCell and C.bad or C.dim)
        HUD.Text(cells .. " spare", 14, right, y + math.floor(4 * s), C.dim, TEXT_ALIGN_RIGHT)
        HUD.Bar(x, y + sizes.cell - math.floor(10 * s), w, math.floor(6 * s), charge, lowCell and C.bad or C.armor)
    end
end

Rhylib.Hook.Add("HUDPaint", "hud.ammo", function()
    if HUD.Hidden() then return end
    local ply = LocalPlayer()
    local wep = ply:GetActiveWeapon()
    if not IsValid(wep) then return end
    if wep:Clip1() < 0 and wep:GetPrimaryAmmoType() < 0 then return end

    local s = HUD.Scale()
    local sizes = {
        name = math.floor(20 * s),
        count = math.floor(46 * s),
        cell = (wep.IsRhylib and wep.UsesCell) and math.floor(34 * s) or 0,
    }
    local contentH = sizes.name + sizes.count + sizes.cell

    if HUD.VisorActive and HUD.VisorActive() then
        local pad = math.floor(12 * s)
        local w = math.floor(240 * s)
        local mx, my = HUD.Margins("ammo")
        local x = ScrW() - w - mx
        local y = ScrH() - contentH - pad * 2 - my
        HUD.Panel(x, y, w, contentH + pad * 2)
        drawContent(ply, wep, x + pad, y + pad, w - pad * 2, sizes)
    else
        local x, y, w = HUD.Plate(1, math.floor(260 * s), contentH)
        drawContent(ply, wep, x, y, w, sizes)
    end
end)
