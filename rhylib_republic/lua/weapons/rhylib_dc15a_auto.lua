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
SWEP.FireRate = 450
