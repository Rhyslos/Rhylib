AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "rhylib_item_base"
ENT.PrintName = "Blaster magazine"
ENT.Category = "Rhylib"
ENT.Spawnable = true
ENT.Model = "models/items/boxmrounds.mdl"  -- placeholder

if SERVER then
    function ENT:GiveTo(ply)
        return Rhylib.Weapons.Pouch.Add(ply, "mags", 1)
    end
end
