--[[
    Rhylib weapon base. Every blaster derives from this.

    Hip-fire by default. Hold right mouse to half-aim: the gun comes up
    toward the shoulder, the view zooms slightly and the spread tightens.
    (Aiming will be gated behind a skill once the skill module exists.)

    Derived weapons set their own values below. Note: GMod does NOT merge
    the Primary and Spread tables from the base, so a weapon that changes
    any field in them must define the whole table.
]]

SWEP.Base = "weapon_base"
SWEP.PrintName = "Rhylib base"
SWEP.Category = "Rhylib"
SWEP.Spawnable = false
SWEP.Author = "Rhylib"

SWEP.ViewModel = "models/weapons/c_smg1.mdl"
SWEP.WorldModel = "models/weapons/w_smg1.mdl"
SWEP.ViewModelFOV = 54
SWEP.UseHands = true
SWEP.HoldType = "ar2"
SWEP.Slot = 2
SWEP.SlotPos = 1
SWEP.DrawAmmo = true
SWEP.DrawCrosshair = true  -- must stay true so DoDrawCrosshair is called

SWEP.Primary = {
    ClipSize = 50,
    DefaultClip = 200,
    Automatic = true,
    Ammo = "rhylib_blaster",
}
SWEP.Secondary = {
    ClipSize = -1,
    DefaultClip = -1,
    Automatic = true,
    Ammo = "none",
}

-- Rhylib settings
SWEP.FireRate = 600                 -- rounds per minute
SWEP.Damage = 25
SWEP.BoltSpeed = 7000               -- units per second (max 16383)
SWEP.BoltColor = 1                  -- 1 blue, 2 red, 3 green
SWEP.FireSound = "weapons/airboat/airboat_gun_energy1.wav"

-- Cone angles in degrees. See rhylib/weapons/sh_10_spread.lua.
SWEP.Spread = {
    hip = 1.4,              -- resting cone, hip-fire
    aim = 0.7,              -- resting cone, aiming
    kickMain = 0.35,        -- kick on the arc nearest the shot (times the streak)
    kickSide = 0.1,         -- kick on the other two arcs
    bloomPerShot = 0.11,    -- shared bloom per shot
    bloomMax = 2.0,
    aimKickMult = 0.5,      -- kicks and bloom added while aiming
    aimOffsetMult = 0.6,    -- all arc offsets while aiming
}

SWEP.AimPos = Vector(-2, 0, 1)      -- viewmodel offset when aiming (right, forward, up)
SWEP.AimFov = 0.85                  -- FOV multiplier when aiming

function SWEP:SetupDataTables()
    self:NetworkVar("Float", 0, "Bloom")
    self:NetworkVar("Float", 1, "Kick1")
    self:NetworkVar("Float", 2, "Kick2")
    self:NetworkVar("Float", 3, "Kick3")
    self:NetworkVar("Float", 4, "KickTime")
    self:NetworkVar("Float", 5, "ReloadEnd")
    self:NetworkVar("Int", 0, "Streak")
    self:NetworkVar("Int", 1, "LastArc")
    self:NetworkVar("Bool", 0, "Aiming")
end

function SWEP:Initialize()
    self:SetHoldType(self.HoldType)
end

function SWEP:Deploy()
    self:SetAiming(false)
    return true
end

function SWEP:Holster()
    self:SetAiming(false)
    return true
end

function SWEP:PrimaryAttack()
    if not self:CanPrimaryAttack() then return end

    local owner = self:GetOwner()
    if not IsValid(owner) then return end

    local now = CurTime()
    self:SetNextPrimaryFire(now + 60 / self.FireRate)

    local Spread = Rhylib.Weapons.Spread
    local dir, a = Spread.ShotDirection(self, owner:EyeAngles(), 0)
    Spread.AddShot(self, Spread.NearestArc(a), now)

    self:TakePrimaryAmmo(1)
    self:EmitSound(self.FireSound, 80, util.SharedRandom("rhylib.pitch", 96, 104), 1, CHAN_WEAPON)
    self:SendWeaponAnim(ACT_VM_PRIMARYATTACK)
    owner:SetAnimation(PLAYER_ATTACK1)

    if owner:IsPlayer() then
        owner:ViewPunch(Angle(-0.3, util.SharedRandom("rhylib.punch", -0.15, 0.15), 0))
    end

    local origin = owner:GetShootPos()
    if SERVER then
        Rhylib.Weapons.Bolts.Fire(owner, self, origin, dir)
    elseif IsFirstTimePredicted() then
        Rhylib.Weapons.Bolts.FireLocal(owner, self, origin, dir)
    end
end

function SWEP:SecondaryAttack()
    -- Right mouse is aim, handled in Think.
end

function SWEP:Reload()
    if self:Clip1() >= self.Primary.ClipSize or self:Ammo1() <= 0 then return end
    if self:DefaultReload(ACT_VM_RELOAD) then
        -- DefaultReload pushes the next shot back to when the reload ends.
        self:SetReloadEnd(self:GetNextPrimaryFire())
        self:SetAiming(false)
        local owner = self:GetOwner()
        if IsValid(owner) then owner:SetAnimation(PLAYER_RELOAD) end
    end
end

function SWEP:Think()
    local owner = self:GetOwner()
    if not IsValid(owner) or not owner:IsPlayer() then return end

    local reloading = CurTime() < self:GetReloadEnd()
    local want = owner:KeyDown(IN_ATTACK2) and not owner:IsSprinting() and not reloading
    if want ~= self:GetAiming() then
        self:SetAiming(want)
    end
end

if CLIENT then
    -- Smooth 0..1 value for the aim animation, client only.
    function SWEP:GetAimFrac()
        return self.aimFrac or 0
    end

    function SWEP:GetViewModelPosition(pos, ang)
        self.aimFrac = math.Approach(self.aimFrac or 0, self:GetAiming() and 1 or 0, FrameTime() * 6)
        local f = math.ease and math.ease.InOutSine(self.aimFrac) or self.aimFrac
        if f <= 0 then return pos, ang end
        local off = self.AimPos * f
        pos = pos + ang:Right() * off.x + ang:Forward() * off.y + ang:Up() * off.z
        return pos, ang
    end

    function SWEP:TranslateFOV(fov)
        return fov * Lerp(self:GetAimFrac(), 1, self.AimFov)
    end

    function SWEP:AdjustMouseSensitivity()
        if self:GetAimFrac() > 0 then
            return Lerp(self:GetAimFrac(), 1, self.AimFov)
        end
    end

    function SWEP:DoDrawCrosshair(x, y)
        Rhylib.Weapons.Crosshair.Draw(self, x, y)
        return true
    end
end
