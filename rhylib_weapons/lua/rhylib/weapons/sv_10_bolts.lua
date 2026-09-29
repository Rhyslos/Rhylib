--[[
    Server bolt simulation.

    A bolt is a row in one Lua table, never an entity. One Tick handler
    moves all bolts and does one line trace per bolt per tick.

    Hit registration:
      1. First leg: the server rewinds other players to what the shooter
         saw (lag compensation) and traces the distance the bolt covered
         during the shooter's ping, capped by weapons.lagCompMax.
      2. The rest of the flight runs in real time, tick by tick.

    Other players get one small "shot" event (batched per tick) and draw
    the bolt themselves. The shooter's own client already drew it.
]]

local W = Rhylib.Weapons
W.Bolts = W.Bolts or {}
local Bolts = W.Bolts
Bolts.active = Bolts.active or {}

local Config = Rhylib.Config

local shotBatch = Rhylib.Net.CreateBatch("wep.shot", function(s)
    net.WriteUInt(s.shooter, 13)
    net.WriteVector(s.origin)
    net.WriteNormal(s.dir)
    net.WriteUInt(s.speed, 14)
    net.WriteUInt(s.color, 4)
end)

local hitBatch = Rhylib.Net.CreateBatch("wep.hit", function(h)
    net.WriteBool(h.head)
end)

local LIMBS = {
    [HITGROUP_LEFTARM] = true,
    [HITGROUP_RIGHTARM] = true,
    [HITGROUP_LEFTLEG] = true,
    [HITGROUP_RIGHTLEG] = true,
}

-- Reused for every trace so the bolt loop creates no garbage.
local traceResult = {}
local traceData = { mask = MASK_SHOT, output = traceResult }

local function trace(from, to, filter)
    traceData.start = from
    traceData.endpos = to
    traceData.filter = filter
    return util.TraceLine(traceData)
end

local function applyHit(bolt, tr)
    local ent = tr.Entity
    if not IsValid(ent) then return end

    local mult = 1
    if tr.HitGroup == HITGROUP_HEAD then
        mult = Config.Get("weapons", "headMult")
    elseif LIMBS[tr.HitGroup] then
        mult = Config.Get("weapons", "limbMult")
    end

    local owner = bolt.owner
    local attacker = IsValid(owner) and owner or game.GetWorld()

    local dmg = DamageInfo()
    dmg:SetDamage(bolt.damage * mult)
    dmg:SetAttacker(attacker)
    dmg:SetInflictor(IsValid(bolt.weapon) and bolt.weapon or attacker)
    dmg:SetDamageType(DMG_BULLET)
    dmg:SetDamagePosition(tr.HitPos)
    dmg:SetDamageForce(bolt.dir * bolt.damage * 60)
    ent:TakeDamageInfo(dmg)

    if IsValid(owner) and owner:IsPlayer() and (ent:IsPlayer() or ent:IsNPC() or ent:IsNextBot()) then
        hitBatch:Send(owner, { head = tr.HitGroup == HITGROUP_HEAD })
    end
end

local function sendShot(owner, weapon, origin, dir, speed)
    local range = Config.Get("weapons", "shotRange")
    local rangeSqr = range * range
    local sp = game.SinglePlayer()  -- in singleplayer the client doesn't predict, so the owner needs it too
    local item = {
        shooter = owner:EntIndex(),
        origin = origin,
        dir = dir,
        speed = math.min(speed, 16383),
        color = weapon.BoltColor or 1,
    }
    for _, ply in ipairs(player.GetHumans()) do
        if (ply ~= owner or sp) and ply:GetPos():DistToSqr(origin) < rangeSqr then
            shotBatch:Send(ply, item)
        end
    end
end

-- Called from the weapon's PrimaryAttack on the server.
function Bolts.Fire(owner, weapon, origin, dir)
    local speed = weapon.BoltSpeed
    local bolt = {
        owner = owner,
        weapon = weapon,
        pos = origin,
        dir = dir,
        speed = speed,
        damage = weapon.Damage,
        die = CurTime() + Config.Get("weapons", "boltLife"),
    }

    sendShot(owner, weapon, origin, dir, speed)

    local isPly = owner:IsPlayer()
    local lag = isPly and math.min(owner:Ping() / 1000, Config.Get("weapons", "lagCompMax")) or 0
    local firstLeg = speed * math.max(lag, engine.TickInterval())

    if isPly then owner:LagCompensation(true) end
    local tr = trace(origin, origin + dir * firstLeg, owner)
    if isPly then owner:LagCompensation(false) end

    if tr.Hit then
        applyHit(bolt, tr)
        return
    end

    bolt.pos = tr.HitPos
    Bolts.active[#Bolts.active + 1] = bolt
end

Rhylib.Hook.Add("Tick", "weapons.bolts", function()
    local list = Bolts.active
    if #list == 0 then return end

    local step = engine.TickInterval()
    local now = CurTime()
    local i = 1
    while i <= #list do
        local b = list[i]
        local remove = now > b.die

        if not remove then
            local to = b.pos + b.dir * (b.speed * step)
            local tr = trace(b.pos, to, IsValid(b.owner) and b.owner or nil)
            if tr.Hit then
                applyHit(b, tr)
                remove = true
            else
                b.pos = to
            end
        end

        if remove then
            list[i] = list[#list]
            list[#list] = nil
        else
            i = i + 1
        end
    end
end)
