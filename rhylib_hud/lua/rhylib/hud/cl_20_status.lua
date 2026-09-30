-- Health and armour, bottom left. With DarkRP, also job and money.

local HUD = Rhylib.HUD

local shown = { hp = 100, ar = 0 }  -- smoothed values so bars slide instead of jump

Rhylib.Hook.Add("HUDPaint", "hud.status", function()
    if HUD.Hidden() then return end
    -- In the helmet visor, the armour and health blocks replace this box.
    if HUD.VisorActive and HUD.VisorActive() then return end
    local ply = LocalPlayer()
    local s = HUD.Scale()
    local C = HUD.Colors

    local hp, maxHp = math.max(ply:Health(), 0), math.max(ply:GetMaxHealth(), 1)
    local ar = ply:Armor()
    local maxAr = ply.GetMaxArmor and ply:GetMaxArmor() or 100
    if maxAr <= 0 then maxAr = 100 end

    local ft = FrameTime() * 8
    shown.hp = Lerp(math.min(ft, 1), shown.hp, hp)
    shown.ar = Lerp(math.min(ft, 1), shown.ar, ar)

    local darkrp = DarkRP and ply.getDarkRPVar
    local pad = math.floor(12 * s)
    local w = math.floor(300 * s)
    local barH = math.floor(10 * s)
    local rowH = math.floor(34 * s)
    local rows = 1 + ((ar > 0) and 1 or 0)
    local h = pad * 2 + rows * rowH + (darkrp and math.floor(24 * s) or 0)
    local mx, my = HUD.Margins("status")
    local x = mx
    local y = ScrH() - h - my

    HUD.Panel(x, y, w, h)
    local cx, cy = x + pad, y + pad
    local labelW = math.floor(44 * s)
    local barW = w - pad * 2 - labelW - math.floor(8 * s)

    -- Health
    local low = hp / maxHp < 0.3
    local hcol = low and C.healthLow or C.health
    HUD.Text(tostring(hp), 26, cx, cy + rowH * 0.5, low and C.healthLow or C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    HUD.Bar(cx + labelW, cy + (rowH - barH) * 0.5, barW, barH, shown.hp / maxHp, hcol)
    cy = cy + rowH

    -- Armour (only while you have some)
    if ar > 0 then
        HUD.Text(tostring(ar), 26, cx, cy + rowH * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        HUD.Bar(cx + labelW, cy + (rowH - barH) * 0.5, barW, barH, shown.ar / maxAr, C.armor)
        cy = cy + rowH
    end

    -- DarkRP job and money
    if darkrp then
        local job = ply:getDarkRPVar("job") or team.GetName(ply:Team())
        local money = ply:getDarkRPVar("money") or 0
        local moneyText = DarkRP.formatMoney and DarkRP.formatMoney(money) or ("$" .. money)
        HUD.Text(job, 16, cx, cy + math.floor(4 * s), C.dim)
        HUD.Text(moneyText, 16, x + w - pad, cy + math.floor(4 * s), C.text, TEXT_ALIGN_RIGHT)
    end
end)
