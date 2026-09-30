--[[
    Hotbar, bottom centre. Replaces the default weapon selection.

    Number keys pick the weapon in that slot straight away (press again to
    cycle if a slot holds several). The scroll wheel steps through all
    weapons, and "lastinv" (Q by default) swaps to the previous one.
    The bar is bright right after switching and fades back after a moment.

    The weapon list is rebuilt at most five times a second, not every frame.
]]

local HUD = Rhylib.HUD
local UI = Rhylib.UI

local fadeVar = CreateClientConVar("rhylib_hud_hotbar_fade", "1", true, false, "Fade the hotbar when you're not switching weapons (0/1)")

local list = {}
local nextBuild = 0
local lastSwitch = 0
local previous = nil

local function rebuild(ply)
    list = {}
    for _, w in ipairs(ply:GetWeapons()) do list[#list + 1] = w end
    table.sort(list, function(a, b)
        local sa, sb = a:GetSlot(), b:GetSlot()
        if sa ~= sb then return sa < sb end
        return a:GetSlotPos() < b:GetSlotPos()
    end)
end

local function selectWeapon(wep)
    local ply = LocalPlayer()
    local active = ply:GetActiveWeapon()
    if not IsValid(wep) or wep == active then return end
    previous = active
    input.SelectWeapon(wep)
    lastSwitch = RealTime()
end

local function indexOf(wep)
    for i, w in ipairs(list) do
        if w == wep then return i end
    end
end

local function busy()
    local Inv = Rhylib.Inventory
    return (Inv and IsValid(Inv.panel)) or (Rhylib.Weapons and Rhylib.Weapons.Radial and Rhylib.Weapons.Radial.open)
end

Rhylib.Hook.Add("PlayerBindPress", "hud.hotbar", function(ply, bind, pressed)
    if not pressed or not ply:Alive() or ply:InVehicle() then return end

    local slot = string.match(bind, "^slot(%d+)")
    local isNext = string.find(bind, "invnext", 1, true)
    local isPrev = string.find(bind, "invprev", 1, true)
    local isLast = string.find(bind, "lastinv", 1, true)
    if not (slot or isNext or isPrev or isLast) then return end

    -- Let the physgun use the scroll wheel while holding something.
    local active = ply:GetActiveWeapon()
    if (isNext or isPrev) and IsValid(active) and active:GetClass() == "weapon_physgun" and ply:KeyDown(IN_ATTACK) then return end
    if busy() then return true end

    rebuild(ply)
    if #list == 0 then return true end

    if slot then
        local want = tonumber(slot) - 1
        local inSlot = {}
        for _, w in ipairs(list) do
            if w:GetSlot() == want then inSlot[#inSlot + 1] = w end
        end
        if #inSlot > 0 then
            -- Cycle within the slot if you're already on it.
            local pick = inSlot[1]
            for i, w in ipairs(inSlot) do
                if w == active then pick = inSlot[i % #inSlot + 1] end
            end
            selectWeapon(pick)
        end
    elseif isLast then
        if IsValid(previous) and previous:GetOwner() == ply then selectWeapon(previous) end
    else
        local i = indexOf(active) or 0
        local n = #list
        i = isNext and (i % n + 1) or ((i - 2) % n + 1)
        selectWeapon(list[i])
    end
    return true
end)

Rhylib.Hook.Add("HUDPaint", "hud.hotbar", function()
    if HUD.Hidden() then return end
    local ply = LocalPlayer()
    if RealTime() >= nextBuild then
        rebuild(ply)
        nextBuild = RealTime() + 0.2
    end
    if #list == 0 then return end

    local s = HUD.Scale()
    local C = HUD.Colors
    local active = ply:GetActiveWeapon()

    local since = RealTime() - lastSwitch
    local alpha = 255
    if fadeVar:GetBool() then
        alpha = since < 2.5 and 255 or math.max(90, 255 - (since - 2.5) * 400)
    end

    local bw, bh = math.floor(132 * s), math.floor(44 * s)
    local gap = math.floor(6 * s)
    local total = #list * bw + (#list - 1) * gap
    local x = math.floor((ScrW() - total) * 0.5)
    local y = ScrH() - bh - math.floor(24 * s)
    local font = UI.Font(15)

    for i, w in ipairs(list) do
        local bx = x + (i - 1) * (bw + gap)
        local isActive = w == active
        HUD.Panel(bx, y, bw, bh, isActive and 255 or alpha)
        if isActive then
            surface.SetDrawColor(C.accent.r, C.accent.g, C.accent.b, 255)
            surface.DrawRect(bx, y + bh - math.max(2, math.floor(3 * s)), bw, math.max(2, math.floor(3 * s)))
        end
        local a = isActive and 255 or alpha
        HUD.Text(tostring(w:GetSlot() + 1), 13, bx + math.floor(7 * s), y + math.floor(5 * s), C.dim, nil, nil, a)
        local name = w:GetPrintName() or w:GetClass()
        surface.SetFont(font)
        if surface.GetTextSize(name) > bw - 16 * s then name = string.sub(name, 1, 12) .. "…" end
        HUD.Text(name, 15, bx + bw * 0.5, y + bh * 0.5 + math.floor(3 * s), isActive and C.text or C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, a)
    end
end)
