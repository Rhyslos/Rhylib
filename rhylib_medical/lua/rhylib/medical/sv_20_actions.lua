--[[
    Medical actions (server): stabilise, revive and heal.

    Every action is one row in Med.acts[helper] and four NW2 values on the
    helper (sh_00_config.lua), set when it starts and cleared when it ends.
    The 0.1 s loop in sv_10_downed.lua checks them: helper and target still
    valid and close, kit still carried; at the end time the kit is used up
    and the effect applied. Stabilising has no end; it pauses the target's
    bleed-out until the helper stops.

    Started by the kit weapons (left click: someone else, right click:
    yourself, which takes selfMult times longer) or by the E menu on a
    downed player (med.act). The client only asks; everything is checked here.
]]

local Med = Rhylib.Medical
Med.acts = Med.acts or {}

--------------------------------------------------------------------------
-- Kits: carried in the inventory (rhylib_inventory) or as plain weapons
--------------------------------------------------------------------------

local function inventory()
    return Rhylib.Inventory and Rhylib.Inventory.Count and Rhylib.Inventory or nil
end

function Med.Has(ply, class)
    local Inv = inventory()
    if Inv then return Inv.Count(ply, class) > 0 end
    return ply:HasWeapon(class)
end

-- Uses in a full medkit: the item's (from the weapon file), else config.
local function medkitMax()
    local def = Rhylib.Items and Rhylib.Items.Get(Med.MEDKIT)
    local n = def and def.rounds or tonumber(Med.Cfg("medkitUses")) or 5
    return math.max(1, math.floor(n))
end

-- Uses up one kit (or one medkit use). Returns false if there was none.
function Med.Consume(ply, class)
    local Inv = inventory()
    local wep = ply:GetWeapon(class)
    if not Inv then
        if not IsValid(wep) then return false end
        if class == Med.MEDKIT and wep.SetUses then
            local left = wep:GetUses() - 1
            wep:SetUses(left)
            if left > 0 then return true end
        end
        ply:StripWeapon(class)
        return true
    end

    local st = Inv.Get(ply)
    local pick
    for _, o in pairs(st.byUid) do
        if o.id == class then
            -- Medkits: use the emptiest first, so full ones stay full.
            local f = o.data and o.data.fill or 1
            if not pick or f < (pick.data and pick.data.fill or 1) then pick = o end
        end
    end
    if not pick then return false end

    if class == Med.MEDKIT then
        local max = medkitMax()
        local left = math.floor((pick.data and pick.data.fill or 1) * max + 0.5) - 1
        if left > 0 then
            pick.data = pick.data or {}
            pick.data.fill = left / max
            Inv.Internal.update(ply, st, pick)
            if IsValid(wep) and wep.SetUses then wep:SetUses(left) end
            return true
        end
        Inv.Remove(ply, pick.uid)
        return true
    end
    Inv.Remove(ply, pick.uid, 1)
    return true
end

--------------------------------------------------------------------------
-- Starting and stopping
--------------------------------------------------------------------------

local function setAct(helper, kind, target, startT, endT)
    helper:SetNW2Int("rhylib_medAct", kind)
    helper:SetNW2Entity("rhylib_medT", target or NULL)
    helper:SetNW2Float("rhylib_medS", startT or 0)
    helper:SetNW2Float("rhylib_medE", endT or 0)
end

local KIT = {
    [Med.A_REVIVE] = Med.REVIVE_KIT,
    [Med.A_FA_REVIVE] = Med.FIRST_AID,
    [Med.A_FA_HEAL] = Med.FIRST_AID,
    [Med.A_MEDKIT] = Med.MEDKIT,
}

local function duration(kind, self)
    local mult = self and math.max(1, tonumber(Med.Cfg("selfMult")) or 2) or 1
    if kind == Med.A_REVIVE then return Med.Cfg("reviveKitTime") end
    if kind == Med.A_FA_REVIVE then return Med.Cfg("firstAidReviveTime") end
    if kind == Med.A_FA_HEAL then return Med.Cfg("firstAidHealTime") * mult end
    if kind == Med.A_MEDKIT then return Med.Cfg("medkitHealTime") * mult end
    return 0
end

-- Why this can't start, or nil if it can.
local function refuse(helper, kind, target)
    if not helper:Alive() or helper.rhylibDown then return "" end
    if Med.acts[helper] then return "" end
    if not (IsValid(target) and target:IsPlayer() and target:Alive()) then return "" end
    local self = target == helper
    local down = target.rhylibDown

    if kind == Med.A_STAB or kind == Med.A_REVIVE or kind == Med.A_FA_REVIVE then
        if self or not down then return "" end
    elseif kind == Med.A_FA_HEAL or kind == Med.A_MEDKIT then
        if down then return kind == Med.A_MEDKIT and "Medkits can't revive" or "" end
        if target:Health() >= target:GetMaxHealth() then return (self and "You're" or target:Nick() .. " is") .. " at full health" end
    else
        return ""
    end

    if not self and not Med.InRange(helper, target, 30) then return "Too far away" end
    if not self and not Med.CanSee(helper, target) then return "Can't reach them from here" end

    if kind == Med.A_STAB then
        if Med.StabilisedBy(target) then return "Already being stabilised" end
        return nil
    end
    -- One revive or treatment per patient at a time (no wasted kits).
    for h, a in pairs(Med.acts) do
        if a.target == target and a.kind ~= Med.A_STAB and h ~= helper then
            return (h:Nick() or "Someone") .. " is already treating them"
        end
    end
    local medicNeeded = kind ~= Med.A_MEDKIT or Med.Cfg("medkitMedicOnly")
    if medicNeeded and not Med.IsMedic(helper) then return "Only medics can do that" end
    local kit = KIT[kind]
    if not Med.Has(helper, kit) then
        if kit == Med.REVIVE_KIT then return "You have no revive kit" end
        if kit == Med.FIRST_AID then return "You have no first aid kit" end
        return "You have no medkit"
    end
end

function Med.Start(helper, kind, target)
    local why = refuse(helper, kind, target)
    if why then
        if why ~= "" then Med.Note(helper, why) end
        return false
    end
    Med.StopDrag(helper)

    local now = CurTime()
    if kind == Med.A_STAB then
        target:SetNW2Float("rhylib_downLeft", Med.TimeLeft(target))
        target:SetNW2Entity("rhylib_stabBy", helper)
        Med.acts[helper] = { kind = kind, target = target }
        setAct(helper, kind, target, now, 0)
        return true
    end

    local endT = now + duration(kind, target == helper)
    Med.acts[helper] = { kind = kind, target = target, endTime = endT }
    setAct(helper, kind, target, now, endT)
    return true
end

function Med.Cancel(helper)
    local a = Med.acts[helper]
    if not a then return end
    Med.acts[helper] = nil
    local t = a.target
    if a.kind == Med.A_STAB and IsValid(t) and t:GetNW2Entity("rhylib_stabBy") == helper then
        t:SetNW2Float("rhylib_downEnd", CurTime() + t:GetNW2Float("rhylib_downLeft", 0))
        t:SetNW2Entity("rhylib_stabBy", NULL)
    end
    if IsValid(helper) then setAct(helper, Med.A_NONE) end
end

--------------------------------------------------------------------------
-- Checks and finishing (from the loop in sv_10_downed.lua)
--------------------------------------------------------------------------

local function finishAct(helper, a)
    Med.acts[helper] = nil
    setAct(helper, Med.A_NONE)
    local t = a.target
    local kit = KIT[a.kind]
    if not Med.Consume(helper, kit) then return end

    if a.kind == Med.A_REVIVE then
        Med.Revive(t, t:GetMaxHealth() * Med.Cfg("reviveKitHealth"), helper)
    elseif a.kind == Med.A_FA_REVIVE then
        Med.Revive(t, Med.Cfg("firstAidReviveHealth"), helper)
    elseif a.kind == Med.A_FA_HEAL then
        t:SetHealth(math.max(t:Health(), t:GetMaxHealth()))
    elseif a.kind == Med.A_MEDKIT then
        t:SetHealth(math.min(t:GetMaxHealth(), t:Health() + Med.Cfg("medkitHeal")))
    end
end

function Med.CheckActions(now)
    for helper, a in pairs(Med.acts) do
        local t = a.target
        local ok = IsValid(helper) and helper:Alive() and not helper.rhylibDown
            and IsValid(t) and t:Alive()
        if ok then
            local needDown = a.kind == Med.A_STAB or a.kind == Med.A_REVIVE or a.kind == Med.A_FA_REVIVE
            ok = (t.rhylibDown and true or false) == needDown
                and (t == helper or Med.InRange(helper, t, 50))
                and (a.kind == Med.A_STAB or Med.Has(helper, KIT[a.kind]))
                and not (needDown and Med.DraggedBy(t))
        end
        if not ok then
            Med.Cancel(helper)
        elseif a.endTime and now >= a.endTime then
            finishAct(helper, a)
        end
    end
end

--------------------------------------------------------------------------
-- Requests
--------------------------------------------------------------------------

-- From a kit weapon. self = right click (treat yourself).
function Med.UseKit(ply, class, self)
    if Med.acts[ply] then return end
    if self then
        if class == Med.FIRST_AID then Med.Start(ply, Med.A_FA_HEAL, ply)
        elseif class == Med.MEDKIT then Med.Start(ply, Med.A_MEDKIT, ply) end
        return
    end

    local downed = Med.FindDowned(ply, Med.downList)
    if downed then
        if class == Med.REVIVE_KIT then Med.Start(ply, Med.A_REVIVE, downed)
        elseif class == Med.FIRST_AID then Med.Start(ply, Med.A_FA_REVIVE, downed)
        else Med.Note(ply, "Medkits can't revive") end
        return
    end
    if class == Med.REVIVE_KIT then
        Med.Note(ply, "Aim at a downed player")
        return
    end

    ply:LagCompensation(true)
    local t = Med.FindStanding(ply)
    ply:LagCompensation(false)
    if not t then
        Med.Note(ply, "Aim at a wounded player, or right click to treat yourself")
        return
    end
    Med.Start(ply, class == Med.FIRST_AID and Med.A_FA_HEAL or Med.A_MEDKIT, t)
end

-- From the E menu on a downed player: stabilise or revive with a chosen kit.
local MENU_KINDS = { [Med.A_STAB] = true, [Med.A_REVIVE] = true, [Med.A_FA_REVIVE] = true }

Rhylib.Net.Receive("med.act", function(ply)
    local kind = net.ReadUInt(Med.ACT_BITS)
    local target = Entity(net.ReadUInt(8))
    if not MENU_KINDS[kind] or not IsValid(target) or not target:IsPlayer() then return end
    Med.Start(ply, kind, target)
end, { rate = 4, burst = 4 })
