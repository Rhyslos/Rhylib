--[[
    Injuries, server side (see sh_30_injuries.lua for the model).

    Damage -> body part:
      fall damage        both legs (a hard fall breaks one)
      blast and fire     spread over the body as damage and burns
      everything else    the part that was hit (rhylib bolts tag the hit
                         group; engine bullets use LastHitGroup); torso if
                         unknown
    Once a second, only for injured players: bleeding takes health (a
    bleed that would kill downs you instead), light bleeds stop after a
    while, and parts with nothing else wrong slowly recover.
    State goes to the owner, and to anyone with the owner's H menu open
    (in range, in sight), at most once per tick, when it changes.
]]

local Med = Rhylib.Medical
local Config = Rhylib.Config
local function cfg(k) return Config.Get("medical", k) end

Med.inj = Med.inj or {}          -- [ply] = { [limb] = part }; nil when unhurt
local inj = Med.inj
local dirty = {}
Med.viewers = Med.viewers or {}  -- [patient] = { [viewer] = true }
local viewers = Med.viewers

Rhylib.Net.Register("med.inj")

local function sendTo(patient, recipients)
    Rhylib.Net.Start("med.inj")
    net.WriteEntity(patient)
    Med.WriteInjuries(inj[patient])
    net.Send(recipients)
end

-- Still allowed to look at this patient?
local function canView(viewer, patient)
    if not (IsValid(viewer) and IsValid(patient) and viewer:Alive() and patient:Alive()) then return false end
    if viewer.rhylibDown then return false end
    local r = Config.Get("medical", "viewRange") * 1.5
    if viewer:GetPos():DistToSqr(patient:GetPos()) > r * r then return false end
    return Med.CanSee(viewer, patient)
end

local function newState()
    local t = {}
    for _, l in ipairs(Med.LIMBS) do t[l] = { dmg = 0, bleed = 0, frac = false, burn = 0, bleedEnd = 0 } end
    return t
end

local function getState(ply)
    local t = inj[ply]
    if not t then
        t = newState()
        inj[ply] = t
    end
    return t
end

local function healthy(t)
    for _, l in ipairs(Med.LIMBS) do
        local p = t[l]
        if p.dmg > 0 or p.bleed > 0 or p.frac or p.burn > 0 then return false end
    end
    return true
end

-- What the owner last got, as whole numbers, so tiny changes aren't sent.
local function signature(t)
    if not t then return "" end
    local s = ""
    for _, l in ipairs(Med.LIMBS) do
        local p = t[l]
        s = s .. math.ceil(p.dmg) .. "," .. p.bleed .. "," .. (p.frac and 1 or 0) .. "," .. math.ceil(p.burn) .. ";"
    end
    return s
end

function Med.MarkInjuries(ply)
    local t = inj[ply]
    if t and healthy(t) then inj[ply] = nil end
    dirty[ply] = true
end

Rhylib.Hook.Add("Tick", "medical.injuries.send", function()
    if next(dirty) == nil then return end
    for ply in pairs(dirty) do
        dirty[ply] = nil
        if IsValid(ply) then
            local sig = signature(inj[ply])
            if sig ~= ply.rhylibInjSent then
                ply.rhylibInjSent = sig
                local list = { ply }
                local v = viewers[ply]
                if v then
                    for viewer in pairs(v) do
                        if canView(viewer, ply) then list[#list + 1] = viewer else v[viewer] = nil end
                    end
                    if next(v) == nil then viewers[ply] = nil end
                end
                sendTo(ply, list)
            end
        end
    end
end)

function Med.ClearInjuries(ply)
    if inj[ply] then
        inj[ply] = nil
        dirty[ply] = true
    end
end

--------------------------------------------------------------------------
-- Damage
--------------------------------------------------------------------------

local GROUP_LIMB = {
    [HITGROUP_HEAD] = "head",
    [HITGROUP_CHEST] = "torso", [HITGROUP_STOMACH] = "torso", [HITGROUP_GENERIC] = "torso", [HITGROUP_GEAR] = "torso",
    [HITGROUP_LEFTARM] = "larm", [HITGROUP_RIGHTARM] = "rarm",
    [HITGROUP_LEFTLEG] = "lleg", [HITGROUP_RIGHTLEG] = "rleg",
}
-- How blast and fire spread over the body.
local SPREAD = { head = 0.1, torso = 0.3, larm = 0.15, rarm = 0.15, lleg = 0.15, rleg = 0.15 }
local IS_LIMB = { larm = true, rarm = true, lleg = true, rleg = true }

local function hurt(ply, t, limb, amount, canBleed, now)
    local p = t[limb]
    p.dmg = math.min(100, p.dmg + amount)
    if canBleed then
        if amount >= cfg("heavyBleedAt") or p.dmg >= 80 then
            p.bleed = 2
        elseif amount >= cfg("lightBleedAt") and p.bleed < 1 then
            p.bleed = 1
            p.bleedEnd = now + cfg("lightBleedStops")
        end
    end
    if IS_LIMB[limb] and amount >= cfg("fractureAt") then p.frac = true end
end

Rhylib.Hook.Add("PostEntityTakeDamage", "medical.injuries", function(ply, dmg, took)
    if not took or not ply:IsPlayer() or ply.rhylibBleedTick then return end
    if not cfg("injuries") or not ply:Alive() then
        ply.rhylibHitGroup = nil
        return
    end
    local amount = dmg:GetDamage()
    if amount <= 0 then return end
    local now = CurTime()
    local t = getState(ply)
    local dtype = dmg:GetDamageType()

    if bit.band(dtype, DMG_FALL) ~= 0 then
        hurt(ply, t, "lleg", amount * 0.6, false, now)
        hurt(ply, t, "rleg", amount * 0.6, false, now)
        if amount >= cfg("fallFractureAt") then t[math.random(2) == 1 and "lleg" or "rleg"].frac = true end
    elseif bit.band(dtype, bit.bor(DMG_BLAST, DMG_BURN, DMG_SLOWBURN, DMG_PLASMA)) ~= 0 then
        for limb, share in pairs(SPREAD) do
            hurt(ply, t, limb, amount * share, false, now)
            t[limb].burn = math.min(100, t[limb].burn + amount * share)
        end
    else
        local group = ply.rhylibHitGroup or ply:LastHitGroup()
        local limb = GROUP_LIMB[group] or "torso"
        hurt(ply, t, limb, amount, bit.band(dtype, bit.bor(DMG_BULLET, DMG_SLASH, DMG_CLUB, DMG_GENERIC, DMG_BUCKSHOT, DMG_SNIPER)) ~= 0 or dtype == 0, now)
        -- Torso hits knock the wind out of you.
        if limb == "torso" and Rhylib.Stamina and Rhylib.Stamina.Drain then
            Rhylib.Stamina.Drain(ply, amount * cfg("torsoStaminaHit"))
        end
    end
    ply.rhylibHitGroup = nil
    Med.MarkInjuries(ply)
end, 50)

Rhylib.Hook.Add("PlayerSpawn", "medical.injuries", Med.ClearInjuries)
Rhylib.Hook.Add("PlayerDeath", "medical.injuries", Med.ClearInjuries)
Rhylib.Hook.Add("PlayerSilentDeath", "medical.injuries", Med.ClearInjuries)
Rhylib.Hook.Add("PlayerDisconnected", "medical.injuries", function(ply)
    inj[ply] = nil
    dirty[ply] = nil
    viewers[ply] = nil
    for _, v in pairs(viewers) do v[ply] = nil end
end)

-- Opening (or closing, with no patient) someone's injury menu.
Rhylib.Net.Receive("med.view", function(ply)
    local patient = net.ReadEntity()
    for p, v in pairs(viewers) do
        v[ply] = nil
        if next(v) == nil then viewers[p] = nil end
    end
    if not (IsValid(patient) and patient:IsPlayer() and patient ~= ply) then return end
    local r = Config.Get("medical", "viewRange")
    if not ply:Alive() or ply.rhylibDown or ply:GetPos():DistToSqr(patient:GetPos()) > r * r or not Med.CanSee(ply, patient) then return end
    viewers[patient] = viewers[patient] or {}
    viewers[patient][ply] = true
    sendTo(patient, ply)  -- what they look like now
end, { rate = 4, burst = 4 })

--------------------------------------------------------------------------
-- Bleeding and recovery (once a second, injured players only)
--------------------------------------------------------------------------

local function bleedDamage(ply, amount)
    local hp = ply:Health()
    if hp - amount >= 1 then
        ply:SetHealth(math.floor(hp - amount + 0.5))
        return
    end
    -- Would bleed to death: a real hit, so rhylib_medical downs them.
    ply.rhylibBleedTick = true
    local d = DamageInfo()
    d:SetDamage(amount)
    d:SetDamageType(DMG_DIRECT)
    d:SetAttacker(game.GetWorld())
    d:SetInflictor(game.GetWorld())
    ply:TakeDamageInfo(d)
    ply.rhylibBleedTick = nil
end

timer.Create("Rhylib.Medical.Injuries", 1, 0, function()
    if next(inj) == nil then return end
    local now = CurTime()
    local light, heavy = cfg("lightBleed"), cfg("heavyBleed")
    local rec, burnRec = cfg("recover"), cfg("burnRecover")
    for ply, t in pairs(inj) do
        if not IsValid(ply) then
            inj[ply] = nil
        elseif ply:Alive() then
            local loss = 0
            for _, l in ipairs(Med.LIMBS) do
                local p = t[l]
                if p.bleed == 1 and now >= p.bleedEnd then p.bleed = 0 end
                if p.bleed == 1 then loss = loss + light elseif p.bleed == 2 then loss = loss + heavy end
                if p.burn > 0 then p.burn = math.max(0, p.burn - burnRec) end
                if p.bleed == 0 and not p.frac and p.burn <= 0 and p.dmg > 0 then
                    p.dmg = math.max(0, p.dmg - rec)
                end
            end
            -- Bleeding while down is the bleed-out timer's job.
            if loss > 0 and not ply.rhylibDown then
                -- Keep the fraction so slow bleeds still add up.
                ply.rhylibBleedAcc = (ply.rhylibBleedAcc or 0) + loss
                local whole = math.floor(ply.rhylibBleedAcc)
                if whole >= 1 then
                    ply.rhylibBleedAcc = ply.rhylibBleedAcc - whole
                    bleedDamage(ply, whole)
                end
            end
            Med.MarkInjuries(ply)
        end
    end
end)

--------------------------------------------------------------------------
-- Treatment from the H menu
--------------------------------------------------------------------------

Med.TREAT_FIRSTAID, Med.TREAT_MEDKIT = 0, 1

-- treater drags a kit onto patient's body part (patient may be treater).
Rhylib.Net.Receive("med.treat", function(ply)
    local patient = net.ReadEntity()
    local limb = Med.LIMBS[net.ReadUInt(3)]
    local kind = net.ReadUInt(1)
    if not limb or not ply:Alive() or ply.rhylibDown then return end
    if not (IsValid(patient) and patient:IsPlayer() and patient:Alive()) then return end
    if patient ~= ply then
        local r = cfg("viewRange")
        if ply:GetPos():DistToSqr(patient:GetPos()) > r * r or not Med.CanSee(ply, patient) then
            Med.Note(ply, "Too far away")
            return
        end
    end
    if (ply.rhylibTreatNext or 0) > CurTime() then return end
    local t = inj[patient]
    local p = t and t[limb]
    local name = Med.LIMB_NAMES[limb]
    if not p or (p.dmg <= 0 and p.bleed == 0 and not p.frac and p.burn <= 0) then
        Med.Note(ply, name .. ": nothing to treat")
        return
    end
    local medic = Med.IsMedic(ply)

    if kind == Med.TREAT_FIRSTAID then
        if not medic then
            Med.Note(ply, "Only medics can use a first aid kit")
            return
        end
        if not Med.Consume(ply, Med.FIRST_AID) then
            Med.Note(ply, "You have no first aid kit")
            return
        end
        p.dmg, p.bleed, p.frac, p.burn = 0, 0, false, 0
        patient:SetHealth(math.min(patient:GetMaxHealth(), patient:Health() + cfg("firstAidLimbHealth")))
        Med.Note(ply, name .. " treated")
    else
        -- Troopers can only stop bleeding; medics also heal damage and burns.
        local canBleed = p.bleed > 0
        local canHeal = medic and (p.dmg > 0 or p.burn > 0)
        if not canBleed and not canHeal then
            Med.Note(ply, medic and "A medkit can't set bones; use a first aid kit" or "Only medics can treat that (medkits stop bleeding)")
            return
        end
        if not Med.Consume(ply, Med.MEDKIT) then
            Med.Note(ply, "You have no medkit")
            return
        end
        p.bleed = 0
        if medic then
            local r = cfg("medkitLimbRepair")
            p.dmg = math.max(0, p.dmg - r)
            p.burn = math.max(0, p.burn - r)
            patient:SetHealth(math.min(patient:GetMaxHealth(), patient:Health() + cfg("medkitHeal")))
        end
        Med.Note(ply, name .. (medic and " patched up" or ": bleeding stopped"))
    end
    patient:EmitSound("items/medshot4.wav", 60)
    ply.rhylibTreatNext = CurTime() + cfg("treatCooldown")
    Med.MarkInjuries(patient)
end, { rate = 4, burst = 4 })
