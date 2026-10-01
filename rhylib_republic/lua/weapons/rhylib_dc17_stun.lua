--[[
    DC-17 stun variant (military police). Same gun, but it fires slow blue
    stun rings that do no damage: a hit makes the target collapse for a
    few seconds (rhylib_mp), so they can be cuffed.
]]

AddCSLuaFile()

SWEP.Base = "rhylib_dc17"
SWEP.PrintName = "DC-17 (stun)"
SWEP.Category = "Rhylib: Republic"
SWEP.Spawnable = true

SWEP.Stun = true
SWEP.Grapple = false
SWEP.Damage = 0
SWEP.BoltSpeed = 2600
SWEP.BoltColor = 6
SWEP.FireRate = 90           -- one ring every 2/3 s
SWEP.Recoil = { up = 0.5, side = 0.15, bias = 0, recover = 0.8, aimMult = 0.7 }  -- view kick per shot
SWEP.FireModes = { "semi" }
SWEP.FireSound = "weapons/stunstick/spark1.wav"
