--[[
    RPS-6 rocket launcher. One rocket at a time, unguided.
    The rocket is a slow explosive bolt: blast damage where it hits.
    Reloads by itself after each shot if you carry rockets.
    Too heavy to fire while flying.

    Uses a prop model (models/jajoff/sps/cgiweapons/tc13j/rps.mdl), so it
    has no arms in first person. The model's addon must be installed.
    Tune the Prop* offsets below; saving this file updates them in game.
    All numbers are first guesses for tuning.
]]

AddCSLuaFile()

SWEP.Base = "rhylib_base"
SWEP.PrintName = "RPS-6"
SWEP.Category = "Rhylib: Republic"
SWEP.Spawnable = true
SWEP.AdminOnly = false

-- The placeholder viewmodel is hidden; ReloadTime sets the reload length.
SWEP.ViewModel = "models/weapons/c_rpg.mdl"
SWEP.WorldModel = "models/jajoff/sps/cgiweapons/tc13j/rps.mdl"
SWEP.UseHands = false
SWEP.HoldType = "rpg"
SWEP.Slot = 4

SWEP.PropModel = "models/jajoff/sps/cgiweapons/tc13j/rps.mdl"
SWEP.PropScale = 1
SWEP.PropVMPos = Vector(16, 8, -6)     -- forward, right, up (first person)
SWEP.PropVMAng = Angle(0, 0, 0)        -- pitch, yaw, roll
SWEP.PropWMPos = Vector(4, 2, -2)      -- forward, right, up from the right hand
SWEP.PropWMAng = Angle(-10, 0, 180)
SWEP.PropMuzzle = Vector(30, 0, 4)     -- muzzle in the prop's own coordinates

SWEP.Primary = {
    ClipSize = 1,
    DefaultClip = 1,
    Automatic = true,       -- must stay true; FireModes decides
    Ammo = "rhylib_rocket",
}

SWEP.FireRate = 60
SWEP.Damage = 0               -- all damage comes from the blast
SWEP.BoltSpeed = 2200
SWEP.BoltColor = 4            -- rocket look
SWEP.BoltLife = 5
SWEP.FireSound = "weapons/rpg/rocketfire1.wav"

SWEP.Explosive = { radius = 200, damage = 250 }

SWEP.Mags = { "rocket" }
SWEP.FireModes = { "semi" }
SWEP.ReloadTime = 3
SWEP.AutoReload = true

SWEP.UsesCell = false
SWEP.StartMags = 3
SWEP.StartCells = 0

-- Inventory size in cells
SWEP.InvW = 5
SWEP.InvH = 1
SWEP.InvLarge = true
SWEP.InvWeight = 9           -- kg

SWEP.Spread = {
    hip = 0.8,
    aim = 0.25,
    kickMain = 1.2,
    kickSide = 0.5,
    bloomPerShot = 0.5,
    bloomMax = 1.5,
    aimKickMult = 0.5,
    aimOffsetMult = 0.6,
}

SWEP.AimPos = Vector(-2, 0, 1)
SWEP.AimFov = 0.75
