-- Droid popper: EMP grenade. Kills Rhylib droids in range after a short
-- fuse; harmless to everything else.
AddCSLuaFile()
SWEP.Base = "rhylib_grenade_base"
SWEP.PrintName = "Droid popper"
SWEP.Category = "Rhylib: Republic"
SWEP.Spawnable = true
SWEP.GrenadeKind = "emp"
SWEP.FuseTime = 2
SWEP.PropColor = Color(130, 180, 255)
SWEP.RequiresSkill = "droid_popper"   -- (rhylib_skills: needed to throw it)
SWEP.CarrySkill = "droid_popper"      -- and to carry it at all
SWEP.SkillName = "Droid popper"
