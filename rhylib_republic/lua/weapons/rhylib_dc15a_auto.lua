--[[
    DC-15A (Auto): the DC-15A locked to full auto, for testing.
    Everything else comes from rhylib_dc15a.
]]

AddCSLuaFile()

SWEP.Base = "rhylib_dc15a"
SWEP.PrintName = "DC-15A (Auto)"
SWEP.Category = "Rhylib: Republic"
SWEP.Spawnable = true
SWEP.AdminOnly = false

SWEP.FireModes = { "auto" }
SWEP.SkillModes = nil
SWEP.FireRate = 450
SWEP.Recoil = { up = 0.7, side = 0.3, bias = 0.2, recover = 0.6, aimMult = 0.6 }  -- view kick per shot
