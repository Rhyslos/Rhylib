--[[
    DC-15S stun variant (military police). Fires slow blue stun rings that
    do no damage: a hit makes the target collapse for a few seconds
    (rhylib_mp), so they can be cuffed.
]]

AddCSLuaFile()

SWEP.Base = "rhylib_dc15s"
SWEP.PrintName = "DC-15S (stun)"
SWEP.Category = "Rhylib: Republic"
SWEP.Spawnable = true

SWEP.Stun = true
SWEP.Grapple = false
SWEP.Damage = 0
SWEP.BoltSpeed = 2600
SWEP.BoltColor = 6
SWEP.FireRate = 75           -- one ring every 0.8 s
SWEP.FireModes = { "semi" }
SWEP.FireSound = "weapons/stunstick/spark2.wav"
