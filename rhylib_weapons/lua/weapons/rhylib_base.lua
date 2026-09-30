--[[
    Rhylib weapon base. Every blaster derives from this.

    Hip-fire by default. Hold right mouse to half-aim: the gun comes up
    toward the shoulder, the view zooms slightly and the spread tightens.
    (Aiming will be gated behind a skill once the skill module exists.)

    Ammo:
      - Magazine: Clip1 holds the shots. SWEP.Mags lists the magazine
        types the gun takes (see W.MagTypes); the loaded type decides how
        many shots it holds. Tap R to reload the best magazine (the same
        type if you have one, else the first in SWEP.Mags).
      - Power cell (weapons with UsesCell): the "Cell" value drains per shot.
      Hold R for the radial menu to pick a magazine type or a power cell.
      Magazines and cells come from the inventory (or the pouch without it),
      see sv_20_pouch.lua.

    Sprinting lowers the gun the same way safety does (passive hold, no
    firing or aiming) without changing the fire mode. It comes back up
    SprintRaiseTime after you stop.

    Fire modes and safety:
      - E + R cycles through the weapon's FireModes ("semi", "auto", "burst").
      - Shift + E + R toggles safety: the weapon is lowered (passive hold),
        can't fire or aim, and the crosshair hides.
      Semi and burst need a fresh trigger pull for each shot or burst.
      Primary.Automatic must stay true; the fire mode decides instead.

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
    ClipSize = 30,          -- rounds of the preferred magazine, SWEP.Mags[1]
    DefaultClip = 30,       -- keep equal to ClipSize: spawned guns come loaded, spares come from the inventory
    Automatic = true,
    Ammo = "rhylib_mag_small",
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

-- Fire modes this weapon can switch between (E + R), first one is the default.
SWEP.FireModes = { "semi" }
SWEP.SprintRaiseTime = 0.25         -- seconds after sprinting before the gun can fire
SWEP.Grapple = false                -- true: gets a "grapple" fire mode while you carry a grapple hook
SWEP.BurstCount = 3
SWEP.BurstDelay = 0.25              -- extra pause after a burst

-- Magazine types this gun takes, preferred first (ids from W.MagTypes).
SWEP.Mags = { "mag_small" }
SWEP.ReloadTime = nil               -- seconds; nil = the viewmodel's reload animation length
SWEP.AutoReload = false             -- reload by itself when the magazine runs empty (launchers)

-- Spin-up (rotary guns): hold fire this long before the first shot.
-- While spinning or firing, walk speed is multiplied by SpinMoveMult.
SWEP.SpinUp = nil                   -- seconds, nil = fires at once
SWEP.SpinMoveMult = 0.6

-- Explosive bolts (rockets): { radius = units, damage = at the centre }.
-- The bolt then does blast damage where it hits instead of a direct hit.
SWEP.Explosive = nil
SWEP.BoltLife = nil                 -- seconds before a bolt that hit nothing is gone; nil = config

SWEP.UsesCell = false
SWEP.CellShots = 500                -- shots from one full power cell
SWEP.CellReloadMult = 1.6           -- cell swap takes this much longer than a magazine swap

-- Spare ammo given when the weapon is picked up (of the preferred
-- magazine type). Testing only, until armouries exist.
SWEP.StartMags = 4
SWEP.StartCells = 0

-- Size in the inventory grid (cells). InvLarge = can't go in a backpack.
SWEP.InvW = 3
SWEP.InvH = 1
SWEP.InvLarge = false
SWEP.InvWeight = 3                  -- kg

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
    self:NetworkVar("Float", 7, "SpinStart")   -- when the barrels started spinning, 0 = not spinning
    self:NetworkVar("Int", 0, "Streak")
    self:NetworkVar("Int", 1, "LastArc")
    self:NetworkVar("Int", 2, "ReloadKind")
    self:NetworkVar("Int", 3, "FireMode")
    self:NetworkVar("Int", 4, "BurstLeft")
    self:NetworkVar("Int", 5, "MagType")       -- index of the loaded magazine type, 0 = none
    self:NetworkVar("Int", 6, "ReloadMag")     -- magazine type being loaded
    self:NetworkVar("Bool", 0, "Aiming")
    self:NetworkVar("Bool", 1, "Safety")
    self:NetworkVar("Bool", 2, "TriggerReady")
    self:NetworkVar("Bool", 3, "Lowered")      -- lowered while sprinting

    -- Lowered hold on every client as soon as safety or sprinting changes.
    self:NetworkVarNotify("Safety", self.OnLoweredChanged)
    self:NetworkVarNotify("Lowered", self.OnLoweredChanged)
end

-- Safety on, or lowered while sprinting: gun down, can't fire or aim.
function SWEP:IsLowered()
    return self:GetSafety() or self:GetLowered()
end

-- Notify callbacks run before the new value is stored, so take it from the args.
function SWEP:OnLoweredChanged(name, _, on)
    local safety = name == "Safety" and on or (name ~= "Safety" and self:GetSafety())
    local lowered = name == "Lowered" and on or (name ~= "Lowered" and self:GetLowered())
    self:SetHoldType((safety or lowered) and "passive" or self.HoldType)
end

function SWEP:Initialize()
    self:SetHoldType(self:IsLowered() and "passive" or self.HoldType)
    if self.UsesCell then self:SetCell(1) end
    if self:GetFireMode() == 0 then self:SetFireMode(1) end
    if self:GetMagType() == 0 then
        local m = Rhylib.Weapons.MagTypes[self.Mags[1]]
        if m then self:SetMagType(m.index) end
    end
    self:SetTriggerReady(true)
end

-- The grapple mode sits after the weapon's own modes (index #FireModes + 1).
function SWEP:GetFireModeName()
    local m = self:GetFireMode()
    if self.Grapple and m == #self.FireModes + 1 then return "grapple" end
    return self.FireModes[m] or self.FireModes[1] or "semi"
end

function SWEP:InGrappleMode()
    return self.Grapple and self:GetFireMode() == #self.FireModes + 1
end

-- Magazine helpers --------------------------------------------------------

function SWEP:TakesMag(id)
    for i = 1, #self.Mags do
        if self.Mags[i] == id then return true end
    end
    return false
end

-- The loaded magazine type (table from W.MagTypes) or nil.
function SWEP:GetMag()
    return Rhylib.Weapons.MagByIndex[self:GetMagType()]
end

-- Shots the loaded magazine holds when full.
function SWEP:GetMagSize()
    local m = self:GetMag()
    return m and m.rounds or self.Primary.ClipSize
end

function SWEP:Deploy()
    self:SetAiming(false)
    return true
end

function SWEP:Holster()
    self:SetAiming(false)
    self:SetBurstLeft(0)
    self:SetSpinStart(0)
    self:SetLowered(false)
    self:CancelReload()
    return true
end

if SERVER then
    -- E + R (sent by cl_30_reload.lua).
    function SWEP:CycleFireMode()
        local n = #self.FireModes
        local G = Rhylib.Weapons.Grapple
        local owner = self:GetOwner()
        local grapple = self.Grapple and G and IsValid(owner)
            and Rhylib.Weapons.Pouch.Count(owner, G.ITEM) > 0
        local total = n + (grapple and 1 or 0)
        if self:GetSafety() or total <= 1 then
            self:EmitSound("Weapon_AR2.Empty", 60)
            return
        end
        local cur = self:GetFireMode()
        if cur < 1 or cur > total then cur = 1 end
        local nextMode = cur % total + 1
        if nextMode == n + 1 then self.preGrappleMode = cur end
        self:SetFireMode(nextMode)
        self:SetBurstLeft(0)
        self:EmitSound("weapons/smg1/switch_burst.wav", 60)
    end

    -- Back to the fire mode used before switching to grapple.
    function SWEP:LeaveGrappleMode()
        if not self:InGrappleMode() then return end
        local m = self.preGrappleMode
        self:SetFireMode(self.FireModes[m or 0] and m or 1)
    end

    -- Shift + E + R.
    function SWEP:ToggleSafety()
        local on = not self:GetSafety()
        self:SetSafety(on)
        self:SetAiming(false)
        self:SetBurstLeft(0)
        self:EmitSound("weapons/smg1/switch_single.wav", 60)
    end
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
    if self:IsLowered() then return false end
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

-- Called by the engine every tick while the trigger is held (Automatic
-- is always true). The fire mode decides whether that fires.
function SWEP:PrimaryAttack()
    if self:GetBurstLeft() > 0 then return end  -- a burst is running (Think fires it)
    if self:GetLowered() then return end        -- sprinting: gun is down

    local mode = self:GetFireModeName()
    if mode ~= "auto" or self:GetSafety() then
        if not self:GetTriggerReady() then return end
        self:SetTriggerReady(false)
    end

    if self:GetSafety() then
        self:EmitSound("Weapon_Pistol.Empty", 60)
        return
    end
    if mode == "grapple" then
        self:FireGrapple()
        return
    end
    -- Rotary guns wait for spin-up (an empty gun skips it, so the click
    -- and the automatic reload below still happen).
    if self:Clip1() > 0 and not self:SpunUp() then return end
    if not self:CanPrimaryAttack() then return end

    if mode == "burst" then self:SetBurstLeft(self.BurstCount - 1) end
    self:FireShot()
end

-- One shot: spread, recoil, ammo, sound and the bolt.
function SWEP:FireShot()
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

-- One grapple hook (see rhylib/weapons/sh_30_grapple.lua).
function SWEP:FireGrapple()
    local owner = self:GetOwner()
    if not IsValid(owner) or not owner:IsPlayer() then return end
    self:SetNextPrimaryFire(CurTime() + Rhylib.Config.Get("grapple", "cooldown"))
    local G = Rhylib.Weapons.Grapple
    if IsFirstTimePredicted() then
        self:EmitSound("weapons/crossbow/fire1.wav", 70, 115)
        owner:SetAnimation(PLAYER_ATTACK1)
        -- Your own client draws the hook flying out straight away.
        if CLIENT and owner:GetAmmoCount(G.AMMO) > 0 then
            Rhylib.Weapons.Bolts.Spawn(owner, owner:GetShootPos(), owner:GetAimVector(),
                Rhylib.Config.Get("grapple", "hookSpeed"), 5)
        end
    end
    if SERVER then G.Fire(owner, self) end
end

function SWEP:SecondaryAttack()
    -- Right mouse is aim, handled in Think.
end

-- Spin-up ---------------------------------------------------------------

function SWEP:IsSpinning()
    return self.SpinUp ~= nil and self:GetSpinStart() > 0
end

function SWEP:SpunUp()
    if not self.SpinUp then return true end
    local start = self:GetSpinStart()
    return start > 0 and CurTime() - start >= self.SpinUp
end

-- Walk speed multiplier for this weapon right now (see sh_20_move.lua).
function SWEP:GetMoveMult()
    if self:IsSpinning() then return self.SpinMoveMult end
    return 1
end

-- Runs in Think: spin while the trigger is held and the gun could fire.
function SWEP:UpdateSpin(owner)
    if not self.SpinUp then return end
    local want = owner:KeyDown(IN_ATTACK) and not self:IsLowered() and not self:IsReloading()
        and not self:TooHeavyToFire() and self:Clip1() > 0
    local spinning = self:GetSpinStart() > 0
    if want and not spinning then
        self:SetSpinStart(CurTime())
        if IsFirstTimePredicted() and self.SpinSound then self:EmitSound(self.SpinSound, 70) end
    elseif not want and spinning then
        self:SetSpinStart(0)
    end
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

    -- Which magazine type a reload should load. magId: the type asked
    -- for, or nil for the best one. Returns a W.MagTypes entry or nil.
    function SWEP:ChooseMag(owner, magId)
        local W = Rhylib.Weapons
        local Pouch = W.Pouch
        local cur = self:GetMag()
        local full = self:Clip1() >= self:GetMagSize()

        local function usable(id)
            if not self:TakesMag(id) or Pouch.Count(owner, id) == 0 then return false end
            return not (full and cur and cur.id == id)  -- same type into a full gun does nothing
        end

        if magId then return usable(magId) and W.MagTypes[magId] or nil end
        if cur and usable(cur.id) then return cur end
        for i = 1, #self.Mags do
            if usable(self.Mags[i]) then return W.MagTypes[self.Mags[i]] end
        end
    end

    -- kind: 1 = magazine, 2 = power cell. magId: magazine type (nil = best).
    function SWEP:StartReload(kind, magId)
        if self:IsReloading() then return end
        local owner = self:GetOwner()
        if not IsValid(owner) or not owner:IsPlayer() then return end
        local W = Rhylib.Weapons

        if kind == RELOAD_MAG then
            local m = self:ChooseMag(owner, magId)
            if not m then return end
            self:SetReloadMag(m.index)
        elseif kind == RELOAD_CELL then
            if not self.UsesCell or W.Pouch.Count(owner, W.CELL) == 0 then return end
        else
            return
        end

        self:SendWeaponAnim(ACT_VM_RELOAD)
        local vm = owner:GetViewModel()
        local animTime = IsValid(vm) and vm:SequenceDuration() or 2
        local duration = self.ReloadTime or animTime
        local rate = animTime / duration
        if kind == RELOAD_CELL then
            duration = duration * self.CellReloadMult
            rate = rate / self.CellReloadMult
        end
        if IsValid(vm) and rate ~= 1 then vm:SetPlaybackRate(rate) end

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
        local W = Rhylib.Weapons
        local Pouch = W.Pouch

        local vm = owner:GetViewModel()
        if IsValid(vm) then vm:SetPlaybackRate(1) end

        if kind == RELOAD_MAG then
            local m = W.MagByIndex[self:GetReloadMag()]
            local best = m and Pouch.TakeBest(owner, m.id)
            if not best then return end
            -- The old magazine goes back into the inventory with what's left in it.
            local old = self:GetMag()
            if old and self:Clip1() > 0 then
                Pouch.Add(owner, old.id, self:Clip1() / old.rounds, true)
            end
            self:SetMagType(m.index)
            self:SetClip1(math.floor(best * m.rounds + 0.5))
        elseif kind == RELOAD_CELL then
            local best = Pouch.TakeBest(owner, W.CELL)
            if not best then return end
            local old = self:GetCell()
            if old > 0.001 then Pouch.Add(owner, W.CELL, old, true) end
            self:SetCell(best)
        end
    end

    -- Without the inventory addon, picking up the weapon gives its start ammo.
    -- With it, rhylib_inventory handles pickups (see sv_20_pouch.lua).
    function SWEP:Equip(owner)
        if Rhylib.Inventory and Rhylib.Inventory.AddItem then return end
        if not IsValid(owner) or not owner:IsPlayer() then return end
        Rhylib.Weapons.Pouch.GiveStartAmmo(owner, self, false)
    end
end

-- Clip, magazine type and cell are kept in the inventory item while the
-- weapon is stored.
function SWEP:GetInventoryData()
    return {
        clip = self:Clip1(),
        mag = self:GetMagType(),
        cell = self.UsesCell and self:GetCell() or nil,
        mode = self:GetFireMode(),
        safe = self:GetSafety() or nil,
    }
end

function SWEP:SetInventoryData(data)
    data = data or {}
    local W = Rhylib.Weapons
    local m = W.MagByIndex[data.mag or 0]
    if not (m and self:TakesMag(m.id)) then m = W.MagTypes[self.Mags[1]] end
    if m then self:SetMagType(m.index) end
    self:SetClip1(math.min(data.clip or self:GetMagSize(), self:GetMagSize()))
    if self.UsesCell then self:SetCell(data.cell or 1) end
    if data.mode and self.FireModes[data.mode] then self:SetFireMode(data.mode) end
    if data.safe then self:SetSafety(true) end
end

-- Actually sprinting: sprint held, on the ground and moving faster than
-- a walk. Going by speed means a player too tired to sprint (held to walking
-- speed by rhylib_stamina) keeps the gun up.
function SWEP:OwnerSprinting(owner)
    if not owner:KeyDown(IN_SPEED) or not owner:OnGround() then return false end
    local walk = owner:GetWalkSpeed() * 1.1
    return owner:GetVelocity():Length2DSqr() > walk * walk
end

function SWEP:UpdateLowered(owner)
    local sprint = self:OwnerSprinting(owner)
    if sprint == self:GetLowered() then return end
    self:SetLowered(sprint)
    if sprint then
        self:SetBurstLeft(0)
        self:SetAiming(false)
    else
        -- A short moment to bring the gun back up.
        self:SetNextPrimaryFire(math.max(self:GetNextPrimaryFire(), CurTime() + self.SprintRaiseTime))
    end
end

function SWEP:Think()
    local owner = self:GetOwner()
    if not IsValid(owner) or not owner:IsPlayer() then return end

    if SERVER and self:IsReloading() and CurTime() >= self:GetReloadEnd() then
        self:FinishReload()
    end

    -- Launchers load the next round by themselves once the shot is away.
    if SERVER and self.AutoReload and self:Clip1() <= 0 and not self:IsReloading()
        and CurTime() >= self:GetNextPrimaryFire() and not self:GetSafety()
        and CurTime() >= (self.autoReloadTry or 0) then
        self.autoReloadTry = CurTime() + 0.5  -- with no rounds left, don't recount every tick
        self:StartReload(RELOAD_MAG)
    end

    self:UpdateLowered(owner)
    self:UpdateSpin(owner)

    -- Trigger released: the next semi shot or burst may fire.
    if not self:GetTriggerReady() and not owner:KeyDown(IN_ATTACK) then
        self:SetTriggerReady(true)
    end

    -- Keep a burst going after the first shot.
    local left = self:GetBurstLeft()
    if left > 0 and CurTime() >= self:GetNextPrimaryFire() then
        if self:CanPrimaryAttack() then
            self:FireShot()
            left = left - 1
            if left == 0 then self:SetNextPrimaryFire(self:GetNextPrimaryFire() + self.BurstDelay) end
            self:SetBurstLeft(left)
        else
            self:SetBurstLeft(0)
        end
    end

    local want = owner:KeyDown(IN_ATTACK2) and not self:IsReloading() and not self:IsLowered()
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

    local ease = math.ease and math.ease.InOutSine or function(x) return x end

    function SWEP:GetViewModelPosition(pos, ang)
        local ft = FrameTime()
        self.aimFrac = math.Approach(self.aimFrac or 0, self:GetAiming() and 1 or 0, ft * 6)
        self.safeFrac = math.Approach(self.safeFrac or 0, self:IsLowered() and 1 or 0, ft * 5)

        local f = ease(self.aimFrac)
        if f > 0 then
            local off = self.AimPos * f
            pos = pos + ang:Right() * off.x + ang:Forward() * off.y + ang:Up() * off.z
        end

        -- On safety: gun lowered and turned inward.
        local sf = ease(self.safeFrac)
        if sf > 0 then
            pos = pos - ang:Up() * (4 * sf) + ang:Right() * (1.5 * sf) - ang:Forward() * (2 * sf)
            ang = Angle(ang.p, ang.y, ang.r)
            ang:RotateAroundAxis(ang:Right(), -20 * sf)
            ang:RotateAroundAxis(ang:Up(), 18 * sf)
        end
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
        if self:IsLowered() then return true end  -- no crosshair on safety or while sprinting
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

        -- One message under the crosshair at a time, most important first.
        local text, col, size
        local kind = self:GetReloadKind()
        if self:TooHeavyToFire() then
            text, col, size = "Too heavy to fire while flying", UI.Colors.bad, 20
        elseif kind ~= RELOAD_NONE then
            text, col, size = RELOAD_TEXT[kind], UI.Colors.textDim, 20
        elseif self:GetSafety() and not Rhylib.HUD then
            text, col, size = "Safety on", UI.Colors.textDim, 18
        end
        if text then
            draw.SimpleText(text, UI.Font(size), ScrW() * 0.5, ScrH() * 0.62, col, TEXT_ALIGN_CENTER)
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

    local handBone = {}

    function SWEP:DrawWorldModel(flags)
        local owner = self:GetOwner()
        if not self.PropModel or not IsValid(owner) then
            self:DrawModel(flags)
            return
        end

        -- Hand bone id per player model, so LookupBone runs once per model.
        local mdl = owner:GetModel() or ""
        local bone = handBone[mdl]
        if bone == nil then
            bone = owner:LookupBone("ValveBiped.Bip01_R_Hand") or false
            handBone[mdl] = bone
        end
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
