--[[
    Grenade base (not spawnable). A 1x1 inventory item that stacks; LMB
    throws hard, RMB lobs short. Each throw uses one from the inventory
    (none in rhylib_infammo test mode) and spawns rhylib_grenade.

    SWEP.GrenadeKind: "fuse" (explodes FuseTime after the throw), "impact"
    (explodes on the first hit) or "emp" (fuse; kills Rhylib droids in
    range, harmless to everything else). Blast numbers are on the entity.
    First person: GMod's HL2 grenade hands (c_grenade, player hands) play
    draw / idle / throw; its grenade bones are shrunk away and the prop is
    drawn on the grenade bone, so it follows the throw. Third person: the
    prop in the right hand (PropWMPos/Ang, tune with rhylib_wm_editor).
    Prop offsets are from the model's centre (the thermal's origin is off
    to one side).
]]

AddCSLuaFile()

SWEP.Base = "weapon_base"
SWEP.PrintName = "Grenade"
SWEP.Category = "Rhylib: Republic"
SWEP.Spawnable = false
SWEP.Slot = 4
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true

SWEP.ViewModel = "models/weapons/c_grenade.mdl"
SWEP.ViewModelFOV = 54
SWEP.WorldModel = "models/jajoff/sps/cgiweapons/tc13j/thermalgrenade.mdl"
SWEP.UseHands = true
SWEP.HoldType = "grenade"

SWEP.Primary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }

SWEP.InvW = 1
SWEP.InvH = 1
SWEP.InvStack = 3
SWEP.InvWeight = 0.4
SWEP.InvCategory = "gear"

SWEP.GrenadeKind = "fuse"
SWEP.FuseTime = 3
SWEP.ThrowForce = 1000       -- LMB
SWEP.LobForce = 450          -- RMB
SWEP.ThrowDelay = 1          -- seconds between throws
SWEP.PropColor = nil         -- tint of the grenade model

SWEP.PropModel = "models/jajoff/sps/cgiweapons/tc13j/thermalgrenade.mdl"
SWEP.PropScale = 0.75                  -- third person size
SWEP.PropVMScale = 1                   -- first person size
SWEP.PropVMPos = Vector(0, 0, 0)       -- first person: from the viewmodel's grenade bone
SWEP.PropVMAng = Angle(0, 0, 0)
SWEP.PropWMPos = Vector(-5, -1, -5)    -- third person: forward, right, up from the right hand
SWEP.PropWMAng = Angle(0, 0, 0)
SWEP.RedrawTime = 0.7                  -- after a throw, the next one comes up

function SWEP:SetupDataTables()
    self:NetworkVar("Float", 0, "LastThrow")
    self:NetworkVar("Bool", 0, "NeedDraw")
end

function SWEP:Deploy()
    self:SendWeaponAnim(ACT_VM_DRAW)
    self:SetNeedDraw(false)
    return true
end

-- The next grenade comes up after a throw.
function SWEP:Think()
    if self:GetNeedDraw() and CurTime() >= self:GetLastThrow() + self.RedrawTime then
        self:SetNeedDraw(false)
        self:SendWeaponAnim(ACT_VM_DRAW)
    end
end

function SWEP:Initialize()
    self:SetHoldType(self.HoldType)
end

function SWEP:Reload() end

function SWEP:PrimaryAttack() self:Throw(self.ThrowForce, 0.05) end
function SWEP:SecondaryAttack() self:Throw(self.LobForce, 0.25) end

-- force: speed along the aim; lift: extra upward share of it.
function SWEP:Throw(force, lift)
    local o = self:GetOwner()
    if not IsValid(o) or not o:IsPlayer() then return end
    self:SetNextPrimaryFire(CurTime() + self.ThrowDelay)
    self:SetNextSecondaryFire(CurTime() + self.ThrowDelay)
    self:SetLastThrow(CurTime())
    self:SetNeedDraw(true)
    self:SendWeaponAnim(ACT_VM_THROW)
    o:SetAnimation(PLAYER_ATTACK1)
    if CLIENT then return end

    local ang = o:EyeAngles()
    local pos = o:GetShootPos() + ang:Forward() * 16 + ang:Right() * 6 - ang:Up() * 4
    -- Don't spawn it inside a wall.
    local tr = util.TraceLine({ start = o:GetShootPos(), endpos = pos, filter = o, mask = MASK_SOLID })
    if tr.Hit then pos = tr.HitPos + tr.HitNormal * 4 end

    local g = ents.Create("rhylib_grenade")
    if not IsValid(g) then return end
    g:SetPos(pos)
    g:SetAngles(ang)
    g.kind = self.GrenadeKind
    g.fuse = self.FuseTime
    g.thrower = o
    g:SetOwner(o)
    if self.PropColor then g:SetColor(self.PropColor) end
    g:Spawn()
    local phys = g:GetPhysicsObject()
    if IsValid(phys) then
        phys:SetVelocity(o:GetVelocity() * 0.5 + ang:Forward() * force + Vector(0, 0, force * lift))
        phys:AddAngleVelocity(VectorRand() * 400)
    end
    o:EmitSound("weapons/slam/throw.wav", 65, 100)
    self:UseOne(o)
end

-- One fewer in the inventory (the inventory strips the weapon when the
-- last one leaves). Test ammo keeps it.
function SWEP:UseOne(o)
    if o:GetNW2Bool("rhylib_infammo") then return end
    local Inv = Rhylib.Inventory
    local class = self:GetClass()
    if Inv and Inv.Get and Inv.Remove then
        for _, inst in pairs(Inv.Get(o).byUid) do
            if inst.id == class then
                Inv.Remove(o, inst.uid, 1)
                return
            end
        end
    end
    o:StripWeapon(class)
end

if CLIENT then
    -- Model centre in its own coordinates (the thermal's origin is off to
    -- one side), per model.
    local centres = {}
    function SWEP:PropCentre(e)
        local m = self.PropModel
        if not centres[m] then
            local mins, maxs = e:GetModelBounds()
            centres[m] = (mins + maxs) * 0.5
        end
        return centres[m]
    end

    local function place(pos, ang, off, offAng)
        local p = pos + ang:Forward() * off.x + ang:Right() * off.y + ang:Up() * off.z
        local a = Angle(ang.p, ang.y, ang.r)
        a:RotateAroundAxis(a:Up(), offAng.y)
        a:RotateAroundAxis(a:Right(), offAng.p)
        a:RotateAroundAxis(a:Forward(), offAng.r)
        return p, a
    end

    function SWEP:Prop(key, sc)
        local e = self[key]
        if not IsValid(e) then
            e = ClientsideModel(self.PropModel, RENDERGROUP_OPAQUE)
            if not IsValid(e) then return nil end
            e:SetNoDraw(true)
            if self.PropColor then e:SetColor(self.PropColor) end
            self[key] = e
        end
        sc = sc or self.PropScale or 1
        if e.rhylibScale ~= sc then e:SetModelScale(sc, 0) e.rhylibScale = sc end
        return e
    end

    -- Draws the prop with its centre at pos.
    function SWEP:DrawPropAt(e, pos, ang)
        local c = self:PropCentre(e) * (e.rhylibScale or 1)
        e:SetPos(LocalToWorld(-c, angle_zero, pos, ang))
        e:SetAngles(ang)
        e:SetupBones()
        e:DrawModel()
    end

    -- c_grenade's own grenade (bones named like grenade / .pin / lever) is
    -- shrunk away every frame (the server overwrites client bone changes)
    -- and restored for other weapons.
    local SHRINK, ONE = Vector(0.01, 0.01, 0.01), Vector(1, 1, 1)
    local nadeBones = {}
    local function bonesOf(vm)
        local mdl = vm:GetModel() or ""
        if not nadeBones[mdl] then
            local list, body = {}, nil
            for i = 0, (vm:GetBoneCount() or 0) - 1 do
                local n = string.lower(vm:GetBoneName(i) or "")
                if string.find(n, "grenade", 1, true) or string.find(n, "[%._]pin$") or string.find(n, "lever", 1, true) or string.find(n, "spoon", 1, true) then
                    list[#list + 1] = i
                    if not body and string.find(n, "grenade", 1, true) then body = i end
                end
            end
            nadeBones[mdl] = { list = list, body = body }
        end
        return nadeBones[mdl]
    end

    -- c_grenade is only the HL2 grenade (the arms are the separate hands
    -- entity), so the whole viewmodel is drawn with an invisible material.
    local INVIS = "!rhylib_nade_invisible"
    local madeInvis = false
    local function invisible()
        if not madeInvis then
            madeInvis = true
            CreateMaterial("rhylib_nade_invisible", "UnlitGeneric", {
                ["$basetexture"] = "vgui/white", ["$alpha"] = "0", ["$translucent"] = "1",
            })
        end
        return INVIS
    end

    Rhylib.Hook.Add("PreDrawViewModel", "grenade.vmreset", function(vm, ply, wep)
        if not IsValid(vm) or not vm.rhylibNadeHidden then return end
        if IsValid(wep) and wep.Base == "rhylib_grenade_base" then return end
        for _, i in ipairs(vm.rhylibNadeHidden) do
            if i < (vm:GetBoneCount() or 0) then vm:ManipulateBoneScale(i, ONE) end
        end
        vm:SetMaterial("")
        vm.rhylibNadeHidden = nil
    end)

    function SWEP:PreDrawViewModel(vm)
        local b = bonesOf(vm)
        for _, i in ipairs(b.list) do vm:ManipulateBoneScale(i, SHRINK) end
        if vm:GetMaterial() ~= INVIS then vm:SetMaterial(invisible()) end
        vm.rhylibNadeHidden = b.list
    end

    function SWEP:PostDrawViewModel(vm)
        -- Gone from the hand once thrown, until the next one comes up.
        if self:GetNeedDraw() or CurTime() < self:GetLastThrow() + 0.1 then return end
        local b = bonesOf(vm)
        local bone = b.body or vm:LookupBone("ValveBiped.Bip01_R_Hand")
        local m = bone and vm:GetBoneMatrix(bone)
        local e = self:Prop("propVM", self.PropVMScale or 1)
        if m and e then self:DrawPropAt(e, place(m:GetTranslation(), m:GetAngles(), self.PropVMPos, self.PropVMAng)) end
    end

    function SWEP:DrawWorldModel(flags)
        local o = self:GetOwner()
        if not IsValid(o) then self:DrawModel(flags) return end
        if self:GetNeedDraw() then return end   -- just thrown
        local b = o:LookupBone("ValveBiped.Bip01_R_Hand")
        local m = b and o:GetBoneMatrix(b)
        local e = self:Prop("propWM")
        if m and e then self:DrawPropAt(e, place(m:GetTranslation(), m:GetAngles(), self.PropWMPos, self.PropWMAng)) end
    end

    function SWEP:OnRemove()
        if IsValid(self.propVM) then self.propVM:Remove() end
        if IsValid(self.propWM) then self.propWM:Remove() end
    end
end
