--[[
    DC-15A blaster rifle. Uses a magazine and a power cell.
    Semi-auto by default (full auto comes from the Autorifleman skill later).

    Uses a prop model (models/jajoff/sps/cgiweapons/tc13j/dc15a.mdl), so it
    has no arms in first person. The model's addon must be installed.
    Tune the Prop* offsets below; saving this file updates them in game.
    All numbers are first guesses for tuning.
]]

AddCSLuaFile()

SWEP.Base = "rhylib_base"
SWEP.PrintName = "DC-15A"
SWEP.Category = "Rhylib: Republic"
SWEP.Spawnable = true
SWEP.AdminOnly = false

-- The placeholder viewmodel is hidden but still drives the reload timing.
SWEP.ViewModel = "models/weapons/c_irifle.mdl"
SWEP.WorldModel = "models/jajoff/sps/cgiweapons/tc13j/dc15a.mdl"
SWEP.UseHands = false
SWEP.HoldType = "ar2"
SWEP.Slot = 2

SWEP.PropModel = "models/jajoff/sps/cgiweapons/tc13j/dc15a.mdl"
SWEP.PropScale = 1
SWEP.PropVMPos = Vector(18, 7, -8)     -- forward, right, up (first person)
SWEP.PropVMAng = Angle(0, 0, 0)        -- pitch, yaw, roll
SWEP.PropWMPos = Vector(5, 1, -3)      -- forward, right, up from the right hand
SWEP.PropWMAng = Angle(-10, 0, 180)
SWEP.PropMuzzle = Vector(32, 0, 2)     -- muzzle in the prop's own coordinates (longer rifle)

SWEP.Primary = {
    ClipSize = 60,
    DefaultClip = 60,
    Automatic = true,       -- must stay true; FireModes decides
    Ammo = "rhylib_mag_medium",
}
SWEP.Secondary = {
    ClipSize = -1,
    DefaultClip = -1,
    Automatic = true,
    Ammo = "rhylib_cell",   -- shows spare cells on the HUD
}

SWEP.FireRate = 400
SWEP.Recoil = { up = 0.9, side = 0.2, bias = 0.15, recover = 0.7, aimMult = 0.6 }  -- view kick per shot
SWEP.Damage = 35
SWEP.BoltSpeed = 8000
SWEP.BoltColor = 1
SWEP.FireSound = "weapons/airboat/airboat_gun_energy2.wav"

-- Magazines it takes, preferred first.
SWEP.Mags = { "mag_medium", "mag_small" }

SWEP.Grapple = true     -- grapple fire mode while carrying a grapple hook
SWEP.FireModes = { "semi" }

SWEP.UsesCell = true
SWEP.CellShots = 500
SWEP.CellReloadMult = 1.6
SWEP.StartMags = 8
SWEP.StartCells = 1

-- Inventory size in cells
SWEP.InvW = 5
SWEP.InvH = 1
SWEP.InvLarge = true
SWEP.InvWeight = 5.0         -- kg

SWEP.Spread = {
    hip = 1.1,
    aim = 0.45,
    kickMain = 0.45,
    kickSide = 0.12,
    bloomPerShot = 0.15,
    bloomMax = 2.0,
    aimKickMult = 0.5,
    aimOffsetMult = 0.6,
}

SWEP.AimPos = Vector(-2.5, 0, 1)
SWEP.AimFov = 0.8
