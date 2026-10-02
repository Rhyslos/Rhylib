--[[
    Thermal detonator. For now only a 1x1 inventory item you can hold
    (no throwing yet). Prop model: models/jajoff/sps/cgiweapons/tc13j/
    thermalgrenade.mdl, floating in first person, in the right hand in
    third person.
]]

AddCSLuaFile()

SWEP.Base = "weapon_base"
SWEP.PrintName = "Thermal detonator"
SWEP.Category = "Rhylib: Republic"
SWEP.Spawnable = true
SWEP.AdminOnly = false
SWEP.Slot = 4
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = false

SWEP.ViewModel = "models/weapons/c_grenade.mdl"   -- (hidden, the prop floats)
SWEP.WorldModel = "models/jajoff/sps/cgiweapons/tc13j/thermalgrenade.mdl"
SWEP.UseHands = false
SWEP.HoldType = "grenade"

SWEP.Primary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }

-- Inventory: one cell, stacks of 3.
SWEP.InvW = 1
SWEP.InvH = 1
SWEP.InvStack = 3
SWEP.InvWeight = 0.4
SWEP.InvCategory = "gear"

SWEP.PropModel = "models/jajoff/sps/cgiweapons/tc13j/thermalgrenade.mdl"
SWEP.PropVMPos = Vector(14, 6, -6)     -- first person: forward, right, up from the view
SWEP.PropVMAng = Angle(0, 0, 0)
SWEP.PropWMPos = Vector(3, 2, 0)       -- third person: forward, right, up from the right hand
SWEP.PropWMAng = Angle(0, 0, 0)

function SWEP:Initialize()
    self:SetHoldType(self.HoldType)
end

function SWEP:PrimaryAttack() end
function SWEP:SecondaryAttack() end
function SWEP:Reload() end

if CLIENT then
    local function place(pos, ang, off, offAng)
        local p = pos + ang:Forward() * off.x + ang:Right() * off.y + ang:Up() * off.z
        local a = Angle(ang.p, ang.y, ang.r)
        a:RotateAroundAxis(a:Up(), offAng.y)
        a:RotateAroundAxis(a:Right(), offAng.p)
        a:RotateAroundAxis(a:Forward(), offAng.r)
        return p, a
    end

    function SWEP:Prop(key)
        local e = self[key]
        if IsValid(e) then return e end
        e = ClientsideModel(self.PropModel, RENDERGROUP_OPAQUE)
        if not IsValid(e) then return nil end
        e:SetNoDraw(true)
        self[key] = e
        return e
    end

    local function drawAt(e, pos, ang)
        e:SetPos(pos)
        e:SetAngles(ang)
        e:SetupBones()
        e:DrawModel()
    end

    function SWEP:PreDrawViewModel(vm)
        local e = self:Prop("propVM")
        if e then drawAt(e, place(vm:GetPos(), vm:GetAngles(), self.PropVMPos, self.PropVMAng)) end
        return true
    end

    function SWEP:DrawWorldModel(flags)
        local o = self:GetOwner()
        if not IsValid(o) then self:DrawModel(flags) return end
        local b = o:LookupBone("ValveBiped.Bip01_R_Hand")
        local m = b and o:GetBoneMatrix(b)
        local e = self:Prop("propWM")
        if m and e then drawAt(e, place(m:GetTranslation(), m:GetAngles(), self.PropWMPos, self.PropWMAng)) end
    end

    function SWEP:OnRemove()
        if IsValid(self.propVM) then self.propVM:Remove() end
        if IsValid(self.propWM) then self.propWM:Remove() end
    end
end
