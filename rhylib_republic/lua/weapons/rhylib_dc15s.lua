--[[
    DC-15S blaster carbine.

    No power cell (per the design). Uses HL2 SMG models as placeholders
    until a DC-15S model pack is chosen: change ViewModel and WorldModel.
]]

SWEP.Base = "rhylib_base"
SWEP.PrintName = "DC-15S"
SWEP.Category = "Rhylib: Republic"
SWEP.Spawnable = true
SWEP.AdminOnly = false

SWEP.ViewModel = "models/weapons/c_smg1.mdl"
SWEP.WorldModel = "models/weapons/w_smg1.mdl"
SWEP.HoldType = "smg"
SWEP.Slot = 2

SWEP.Primary = {
    ClipSize = 50,
    DefaultClip = 200,
    Automatic = true,
    Ammo = "rhylib_blaster",
}

SWEP.FireRate = 600
SWEP.Damage = 25
SWEP.BoltSpeed = 7000
SWEP.BoltColor = 1
SWEP.FireSound = "weapons/airboat/airboat_gun_energy1.wav"

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
