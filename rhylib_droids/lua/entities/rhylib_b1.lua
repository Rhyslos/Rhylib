--[[
    B1 battle droid: a NextBot with an E-5. See rhylib/droids/sh_00_config.lua.

    Behaviour (one coroutine): look for a target a few times a second;
    with one, turn to it, wait the reaction time, then fire short bursts
    with pauses, advancing now and then if far. When it loses sight it goes
    to where it last saw the target, then wanders near home.
]]

AddCSLuaFile()

ENT.Base = "base_nextbot"
ENT.Type = "nextbot"
ENT.PrintName = "B1 battle droid"
ENT.Category = "Rhylib Droids"
ENT.Spawnable = false   -- spawned from the NPCs tab (list "NPC")
ENT.AdminOnly = true
ENT.IsRhylibDroid = true

-- Animations: the first activity the model has, from player-model sets
-- (ACT_HL2MP_*) to NPC sets. Worked out once per model (anims[model]).
local CHOICES = {
    idle = { ACT_HL2MP_IDLE_AR2, ACT_HL2MP_IDLE_SMG1, ACT_IDLE_ANGRY_SMG1, ACT_IDLE_SMG1, ACT_IDLE_RIFLE, ACT_IDLE_ANGRY, ACT_IDLE },
    walk = { ACT_HL2MP_WALK_AR2, ACT_HL2MP_WALK_SMG1, ACT_WALK_AIM_RIFLE, ACT_WALK_RIFLE, ACT_WALK },
    run = { ACT_HL2MP_RUN_AR2, ACT_HL2MP_RUN_SMG1, ACT_RUN_AIM_RIFLE, ACT_RUN_RIFLE, ACT_RUN },
    shoot = { ACT_HL2MP_GESTURE_RANGE_ATTACK_AR2, ACT_HL2MP_GESTURE_RANGE_ATTACK_SMG1, ACT_GESTURE_RANGE_ATTACK_SMG1, ACT_GESTURE_RANGE_ATTACK_AR2 },
}
local anims = {}

local function resolveAnims(ent)
    local mdl = ent:GetModel() or ""
    local a = anims[mdl]
    if a then return a end
    a = {}
    for key, list in pairs(CHOICES) do
        for _, act in ipairs(list) do
            if act and ent:SelectWeightedSequence(act) > 0 then a[key] = act break end
        end
    end
    -- Nothing usable for walking/running: reuse what there is.
    a.idle = a.idle or ACT_IDLE
    a.walk = a.walk or a.run or a.idle
    a.run = a.run or a.walk
    anims[mdl] = a
    if SERVER then
        Rhylib.Print("droids", "%s: %d sequences; idle=%s walk=%s run=%s shoot=%s", mdl, ent:GetSequenceCount(),
            tostring(ent:GetSequenceActivityName(ent:SelectWeightedSequence(a.idle))),
            tostring(ent:GetSequenceActivityName(ent:SelectWeightedSequence(a.walk))),
            tostring(ent:GetSequenceActivityName(ent:SelectWeightedSequence(a.run))),
            a.shoot and "yes" or "none")
        if ent:SelectWeightedSequence(a.idle) <= 0 then
            Rhylib.Warn("droids", "%s has no usable animations (is it a ragdoll-only model?)", mdl)
        end
    end
    return a
end

local EYE = Vector(0, 0, 62)
local ADVANCE_DIST = 1400     -- further than this: move closer between bursts

function ENT:Initialize()
    local D = Rhylib.Droids
    self:SetModel(D.B1_MODEL)
    if CLIENT then return end

    -- Over the cap: don't add another.
    if D.Count() >= D.Cfg("maxActive") then
        timer.Simple(0, function() if IsValid(self) then self:Remove() end end)
        return
    end
    D.active[self] = true

    self:SetHealth(D.Cfg("b1Health"))
    self:SetMaxHealth(D.Cfg("b1Health"))
    self:SetCollisionBounds(Vector(-13, -13, 0), Vector(13, 13, 72))
    self.loco:SetDesiredSpeed(D.Cfg("b1Speed"))
    self.loco:SetAcceleration(500)
    self.loco:SetDeceleration(800)
    self.loco:SetStepHeight(18)
    self.loco:SetJumpHeight(40)
    self.home = self:GetPos()
    self.nextLook = 0
    self.anims = resolveAnims(self)
    self:StartActivity(self.anims.idle)
end

if SERVER then
    local D = Rhylib.Droids

    function ENT:OnRemove()
        D.active[self] = nil
    end

    --------------------------------------------------------------------------
    -- Seeing
    --------------------------------------------------------------------------

    local tr = {}
    local trData = { mask = MASK_SHOT, output = tr }

    function ENT:CanSee(t)
        trData.start = self:GetPos() + EYE
        trData.endpos = t:EyePos()
        trData.filter = self
        util.TraceLine(trData)
        return not tr.Hit or tr.Entity == t
    end

    -- Closest visible target in range, checked at most every 0.3 s.
    function ENT:Look()
        local now = CurTime()
        if now < self.nextLook then return self.target end
        self.nextLook = now + 0.3 + math.Rand(0, 0.1)   -- spread droids over ticks
        local range = D.Cfg("b1Range")
        local pos = self:GetPos()
        local best, bestD
        for _, p in ipairs(D.Targets()) do
            local d = p:GetPos():DistToSqr(pos)
            if d < range * range and (not bestD or d < bestD) and self:CanSee(p) then
                best, bestD = p, d
            end
        end
        if best then
            if self.target ~= best then self.reactUntil = now + D.Cfg("b1Reaction") * math.Rand(0.8, 1.3) end
            self.target = best
            self.lastSeen = best:GetPos()
            self.lastSeenAt = now
        elseif IsValid(self.target) and not self.target:Alive() then
            self.target = nil
        end
        return best
    end

    -- Shot at by a player it hadn't seen: turn toward them.
    function ENT:OnInjured(dmg)
        local att = dmg:GetAttacker()
        if IsValid(att) and att:IsPlayer() and not IsValid(self.target) then
            self.lastSeen = att:GetPos()
            self.lastSeenAt = CurTime()
            self.nextLook = 0
        end
    end

    function ENT:OnKilled(dmg)
        hook.Run("OnNPCKilled", self, dmg:GetAttacker(), dmg:GetInflictor())
        local ed = EffectData()
        ed:SetOrigin(self:WorldSpaceCenter())
        ed:SetMagnitude(2)
        ed:SetScale(1)
        ed:SetRadius(4)
        util.Effect("Sparks", ed)
        self:EmitSound("npc/turret_floor/die.wav", 75, math.random(95, 110))
        self:BecomeRagdoll(dmg)   -- a client-side ragdoll (ai_serverragdolls 0)
    end

    --------------------------------------------------------------------------
    -- Shooting
    --------------------------------------------------------------------------

    function ENT:Muzzle()
        local b = self:LookupBone("ValveBiped.Bip01_R_Hand")
        local pos = b and self:GetBonePosition(b)
        if not pos then return self:GetPos() + EYE end
        return pos + self:GetForward() * 18 + Vector(0, 0, 2)
    end

    function ENT:FireAt(t)
        local Bolts = Rhylib.Weapons and Rhylib.Weapons.Bolts
        if not Bolts then return end
        local origin = self:Muzzle()
        local aim = t:WorldSpaceCenter() + Vector(0, 0, 8)   -- chest
        local dir = aim - origin
        dir:Normalize()
        -- Inaccuracy: base cone, worse against moving targets.
        local cone = math.rad((D.Cfg("e5Spread") + t:GetVelocity():Length2D() * 0.006) * D.SuppressMult(self))
        local a = math.Rand(0, math.pi * 2)
        local r = math.tan(cone * math.sqrt(math.Rand(0, 1)))
        local ang = dir:Angle()
        dir = dir + ang:Right() * math.cos(a) * r + ang:Up() * math.sin(a) * r
        dir:Normalize()
        Bolts.Fire(self, D.E5(), origin, dir, D.Cfg("e5Damage"))
        self:EmitSound(D.E5_SOUND, 80, math.random(108, 118), 0.8, CHAN_WEAPON)
        if self.anims.shoot then self:RestartGesture(self.anims.shoot, true, true) end
    end

    --------------------------------------------------------------------------
    -- Moving
    --------------------------------------------------------------------------

    -- Walk a path for up to maxTime; stop early when a target shows up (watch).
    function ENT:Go(pos, maxTime, watch)
        local path = Path("Follow")
        path:SetMinLookAheadDistance(300)
        path:SetGoalTolerance(40)
        if not path:Compute(self, pos) then return false end
        local stop = CurTime() + maxTime
        while path:IsValid() and CurTime() < stop do
            path:Update(self)
            if self.loco:IsStuck() then
                self:HandleStuck()
                return false
            end
            if watch and self:Look() then return true end
            coroutine.yield()
        end
        return true
    end

    -- Turn to face a point for up to t seconds.
    function ENT:Face(pos, t)
        local stop = CurTime() + t
        while CurTime() < stop do
            self.loco:FaceTowards(pos)
            coroutine.yield()
        end
    end

    function ENT:Engage()
        local t = self.target
        local bursts = 0
        while IsValid(t) and t:Alive() and not t.rhylibDown do
            self:Look()
            if self.target ~= t then
                t = self.target
                if not IsValid(t) then break end
            end
            if CurTime() - (self.lastSeenAt or 0) > 1.5 then break end  -- lost sight

            self:Face(t:GetPos(), 0.15)
            if CurTime() >= (self.reactUntil or 0) then
                -- A burst of 3-5.
                local wait = 60 / math.max(D.Cfg("e5RPM"), 1)
                for _ = 1, math.random(3, 5) do
                    if not (IsValid(t) and t:Alive()) or not self:CanSee(t) then break end
                    self.loco:FaceTowards(t:GetPos())
                    self:FireAt(t)
                    self:Face(t:GetPos(), wait)
                end
                bursts = bursts + 1
                self:Face(IsValid(t) and t:GetPos() or self:GetPos(), math.Rand(0.6, 1.3))
                -- Far away: walk a bit closer every few bursts.
                if IsValid(t) and bursts % 3 == 0 and t:GetPos():DistToSqr(self:GetPos()) > ADVANCE_DIST * ADVANCE_DIST then
                    local toward = self:GetPos() + (t:GetPos() - self:GetPos()):GetNormalized() * 400
                    self:Go(toward, 1.5, false)
                end
            end
        end
        self.target = nil
    end

    function ENT:RunBehaviour()
        while true do
            if self:Look() then
                self:Engage()
            elseif self.lastSeen and CurTime() - (self.lastSeenAt or 0) < 20 then
                -- Go where the target was last seen (or where the shot came from).
                local pos = self.lastSeen
                self.lastSeen = nil
                self:Go(pos, 8, true)
            elseif math.random() < 0.35 then
                -- Wander near home.
                local pos = self.home + Vector(math.Rand(-350, 350), math.Rand(-350, 350), 0)
                self:Go(pos, 5, true)
                if not self.target then coroutine.wait(math.Rand(2, 4)) end
            else
                coroutine.wait(math.Rand(1, 2))
            end
            coroutine.yield()
        end
    end

    --------------------------------------------------------------------------
    -- Animation
    --------------------------------------------------------------------------

    function ENT:BodyUpdate()
        local speed = self.loco:GetVelocity():Length2D()
        local A = self.anims
        if not A then return end   -- removed at once (over the cap)
        local want = speed > 10 and (speed > 110 and A.run or A.walk) or A.idle
        if self:GetActivity() ~= want then self:StartActivity(want) end

        -- Aim the gun at the target.
        local t = self.target
        if IsValid(t) then
            local ang = (t:WorldSpaceCenter() - (self:GetPos() + EYE)):Angle()
            self:SetPoseParameter("aim_yaw", math.Clamp(math.NormalizeAngle(ang.y - self:GetAngles().y), -60, 60))
            self:SetPoseParameter("aim_pitch", math.Clamp(math.NormalizeAngle(ang.p), -50, 50))
        else
            self:SetPoseParameter("aim_yaw", 0)
            self:SetPoseParameter("aim_pitch", 0)
        end

        if speed > 10 then self:BodyMoveXY() else self:FrameAdvance() end
    end
end

if CLIENT then
    -- One shared E-5 model, moved to each droid's hand when drawn.
    local gun
    local handBone = {}
    local POS, ANG = Vector(5, 1, -3), Angle(-10, 0, 180)   -- like the clone guns

    local function place(pos, ang)
        local p = pos + ang:Forward() * POS.x + ang:Right() * POS.y + ang:Up() * POS.z
        local a = Angle(ang.p, ang.y, ang.r)
        a:RotateAroundAxis(a:Up(), ANG.y)
        a:RotateAroundAxis(a:Right(), ANG.p)
        a:RotateAroundAxis(a:Forward(), ANG.r)
        return p, a
    end

    function ENT:Draw()
        self:DrawModel()
        if not IsValid(gun) then
            gun = ClientsideModel(Rhylib.Droids.E5_MODEL, RENDERGROUP_OPAQUE)
            if not IsValid(gun) then return end
            gun:SetNoDraw(true)
        end
        local mdl = self:GetModel()
        local b = handBone[mdl]
        if b == nil then
            b = self:LookupBone("ValveBiped.Bip01_R_Hand") or false
            handBone[mdl] = b
        end
        local m = b and self:GetBoneMatrix(b)
        if not m then return end
        local p, a = place(m:GetTranslation(), m:GetAngles())
        gun:SetPos(p)
        gun:SetAngles(a)
        gun:SetupBones()
        gun:DrawModel()
    end
end
