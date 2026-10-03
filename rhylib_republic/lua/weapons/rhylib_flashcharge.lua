-- Flash charge (military police, rhylib_skills Flash charge): a short
-- fuse, then a blinding flash. Players in sight are stunned (rhylib_mp),
-- droids aim much worse for a few seconds. No damage.
AddCSLuaFile()
SWEP.Base = "rhylib_grenade_base"
SWEP.PrintName = "Flash charge"
SWEP.Category = "Rhylib: Republic"
SWEP.Spawnable = true
SWEP.GrenadeKind = "flash"
SWEP.FuseTime = 1.5
SWEP.PropColor = Color(235, 235, 200)
SWEP.RequiresSkill = "flash_charge"
SWEP.CarrySkill = "flash_charge"
SWEP.SkillName = "Flash charge"
