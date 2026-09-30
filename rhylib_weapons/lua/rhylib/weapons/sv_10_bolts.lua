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

    Rockets are bolts too (weapon.Explosive set): slower, longer lived,
    and they do blast damage where they hit instead of a direct hit.
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

-- Rockets: blast damage and an explosion where they hit.
local function explode(bolt, pos, normal)
    local owner = bolt.owner
    local attacker = IsValid(owner) and owner or game.GetWorld()
    local inflictor = IsValid(bolt.weapon) and bolt.weapon or attacker
    local ex = bolt.explosive
    local at = pos + normal * 4  -- just off the surface, so walls don't eat the blast
    util.BlastDamage(inflictor, attacker, at, ex.radius, ex.damage)

    local ed = EffectData()
    ed:SetOrigin(at)
    ed:SetNormal(normal)
    ed:SetMagnitude(1)
    ed:SetScale(1)
    util.Effect("Explosion", ed, true, true)
end

local function applyHit(bolt, tr)
    if bolt.onHit then
        bolt.onHit(bolt, tr)  -- special bolts (the grapple hook) handle their own hits
        return
    end
    if bolt.explosive then
        explode(bolt, tr.HitPos, tr.HitNormal)
        return
    end
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

-- player.GetHumans() builds a new table each call. Build it once per tick,
-- not once per shot (a firefight can be dozens of shots in one tick).
local humans, humansTick = {}, -1
local function getHumans()
    local tick = engine.TickCount()
    if tick ~= humansTick then
        humans, humansTick = player.GetHumans(), tick
    end
    return humans
end

local function sendShot(owner, color, origin, dir, speed)
    local range = Config.Get("weapons", "shotRange")
    local rangeSqr = range * range
    local sp = game.SinglePlayer()  -- in singleplayer the client doesn't predict, so the owner needs it too
    local item = {
        shooter = owner:EntIndex(),
        origin = origin,
        dir = dir,
        speed = math.min(speed, 16383),
        color = color,
    }
    local list = getHumans()
    for i = 1, #list do
        local ply = list[i]
        if IsValid(ply) and (ply ~= owner or sp) and ply:GetPos():DistToSqr(origin) < rangeSqr then
            shotBatch:Send(ply, item)
        end
    end
end

-- Called from the weapon's PrimaryAttack on the server.
-- opts (optional): speed, color, life, onHit(bolt, tr), onExpire(bolt)
-- override the weapon's own bolt settings (used by the grapple hook).
function Bolts.Fire(owner, weapon, origin, dir, damage, opts)
    local speed = opts and opts.speed or weapon.BoltSpeed
    local bolt = {
        owner = owner,
        weapon = weapon,
        pos = origin,
        dir = dir,
        speed = speed,
        damage = damage or weapon.Damage,
        die = CurTime() + (opts and opts.life or weapon.BoltLife or Config.Get("weapons", "boltLife")),
        explosive = weapon.Explosive,
        onHit = opts and opts.onHit,
        onExpire = opts and opts.onExpire,
    }

    sendShot(owner, opts and opts.color or weapon.BoltColor or 1, origin, dir, speed)

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

    -- Two position vectors per bolt, swapped each tick, plus a fixed step,
    -- so the tick loop below allocates no vectors.
    bolt.pos = Vector(tr.HitPos)
    bolt.nextPos = Vector()
    bolt.step = dir * (speed * engine.TickInterval())
    Bolts.active[#Bolts.active + 1] = bolt
end

Rhylib.Hook.Add("Tick", "weapons.bolts", function()
    local list = Bolts.active
    if #list == 0 then return end

    local now = CurTime()
    local i = 1
    while i <= #list do
        local b = list[i]
        local remove = now > b.die or not b.step  -- (bolts from before an autorefresh)
        if remove and b.onExpire and b.step then b.onExpire(b) end

        if not remove then
            local to = b.nextPos
            to:Set(b.pos)
            to:Add(b.step)
            local owner = b.owner
            local tr = trace(b.pos, to, IsValid(owner) and owner or nil)
            if tr.Hit then
                applyHit(b, tr)
                remove = true
            else
                b.nextPos, b.pos = b.pos, to
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
