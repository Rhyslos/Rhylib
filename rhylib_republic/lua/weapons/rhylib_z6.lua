--[[
    Z-6 rotary blaster cannon. Large or small magazines plus a power cell.
    Hold fire to spin the barrels up (SpinUp seconds) before it fires;
    you walk slower while it spins. Too heavy to fire while flying.

    Uses a prop model (models/jajoff/sps/cgiweapons/tc13j/z6.mdl), so it
    has no arms in first person. The model's addon must be installed.
    Tune the Prop* offsets below; saving this file updates them in game.
    All numbers are first guesses for tuning.
]]

AddCSLuaFile()

SWEP.Base = "rhylib_base"
SWEP.PrintName = "Z-6"
SWEP.Category = "Rhylib: Republic"
SWEP.Spawnable = true
SWEP.AdminOnly = false

-- The placeholder viewmodel is hidden but still drives the reload timing.
SWEP.ViewModel = "models/weapons/c_shotgun.mdl"
SWEP.WorldModel = "models/jajoff/sps/cgiweapons/tc13j/z6.mdl"
SWEP.UseHands = false
SWEP.HoldType = "shotgun"
SWEP.Slot = 3

SWEP.PropModel = "models/jajoff/sps/cgiweapons/tc13j/z6.mdl"
SWEP.PropScale = 1
SWEP.PropVMPos = Vector(20, 8, -10)    -- forward, right, up (first person)
SWEP.PropVMAng = Angle(0, 0, 0)        -- pitch, yaw, roll
SWEP.PropWMPos = Vector(6, 1, -3)      -- forward, right, up from the right hand
SWEP.PropWMAng = Angle(-10, 0, 180)
SWEP.PropMuzzle = Vector(36, 0, 0)     -- muzzle in the prop's own coordinates

SWEP.Primary = {
    ClipSize = 250,
    DefaultClip = 250,
    Automatic = true,       -- must stay true; FireModes decides
    Ammo = "rhylib_mag_large",
}
SWEP.Secondary = {
    ClipSize = -1,
    DefaultClip = -1,
    Automatic = true,
    Ammo = "rhylib_cell",
}

SWEP.FireRate = 900
SWEP.Damage = 18
SWEP.BoltSpeed = 7500
SWEP.BoltColor = 1
SWEP.FireSound = "weapons/airboat/airboat_gun_energy2.wav"

SWEP.Mags = { "mag_large", "mag_small" }
SWEP.FireModes = { "auto" }
SWEP.ReloadTime = 3.2

SWEP.SpinUp = 0.6
SWEP.SpinMoveMult = 0.6
SWEP.SpinSound = "weapons/physcannon/physcannon_charge.wav"  -- placeholder

SWEP.UsesCell = true
SWEP.CellShots = 1000
SWEP.CellReloadMult = 1.3
SWEP.StartMags = 3
SWEP.StartCells = 1

-- Inventory size in cells
SWEP.InvW = 5
SWEP.InvH = 1
SWEP.InvLarge = true
SWEP.InvWeight = 11          -- kg

SWEP.Spread = {
    hip = 2.2,
    aim = 1.4,
    kickMain = 0.25,
    kickSide = 0.1,
    bloomPerShot = 0.06,
    bloomMax = 2.4,
    aimKickMult = 0.6,
    aimOffsetMult = 0.7,
}

SWEP.AimPos = Vector(-1.5, 0, 0.5)
SWEP.AimFov = 0.92
