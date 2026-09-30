--[[
    DC-15S blaster carbine. Magazine only, no power cell.

    Uses a prop model (models/jajoff/sps/cgiweapons/tc13j/dc15s.mdl), so
    it has no arms in first person. The model's addon must be installed.
    Tune the Prop* offsets below; saving this file updates them in game.
]]

AddCSLuaFile()

SWEP.Base = "rhylib_base"
SWEP.PrintName = "DC-15S"
SWEP.Category = "Rhylib: Republic"
SWEP.Spawnable = true
SWEP.AdminOnly = false

-- The placeholder viewmodel is hidden but still drives the reload timing.
SWEP.ViewModel = "models/weapons/c_smg1.mdl"
SWEP.WorldModel = "models/jajoff/sps/cgiweapons/tc13j/dc15s.mdl"
SWEP.UseHands = false
SWEP.HoldType = "smg"
SWEP.Slot = 2

SWEP.PropModel = "models/jajoff/sps/cgiweapons/tc13j/dc15s.mdl"
SWEP.PropScale = 1
SWEP.PropVMPos = Vector(18, 7, -8)     -- forward, right, up (first person)
SWEP.PropVMAng = Angle(0, 0, 0)        -- pitch, yaw, roll
SWEP.PropWMPos = Vector(5, 1, -3)      -- forward, right, up from the right hand
SWEP.PropWMAng = Angle(-10, 0, 180)
SWEP.PropMuzzle = Vector(20, 0, 2)     -- muzzle in the prop's own coordinates

SWEP.Primary = {
    ClipSize = 50,
    DefaultClip = 50,
    Automatic = true,
    Ammo = "rhylib_blaster",
}

SWEP.FireRate = 600
SWEP.Damage = 25
SWEP.BoltSpeed = 7000
SWEP.BoltColor = 1
SWEP.FireSound = "weapons/airboat/airboat_gun_energy1.wav"

-- Semi first (default), switch with E + R.
SWEP.FireModes = { "semi", "auto" }

SWEP.UsesCell = false
SWEP.StartMags = 4
SWEP.StartCells = 0

-- Inventory size in cells
SWEP.InvW = 3
SWEP.InvH = 1
SWEP.InvLarge = false

SWEP.Spread = {
    hip = 1.4,
    aim = 0.7,
    kickMain = 0.35,
    kickSide = 0.1,
    bloomPerShot = 0.11,
    bloomMax = 2.0,
    aimKickMult = 0.5,
    aimOffsetMult = 0.6,
}

SWEP.AimPos = Vector(-2, 0, 1)
SWEP.AimFov = 0.85
