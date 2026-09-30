--[[
    DC-17 blaster pistol. Small magazines only, no power cell.

    Uses a prop model (models/jajoff/sps/cgiweapons/tc13j/dc17.mdl), so it
    has no arms in first person. The model's addon must be installed.
    Tune the Prop* offsets below; saving this file updates them in game.
    All numbers are first guesses for tuning.
]]

AddCSLuaFile()

SWEP.Base = "rhylib_base"
SWEP.PrintName = "DC-17"
SWEP.Category = "Rhylib: Republic"
SWEP.Spawnable = true
SWEP.AdminOnly = false

-- The placeholder viewmodel is hidden but still drives the reload timing.
SWEP.ViewModel = "models/weapons/c_pistol.mdl"
SWEP.WorldModel = "models/jajoff/sps/cgiweapons/tc13j/dc17.mdl"
SWEP.UseHands = false
SWEP.HoldType = "pistol"
SWEP.Slot = 1

SWEP.PropModel = "models/jajoff/sps/cgiweapons/tc13j/dc17.mdl"
SWEP.PropScale = 1
SWEP.PropVMPos = Vector(16, 6, -6)     -- forward, right, up (first person)
SWEP.PropVMAng = Angle(0, 0, 0)        -- pitch, yaw, roll
SWEP.PropWMPos = Vector(4, 1, -2)      -- forward, right, up from the right hand
SWEP.PropWMAng = Angle(-10, 0, 180)
SWEP.PropMuzzle = Vector(10, 0, 2)     -- muzzle in the prop's own coordinates

SWEP.Primary = {
    ClipSize = 30,
    DefaultClip = 30,
    Automatic = true,       -- must stay true; FireModes decides
    Ammo = "rhylib_mag_small",
}

SWEP.FireRate = 400
SWEP.Damage = 28
SWEP.BoltSpeed = 7000
SWEP.BoltColor = 1
SWEP.FireSound = "weapons/airboat/airboat_gun_energy1.wav"

SWEP.Mags = { "mag_small" }
SWEP.Grapple = true     -- grapple fire mode while carrying a grapple hook
SWEP.FireModes = { "semi" }

SWEP.UsesCell = false
SWEP.StartMags = 4
SWEP.StartCells = 0

-- Inventory size in cells
SWEP.InvW = 2
SWEP.InvH = 1
SWEP.InvLarge = false
SWEP.InvWeight = 1.0         -- kg

SWEP.Spread = {
    hip = 1.2,
    aim = 0.6,
    kickMain = 0.4,
    kickSide = 0.1,
    bloomPerShot = 0.14,
    bloomMax = 1.8,
    aimKickMult = 0.5,
    aimOffsetMult = 0.6,
}

SWEP.AimPos = Vector(-2, 0, 1)
SWEP.AimFov = 0.9
