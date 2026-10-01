--[[
    Hotbar, bottom centre. Replaces the default weapon selection.

    With rhylib_inventory: fixed numbered slots that you fill yourself by
    dragging items onto the hotbar row in the inventory window (4 slots,
    6 with a backpack). A slot can hold any item; for now only weapons do
    something when picked (grenades and handing out ammo come later).
    Anything you hold that isn't in your inventory (force-given, like the
    physgun or a sandbox loadout) sits in an overflow slot after them:
    its key cycles through them.

    Without rhylib_inventory: one box per weapon you hold, by weapon slot.

    Number keys pick a slot. An empty slot, or the slot you're already
    holding, puts your gun away (the empty "Stowed" weapon). The scroll
    wheel steps through every weapon on the bar, "lastinv" (Q by default)
    swaps to the previous one. The bar
    is bright right after switching and fades back after a moment.

    The bar is rebuilt five times a second (or at once if a weapon on it
    was removed), not every frame.
]]

local HUD = Rhylib.HUD
local UI = Rhylib.UI

local fadeVar = CreateClientConVar("rhylib_hud_hotbar_fade", "1", true, false, "Fade the hotbar when you're not switching weapons (0/1)")

HUD.HotbarRect = HUD.HotbarRect or { x = 0, y = 0, w = 0, h = 0, frame = 0 }

-- entries[i] = { key = number shown, wep = weapon or nil, name, sub, empty, overflow = { weapons } }
local entries = {}
local nextBuild = 0
local lastSwitch = 0
local previous = nil

local STOWED = "rhylib_stowed"

local function inventory()
    local Inv = Rhylib.Inventory
    return Inv and Inv.HotbarItem and Rhylib.Items and Inv or nil
end

local function selectWeapon(wep)
    local ply = LocalPlayer()
    local active = ply:GetActiveWeapon()
    if not IsValid(wep) or wep == active then return end
    previous = active
    input.SelectWeapon(wep)
    lastSwitch = RealTime()
end

-- Put the gun away (hold the empty Stowed weapon), if the player has it.
local function stow(ply)
    local w = ply:GetWeapon(STOWED)
    if IsValid(w) then selectWeapon(w) end
end

local function itemSub(inst, def)
    if inst.count > 1 then return "x" .. inst.count end
    if def.rounds and def.rounds > 1 then return math.floor((inst.data.fill or 1) * def.rounds + 0.5) .. "/" .. def.rounds end
    if def.fill then return math.ceil((inst.data.fill or 1) * 100) .. "%" end
end

local function rebuild(ply)
    entries = {}
    local Inv = inventory()
    local weps = ply:GetWeapons()

    if not Inv then
        -- No inventory: one box per held weapon, by weapon slot.
        local list = {}
        for _, w in ipairs(weps) do
            if IsValid(w) then list[#list + 1] = w end
        end
        table.sort(list, function(a, b)
            local sa, sb = a:GetSlot(), b:GetSlot()
            if sa ~= sb then return sa < sb end
            return a:GetSlotPos() < b:GetSlotPos()
        end)
        for i, w in ipairs(list) do
            entries[i] = { key = i, wep = w, name = w:GetPrintName() or w:GetClass() }
        end
        return
    end

    local Items = Rhylib.Items
    local n = Items.HotbarSize(Inv)
    for k = 1, n do
        local inst = Inv.HotbarItem(k)
        local def = inst and Items.Get(inst.id)
        if def then
            local wep = def.weapon and ply:GetWeapon(def.weapon)
            entries[k] = { key = k, wep = IsValid(wep) and wep or nil, name = def.name, sub = itemSub(inst, def) }
        else
            entries[k] = { key = k, empty = true }
        end
    end

    -- Overflow: held weapons that aren't inventory items.
    local inInv = {}
    for _, inst in pairs(Inv.byUid) do inInv[inst.id] = true end
    local over = {}
    for _, w in ipairs(weps) do
        if IsValid(w) and not inInv[w:GetClass()] and w:GetClass() ~= STOWED then over[#over + 1] = w end
    end
    if #over > 0 then
        local active = ply:GetActiveWeapon()
        local shown = over[1]
        for _, w in ipairs(over) do
            if w == active then shown = w end
        end
        entries[n + 1] = {
            key = n + 1, wep = shown, overflow = over,
            name = shown:GetPrintName() or shown:GetClass(),
            sub = #over > 1 and ("+" .. (#over - 1) .. " more") or nil,
        }
    end
end

-- Every weapon on the bar, in order (for the scroll wheel).
local function cycleList()
    local list = {}
    for _, e in ipairs(entries) do
        if e.overflow then
            for _, w in ipairs(e.overflow) do list[#list + 1] = w end
        elseif e.wep then
            list[#list + 1] = e.wep
        end
    end
    return list
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
    lastSwitch = RealTime()

    if slot then
        local e = entries[tonumber(slot)]
        if not e then return true end
        if e.overflow then
            -- Cycle through the overflow weapons.
            local pick = e.overflow[1]
            for i, w in ipairs(e.overflow) do
                if w == active then pick = e.overflow[i % #e.overflow + 1] end
            end
            selectWeapon(pick)
        elseif e.wep and e.wep ~= active then
            selectWeapon(e.wep)
        elseif inventory() and (e.empty or e.wep == active) then
            -- Empty slot, or the gun you're already holding: put it away.
            -- (Non-weapon items do nothing yet.)
            stow(ply)
        end
    elseif isLast then
        if IsValid(previous) and previous:GetOwner() == ply then selectWeapon(previous) end
    else
        local list = cycleList()
        local n = #list
        if n == 0 then return true end
        local i = 0
        for k, w in ipairs(list) do
            if w == active then i = k end
        end
        i = isNext and (i % n + 1) or ((i - 2) % n + 1)
        selectWeapon(list[i])
    end
    return true
end)

local function fit(text, font, maxW)
    surface.SetFont(font)
    if surface.GetTextSize(text) <= maxW then return text end
    while #text > 1 and surface.GetTextSize(text .. "…") > maxW do text = string.sub(text, 1, -2) end
    return text .. "…"
end

Rhylib.Hook.Add("HUDPaint", "hud.hotbar", function()
    if HUD.Hidden() then return end
    local ply = LocalPlayer()
    -- Rebuild five times a second, or straight away if a weapon on the bar
    -- was removed (dying, dropping, being stripped).
    local stale = RealTime() >= nextBuild
    for i = 1, #entries do
        local w = entries[i].wep
        if w ~= nil and not IsValid(w) then stale = true break end
    end
    if stale then
        rebuild(ply)
        nextBuild = RealTime() + 0.2
    end
    local count = #entries
    if count == 0 then return end

    local s = HUD.Scale()
    local C = HUD.Colors
    local active = ply:GetActiveWeapon()

    local since = RealTime() - lastSwitch
    -- In the helmet visor the bar hides completely when idle, so it
    -- doesn't block the chin opening.
    local visor = HUD.VisorActive and HUD.VisorActive()
    local minAlpha = visor and 0 or 90
    local alpha = 255
    if fadeVar:GetBool() or visor then
        alpha = since < 2.5 and 255 or math.max(minAlpha, 255 - (since - 2.5) * 400)
    end

    -- Square-ish boxes between the corner plates; they shrink to fit.
    local gap = math.floor(6 * s)
    local space = ScrW() * 0.44
    local bw = math.floor(math.Clamp((space - gap * (count - 1)) / count, 56 * s, 104 * s))
    local bh = math.floor(76 * s)
    local total = count * bw + (count - 1) * gap
    local x = math.floor((ScrW() - total) * 0.5)
    local _, my = HUD.Margins("hotbar")
    local y = ScrH() - bh - my

    -- Shared with the stamina bar, which sits on top (even while this fades out).
    local r = HUD.HotbarRect
    r.x, r.y, r.w, r.h, r.frame = x, y, total, bh, FrameNumber()

    if alpha <= 0 then return end
    local font = UI.Font(14)
    local barH = math.max(2, math.floor(3 * s))

    for i, e in ipairs(entries) do
        local bx = x + (i - 1) * (bw + gap)
        local isActive = e.wep ~= nil and e.wep == active
        local a = isActive and math.min(255, alpha * 2) or alpha
        if e.empty then a = a * 0.5 end
        HUD.Panel(bx, y, bw, bh, a)
        if isActive then
            surface.SetDrawColor(C.accent.r, C.accent.g, C.accent.b, a)
            surface.DrawRect(bx, y + bh - barH, bw, barH)
        end
        HUD.Text(e.overflow and (e.key .. " +") or tostring(e.key), 13, bx + math.floor(7 * s), y + math.floor(5 * s), C.dim, nil, nil, a)

        if not e.empty then
            HUD.Text(fit(e.name, font, bw - 10 * s), 14, bx + bw * 0.5, y + bh * 0.5, isActive and C.text or C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, a)
            if e.sub then
                HUD.Text(e.sub, 12, bx + bw * 0.5, y + bh * 0.76, C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, a)
            end
        end
    end
end)
