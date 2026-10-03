-- Thermal detonator: explodes 3 seconds after the throw.
AddCSLuaFile()
SWEP.Base = "rhylib_grenade_base"
SWEP.PrintName = "Thermal detonator"
SWEP.Category = "Rhylib: Republic"
SWEP.Spawnable = true
SWEP.GrenadeKind = "fuse"
SWEP.FuseTime = 3
SWEP.ImpactMode = true   -- E + R switches between timed and impact
