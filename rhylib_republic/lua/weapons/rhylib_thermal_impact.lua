-- Impact thermal detonator: explodes on the first hit.
AddCSLuaFile()
SWEP.Base = "rhylib_grenade_base"
SWEP.PrintName = "Impact detonator"
SWEP.Category = "Rhylib: Republic"
SWEP.Spawnable = false   -- (retired: the thermal detonator has an impact mode, E + R)
SWEP.GrenadeKind = "impact"
SWEP.PropColor = Color(255, 190, 150)
