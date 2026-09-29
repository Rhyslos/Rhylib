AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "rhylib_item_base"
ENT.PrintName = "Power cell"
ENT.Category = "Rhylib"
ENT.Spawnable = true
ENT.Model = "models/items/battery.mdl"  -- placeholder
ENT.PickupSound = "items/battery_pickup.wav"

if SERVER then
    function ENT:GiveTo(ply)
        return Rhylib.Weapons.Pouch.Add(ply, "cells", 1)
    end
end
