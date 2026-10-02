--[[
    A thrown grenade (spawned by rhylib_grenade_base). kind:
      fuse    explodes `fuse` seconds after the throw
      impact  explodes on its first hit (armed after a moment, so it
              can't go off in the thrower's hand)
      emp     fuse; kills Rhylib droids (Rhylib.Droids.active) in range
              and in sight, stuns players there (rhylib_mp MP.Stun), no
              damage to anything else
    Blinks (red, blue for EMP) faster as the fuse runs down.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Grenade"
ENT.Spawnable = false

local KIND = { fuse = 1, impact = 2, emp = 3 }

ENT.Radius = 300        -- frag: blast radius
ENT.Damage = 140        -- frag: damage at the centre
ENT.EmpRadius = 380     -- EMP: droids within this

-- Where the grenade really is: the ball's centre.
function ENT:Centre()
    return self:GetPos()
end

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "Kind")
    self:NetworkVar("Float", 0, "Boom")   -- when the fuse ends (0 = impact)
    self:NetworkVar("Bool", 0, "Ball")    -- physics is a plain ball (the model has no collision mesh)
    self:NetworkVar("Float", 1, "Radius") -- the ball's radius
    self:NetworkVar("Vector", 0, "Offset") -- where the grenade sits in the model (its collision mesh centre)
end

if SERVER then
    function ENT:Initialize()
        self:SetModel("models/jajoff/sps/cgiweapons/tc13j/thermalgrenade.mdl")
        -- The model's bounds are far bigger than the grenade, and its own
        -- collision mesh bounces like a cylinder. So: measure that mesh,
        -- then use a ball of its size at its centre (the model is drawn
        -- around the ball, client side).
        local c, r = Vector(0, 0, 0), 3
        self:PhysicsInit(SOLID_VPHYSICS)
        local mesh = self:GetPhysicsObject()
        if IsValid(mesh) then
            local mn, mx = mesh:GetAABB()
            c = (mn + mx) * 0.5
            local size = mx - mn
            r = math.Clamp(math.max(size.x, size.y, size.z) * 0.5, 1.5, 6)
        end
        self:SetOffset(c)
        self:PhysicsInitSphere(r, "metal")
        self:SetBall(true)
        self:SetRadius(r)
        self:SetCollisionGroup(COLLISION_GROUP_PROJECTILE)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then
            phys:SetMass(2)
            phys:SetDamping(0.2, 2)
            phys:Wake()
        end
        local k = KIND[self.kind or "fuse"] or 1
        self:SetKind(k)
        self:SetBoom(k == 2 and 0 or CurTime() + (self.fuse or 3))
        self.armed = CurTime() + 0.15
        self.dieAt = CurTime() + 20   -- an impact one that never hits anything
    end

    function ENT:PhysicsCollide(data)
        if data.Speed > 120 and (self.nextBounce or 0) < CurTime() then
            self.nextBounce = CurTime() + 0.1
            self:EmitSound("physics/metal/metal_grenade_impact_hard" .. math.random(1, 3) .. ".wav", 70)
        end
        -- Can't remove inside the physics callback: blow up on the next think.
        if self:GetKind() == 2 and CurTime() >= self.armed and data.HitEntity ~= self.thrower then
            self.boomNow = true
            self:NextThink(CurTime())
        end
    end

    function ENT:Think()
        local boom = self:GetBoom()
        if self.boomNow or (boom > 0 and CurTime() >= boom) then
            self:Explode()
            return
        end
        if CurTime() > self.dieAt then self:Remove() return end
        self:NextThink(CurTime() + 0.05)
        return true
    end

    function ENT:Explode()
        if self.done then return end
        self.done = true
        local pos = self:Centre()
        local attacker = IsValid(self.thrower) and self.thrower or self
        if self:GetKind() == 3 then
            self:Emp(pos, attacker)
        else
            local ed = EffectData()
            ed:SetOrigin(pos)
            util.Effect("Explosion", ed, true, true)
            util.BlastDamage(self, attacker, pos, self.Radius, self.Damage)
            util.ScreenShake(pos, 6, 120, 0.8, self.Radius * 2)
            util.Decal("Scorch", pos + Vector(0, 0, 8), pos - Vector(0, 0, 40), self)
        end
        self:Remove()
    end

    function ENT:Emp(pos, attacker)
        local ed = EffectData()
        ed:SetOrigin(pos)
        ed:SetRadius(self.EmpRadius)
        ed:SetFlags(0)
        util.Effect("rhylib_emp", ed, true, true)
        sound.Play("ambient/energy/whiteflash.wav", pos, 85, 110)
        sound.Play("ambient/energy/zap" .. math.random(1, 9) .. ".wav", pos, 80, 100)

        local r2 = self.EmpRadius * self.EmpRadius
        -- Players in range and in sight are stunned (rhylib_mp's stun,
        -- thrower included), with a zap on them.
        local MP = Rhylib.MP
        if MP and MP.Stun then
            for _, p in ipairs(player.GetAll()) do
                if p:Alive() then
                    local c = p:WorldSpaceCenter()
                    if c:DistToSqr(pos) <= r2 and not util.TraceLine({ start = pos, endpos = c, mask = MASK_SOLID_BRUSHONLY }).Hit then
                        local zap = EffectData()
                        zap:SetOrigin(c)
                        zap:SetFlags(1)
                        util.Effect("rhylib_emp", zap, true, true)
                        MP.Stun(p, attacker)
                    end
                end
            end
        end

        local D = Rhylib.Droids
        for droid in pairs(D and D.active or {}) do
            if IsValid(droid) and droid:Health() > 0 then
                local c = droid:WorldSpaceCenter()
                if c:DistToSqr(pos) <= r2 then
                    local tr = util.TraceLine({ start = pos, endpos = c, mask = MASK_SOLID_BRUSHONLY })
                    if not tr.Hit then
                        local zap = EffectData()
                        zap:SetOrigin(c)
                        zap:SetEntity(droid)
                        zap:SetFlags(1)
                        util.Effect("rhylib_emp", zap, true, true)
                        local dmg = DamageInfo()
                        dmg:SetDamage(droid:Health() + 100)
                        dmg:SetDamageType(DMG_SHOCK)
                        dmg:SetAttacker(attacker)
                        dmg:SetInflictor(self)
                        dmg:SetDamagePosition(c)
                        droid:TakeDamageInfo(dmg)
                    end
                end
            end
        end
    end
end

if CLIENT then
    -- rhylib_grenade_debug 1: draws the physics ball (green), the model's
    -- bounds (yellow), its origin (axes) and Centre() (white); prints the
    -- numbers once per grenade.
    local debugVar = CreateClientConVar("rhylib_grenade_debug", "0", false, false, "Show grenade physics and model bounds")

    function ENT:DrawDebug(prop)
        if not debugVar:GetBool() then return end
        render.SetColorMaterial()
        local r = self:GetRadius()
        if r > 0 then render.DrawWireframeSphere(self:GetPos(), r, 12, 12, Color(0, 255, 0), true) end
        local e = IsValid(prop) and prop or self
        local mins, maxs = e:GetModelBounds()
        render.DrawWireframeBox(e:GetPos(), e:GetAngles(), mins, maxs, Color(255, 220, 0), true)
        local o, a = e:GetPos(), e:GetAngles()
        render.DrawLine(o, o + a:Forward() * 6, Color(255, 0, 0), true)
        render.DrawLine(o, o + a:Right() * 6, Color(0, 255, 0), true)
        render.DrawLine(o, o + a:Up() * 6, Color(0, 120, 255), true)
        render.DrawSphere(self:Centre(), 0.6, 8, 8, Color(255, 255, 255))
        if not self.debugPrinted then
            self.debugPrinted = true
            local size = maxs - mins
            local off = self:GetOffset()
            print(string.format("[Rhylib] grenade model %s\n  bounds mins (%.2f %.2f %.2f) maxs (%.2f %.2f %.2f)\n  size (%.2f %.2f %.2f), collision mesh centre (%.2f %.2f %.2f), ball radius %.2f",
                self:GetModel(), mins.x, mins.y, mins.z, maxs.x, maxs.y, maxs.z, size.x, size.y, size.z,
                off.x, off.y, off.z, r))
        end
    end

    function ENT:OnRemove()
        if IsValid(self.prop) then self.prop:Remove() end
    end

    local GLOW = Material("sprites/light_glow02_add")

    -- With a ball, the model (origin off to one side) is drawn centred on
    -- it with its own client model.
    function ENT:Draw()
        if not self:GetBall() then
            self:DrawModel()
        else
            local e = self.prop
            if not IsValid(e) then
                e = ClientsideModel(self:GetModel(), RENDERGROUP_OPAQUE)
                if not IsValid(e) then return end
                e:SetNoDraw(true)
                self.prop = e
            end
            e:SetColor(self:GetColor())
            e:SetPos(self:LocalToWorld(-self:GetOffset()))
            e:SetAngles(self:GetAngles())
            e:SetupBones()
            e:DrawModel()
        end
        self:DrawDebug(self.prop)
        local boom = self:GetBoom()
        local left = boom > 0 and math.max(boom - CurTime(), 0) or 1
        local rate = boom > 0 and Lerp(math.Clamp(left / 3, 0, 1), 12, 3) or 4
        if math.sin(CurTime() * rate * math.pi) > 0 then
            local emp = self:GetKind() == 3
            render.SetMaterial(GLOW)
            render.DrawSprite(self:Centre(), 14, 14, emp and Color(90, 170, 255) or Color(255, 60, 40))
        end
    end
end
