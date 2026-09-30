--[[
    Rhylib weapon base. Every blaster derives from this.

    Hip-fire by default. Hold right mouse to half-aim: the gun comes up
    toward the shoulder, the view zooms slightly and the spread tightens.
    (Aiming will be gated behind a skill once the skill module exists.)

    Ammo:
      - Magazine: Clip1 holds the shots. Tap R to swap magazines.
      - Power cell (weapons with UsesCell): the "Cell" value drains per shot.
        Hold R and pick "Power cell" in the radial menu to swap cells.
      Magazines and cells come from the player's pouch (sv_20_pouch.lua)
      until the inventory module replaces it.

    Derived weapons set their own values below. Note: GMod does NOT merge
    the Primary, Secondary and Spread tables from the base, so a weapon
    that changes any field in them must define the whole table.
]]

AddCSLuaFile()

SWEP.Base = "weapon_base"
SWEP.PrintName = "Rhylib base"
SWEP.Category = "Rhylib"
SWEP.Spawnable = false
SWEP.Author = "Rhylib"
SWEP.IsRhylib = true

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
    DefaultClip = 50,       -- keep equal to ClipSize: spare magazines come from the pouch
    Automatic = true,
    Ammo = "rhylib_blaster",
}
SWEP.Secondary = {
    ClipSize = -1,
    DefaultClip = -1,
    Automatic = true,
    Ammo = "none",          -- set to "rhylib_cell" on cell weapons so the HUD shows spare cells
}

-- Rhylib settings
SWEP.FireRate = 600                 -- rounds per minute
SWEP.Damage = 25
SWEP.BoltSpeed = 7000               -- units per second (max 16383)
SWEP.BoltColor = 1                  -- 1 blue, 2 red, 3 green
SWEP.FireSound = "weapons/airboat/airboat_gun_energy1.wav"

SWEP.UsesCell = false
SWEP.CellShots = 500                -- shots from one full power cell
SWEP.CellReloadMult = 1.6           -- cell swap takes this much longer than a magazine swap

-- Spare ammo given when the weapon is picked up. Testing only, until
-- armouries and the inventory exist.
SWEP.StartMags = 4
SWEP.StartCells = 0

-- Size in the inventory grid (cells). InvLarge = can't go in a backpack.
SWEP.InvW = 3
SWEP.InvH = 1
SWEP.InvLarge = false

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

--[[
    Prop models: a plain prop (no arms, no animations) can be used as the
    gun. It floats in first person and is attached to the right hand in
    third person. Tune the offsets in the weapon file; saving the file
    updates them live.
]]
SWEP.PropModel = nil
SWEP.PropScale = 1
SWEP.PropVMPos = Vector(0, 0, 0)    -- first person: forward, right, up from the view
SWEP.PropVMAng = Angle(0, 0, 0)     -- first person: pitch, yaw, roll
SWEP.PropWMPos = Vector(0, 0, 0)    -- third person: forward, right, up from the right hand
SWEP.PropWMAng = Angle(0, 0, 0)
SWEP.PropMuzzle = Vector(0, 0, 0)   -- muzzle point in the prop's own coordinates

local RELOAD_NONE, RELOAD_MAG, RELOAD_CELL = 0, 1, 2

function SWEP:SetupDataTables()
    self:NetworkVar("Float", 0, "Bloom")
    self:NetworkVar("Float", 1, "Kick1")
    self:NetworkVar("Float", 2, "Kick2")
    self:NetworkVar("Float", 3, "Kick3")
    self:NetworkVar("Float", 4, "KickTime")
    self:NetworkVar("Float", 5, "ReloadEnd")
    self:NetworkVar("Float", 6, "Cell")
    self:NetworkVar("Int", 0, "Streak")
    self:NetworkVar("Int", 1, "LastArc")
    self:NetworkVar("Int", 2, "ReloadKind")
    self:NetworkVar("Bool", 0, "Aiming")
end

function SWEP:Initialize()
    self:SetHoldType(self.HoldType)
    if self.UsesCell then self:SetCell(1) end
end

function SWEP:Deploy()
    self:SetAiming(false)
    return true
end

function SWEP:Holster()
    self:SetAiming(false)
    self:CancelReload()
    return true
end

--------------------------------------------------------------------------
-- Firing
--------------------------------------------------------------------------

-- Damage drops once the power cell is nearly empty.
function SWEP:GetCellDamageMult()
    if not self.UsesCell then return 1 end
    local low = Rhylib.Config.Get("weapons", "lowCellThreshold")
    local cell = self:GetCell()
    if cell >= low then return 1 end
    return Lerp(cell / low, Rhylib.Config.Get("weapons", "lowCellMinDamage"), 1)
end

-- Large weapons (InvLarge) are too heavy to fire while flying a jetpack.
function SWEP:TooHeavyToFire()
    local owner = self:GetOwner()
    local jp = Rhylib.Jetpack
    return self.InvLarge and IsValid(owner) and owner:IsPlayer() and jp and jp.Flying and jp.Flying(owner) or false
end

function SWEP:CanPrimaryAttack()
    if self:GetReloadKind() ~= RELOAD_NONE then return false end
    if self:TooHeavyToFire() then return false end

    if self:Clip1() <= 0 then
        self:EmitSound("Weapon_Pistol.Empty")
        self:SetNextPrimaryFire(CurTime() + 0.3)
        if SERVER then self:StartReload(RELOAD_MAG) end
        return false
    end

    if self.UsesCell and self:GetCell() <= 0 then
        self:EmitSound("Weapon_AR2.Empty")
        self:SetNextPrimaryFire(CurTime() + 0.3)
        return false
    end

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

    local damage = self.Damage * self:GetCellDamageMult()
    self:TakePrimaryAmmo(1)
    if self.UsesCell then
        self:SetCell(math.max(0, self:GetCell() - 1 / self.CellShots))
    end

    self:EmitSound(self.FireSound, 80, util.SharedRandom("rhylib.pitch", 96, 104), 1, CHAN_WEAPON)
    self:SendWeaponAnim(ACT_VM_PRIMARYATTACK)
    owner:SetAnimation(PLAYER_ATTACK1)

    if owner:IsPlayer() then
        owner:ViewPunch(Angle(-0.3, util.SharedRandom("rhylib.punch", -0.15, 0.15), 0))
    end

    local origin = owner:GetShootPos()
    if SERVER then
        Rhylib.Weapons.Bolts.Fire(owner, self, origin, dir, damage)
    elseif IsFirstTimePredicted() then
        Rhylib.Weapons.Bolts.FireLocal(owner, self, origin, dir)
    end
end

function SWEP:SecondaryAttack()
    -- Right mouse is aim, handled in Think.
end

--------------------------------------------------------------------------
-- Reloading
--------------------------------------------------------------------------

-- R is handled by the radial menu (cl_30_reload.lua), which asks the
-- server to reload. The default reload key action does nothing.
function SWEP:Reload()
end

function SWEP:IsReloading()
    return self:GetReloadKind() ~= RELOAD_NONE
end

function SWEP:CancelReload()
    if self:GetReloadKind() == RELOAD_NONE then return end
    self:SetReloadKind(RELOAD_NONE)
    self:SetNextPrimaryFire(CurTime())
    local owner = self:GetOwner()
    local vm = IsValid(owner) and owner:IsPlayer() and owner:GetViewModel()
    if IsValid(vm) then vm:SetPlaybackRate(1) end
end

if SERVER then
    local SOUNDS = {
        [RELOAD_MAG] = "weapons/smg1/smg1_reload.wav",
        [RELOAD_CELL] = "items/battery_pickup.wav",
    }

    -- kind: 1 = magazine, 2 = power cell
    function SWEP:StartReload(kind)
        if self:IsReloading() then return end
        local owner = self:GetOwner()
        if not IsValid(owner) or not owner:IsPlayer() then return end
        local Pouch = Rhylib.Weapons.Pouch

        if kind == RELOAD_MAG then
            if Pouch.Count(owner, "mags") == 0 or self:Clip1() >= self.Primary.ClipSize then return end
        elseif kind == RELOAD_CELL then
            if not self.UsesCell or Pouch.Count(owner, "cells") == 0 then return end
        else
            return
        end

        self:SendWeaponAnim(ACT_VM_RELOAD)
        local vm = owner:GetViewModel()
        local duration = IsValid(vm) and vm:SequenceDuration() or 2
        if kind == RELOAD_CELL then
            duration = duration * self.CellReloadMult
            if IsValid(vm) then vm:SetPlaybackRate(1 / self.CellReloadMult) end
        end

        local finish = CurTime() + duration
        self:SetReloadKind(kind)
        self:SetReloadEnd(finish)
        self:SetNextPrimaryFire(finish)
        self:SetAiming(false)
        owner:SetAnimation(PLAYER_RELOAD)
        self:EmitSound(SOUNDS[kind], 70)
    end

    function SWEP:FinishReload()
        local kind = self:GetReloadKind()
        self:SetReloadKind(RELOAD_NONE)
        local owner = self:GetOwner()
        if not IsValid(owner) then return end
        local Pouch = Rhylib.Weapons.Pouch

        local vm = owner:GetViewModel()
        if IsValid(vm) then vm:SetPlaybackRate(1) end

        if kind == RELOAD_MAG then
            local best = Pouch.TakeBest(owner, "mags")
            if not best then return end
            local old = self:Clip1() / self.Primary.ClipSize
            if old > 0 then Pouch.Add(owner, "mags", old, true) end
            self:SetClip1(math.floor(best * self.Primary.ClipSize + 0.5))
        elseif kind == RELOAD_CELL then
            local best = Pouch.TakeBest(owner, "cells")
            if not best then return end
            local old = self:GetCell()
            if old > 0.001 then Pouch.Add(owner, "cells", old, true) end
            self:SetCell(best)
        end
    end

    -- Without the inventory addon, picking up the weapon gives its start ammo.
    -- With it, rhylib_inventory handles pickups (see sv_20_pouch.lua).
    function SWEP:Equip(owner)
        if Rhylib.Inventory and Rhylib.Inventory.AddItem then return end
        if not IsValid(owner) or not owner:IsPlayer() then return end
        local Pouch = Rhylib.Weapons.Pouch
        for _ = 1, self.StartMags do Pouch.Add(owner, "mags", 1) end
        for _ = 1, self.StartCells do Pouch.Add(owner, "cells", 1) end
        Pouch.Sync(owner)
    end
end

-- Clip and cell are kept in the inventory item while the weapon is stored.
function SWEP:GetInventoryData()
    return { clip = self:Clip1(), cell = self.UsesCell and self:GetCell() or nil }
end

function SWEP:SetInventoryData(data)
    data = data or {}
    self:SetClip1(data.clip or self.Primary.ClipSize)
    if self.UsesCell then self:SetCell(data.cell or 1) end
end

function SWEP:Think()
    local owner = self:GetOwner()
    if not IsValid(owner) or not owner:IsPlayer() then return end

    if SERVER and self:IsReloading() and CurTime() >= self:GetReloadEnd() then
        self:FinishReload()
    end

    local want = owner:KeyDown(IN_ATTACK2) and not owner:IsSprinting() and not self:IsReloading()
    if want ~= self:GetAiming() then
        self:SetAiming(want)
    end
end

--------------------------------------------------------------------------
-- Client: aiming, crosshair, HUD and prop models
--------------------------------------------------------------------------

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
        -- In Rhylib third person, rhylib_thirdperson draws it instead.
        local tp = Rhylib.ThirdPerson
        if not (tp and tp.Active and tp.Active()) then
            Rhylib.Weapons.Crosshair.Draw(self, x, y)
        end
        return true
    end

    local RELOAD_TEXT = {
        [RELOAD_MAG] = "Reloading magazine",
        [RELOAD_CELL] = "Replacing power cell",
    }

    function SWEP:DrawHUD()
        local UI = Rhylib.UI
        local s = ScrH() / 1080

        -- rhylib_hud shows the cell in its ammo counter; this is the fallback.
        if self.UsesCell and not Rhylib.HUD then
            local cell = self:GetCell()
            local col = cell < Rhylib.Config.Get("weapons", "lowCellThreshold") and UI.Colors.bad or UI.Colors.text
            draw.SimpleText(string.format("Power cell %d%%", math.ceil(cell * 100)), UI.Font(22), ScrW() - 40 * s, ScrH() - 150 * s, col, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
        end

        if self:TooHeavyToFire() then
            draw.SimpleText("Too heavy to fire while flying", UI.Font(20), ScrW() * 0.5, ScrH() * 0.62, UI.Colors.bad, TEXT_ALIGN_CENTER)
        end

        local kind = self:GetReloadKind()
        if kind ~= RELOAD_NONE then
            draw.SimpleText(RELOAD_TEXT[kind] or "", UI.Font(20), ScrW() * 0.5, ScrH() * 0.62, UI.Colors.textDim, TEXT_ALIGN_CENTER)
        end
    end

    -- Prop model helpers ------------------------------------------------

    local function offsetTransform(pos, ang, offPos, offAng)
        local p = pos + ang:Forward() * offPos.x + ang:Right() * offPos.y + ang:Up() * offPos.z
        local a = Angle(ang.p, ang.y, ang.r)
        a:RotateAroundAxis(a:Up(), offAng.y)
        a:RotateAroundAxis(a:Right(), offAng.p)
        a:RotateAroundAxis(a:Forward(), offAng.r)
        return p, a
    end

    function SWEP:GetPropEntity(key)
        local ent = self[key]
        if IsValid(ent) and ent:GetModel() == self.PropModel then return ent end
        if IsValid(ent) then ent:Remove() end
        ent = ClientsideModel(self.PropModel, RENDERGROUP_OPAQUE)
        if not IsValid(ent) then return nil end
        ent:SetNoDraw(true)
        ent:SetModelScale(self.PropScale, 0)
        self[key] = ent
        return ent
    end

    -- Where bolts should appear to leave the gun. Used by cl_10_bolts.lua.
    function SWEP:GetPropMuzzle(firstPerson)
        if not self.PropModel then return nil end
        return firstPerson and self.propMuzzleVM or self.propMuzzleWM
    end

    -- Prop weapons: skip drawing the placeholder viewmodel and draw the
    -- prop in its place. This runs inside the viewmodel render pass, so
    -- the prop gets the viewmodel's FOV, bob, sway and aim offset.
    function SWEP:PreDrawViewModel(vm)
        if not self.PropModel then return end
        local ent = self:GetPropEntity("propVM")
        if ent then
            local pos, ang = offsetTransform(vm:GetPos(), vm:GetAngles(), self.PropVMPos, self.PropVMAng)
            ent:SetPos(pos)
            ent:SetAngles(ang)
            ent:SetupBones()
            ent:DrawModel()
            self.propMuzzleVM = ent:LocalToWorld(self.PropMuzzle)
        end
        return true
    end

    function SWEP:DrawWorldModel(flags)
        local owner = self:GetOwner()
        if not self.PropModel or not IsValid(owner) then
            self:DrawModel(flags)
            return
        end

        local bone = owner:LookupBone("ValveBiped.Bip01_R_Hand")
        local matrix = bone and owner:GetBoneMatrix(bone)
        local ent = self:GetPropEntity("propWM")
        if not matrix or not ent then return end

        local pos, ang = offsetTransform(matrix:GetTranslation(), matrix:GetAngles(), self.PropWMPos, self.PropWMAng)
        ent:SetPos(pos)
        ent:SetAngles(ang)
        ent:SetupBones()
        ent:DrawModel()
        self.propMuzzleWM = ent:LocalToWorld(self.PropMuzzle)
    end

    function SWEP:OnRemove()
        if IsValid(self.propVM) then self.propVM:Remove() end
        if IsValid(self.propWM) then self.propWM:Remove() end
    end
end
