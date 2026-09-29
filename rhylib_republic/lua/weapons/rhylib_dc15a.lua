--[[
    DC-15A blaster rifle. Uses a magazine and a power cell.
    Semi-auto by default (full auto comes from the Autorifleman skill later).

    Added now mainly to test power cell reloads. HL2 pulse rifle models
    are placeholders; all numbers are first guesses for tuning.
]]

AddCSLuaFile()

SWEP.Base = "rhylib_base"
SWEP.PrintName = "DC-15A"
SWEP.Category = "Rhylib: Republic"
SWEP.Spawnable = true
SWEP.AdminOnly = false

SWEP.ViewModel = "models/weapons/c_irifle.mdl"
SWEP.WorldModel = "models/weapons/w_irifle.mdl"
SWEP.UseHands = true
SWEP.HoldType = "ar2"
SWEP.Slot = 2

SWEP.Primary = {
    ClipSize = 30,
    DefaultClip = 30,
    Automatic = false,
    Ammo = "rhylib_blaster",
}
SWEP.Secondary = {
    ClipSize = -1,
    DefaultClip = -1,
    Automatic = true,
    Ammo = "rhylib_cell",   -- shows spare cells on the HUD
}

SWEP.FireRate = 400
SWEP.Damage = 35
SWEP.BoltSpeed = 8000
SWEP.BoltColor = 1
SWEP.FireSound = "weapons/airboat/airboat_gun_energy2.wav"

SWEP.UsesCell = true
SWEP.CellShots = 500
SWEP.CellReloadMult = 1.6
SWEP.StartMags = 4
SWEP.StartCells = 1

-- Inventory size in cells
SWEP.InvW = 5
SWEP.InvH = 1
SWEP.InvLarge = true

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
