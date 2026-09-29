--[[
    Base for pick-up items. Press E on it to pick it up.
    Derived items set ENT.Model and ENT:GiveTo(ply), which returns true
    if the player took it.

    Temporary: these feed the ammo pouch. The inventory module will turn
    them into real inventory items.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Rhylib item"
ENT.Category = "Rhylib"
ENT.Spawnable = false
ENT.Model = "models/items/boxmrounds.mdl"
ENT.PickupSound = "items/ammo_pickup.wav"

function ENT:Initialize()
    if CLIENT then return end
    self:SetModel(self.Model)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:Wake() end
end

if SERVER then
    function ENT:GiveTo(ply)
        return false
    end

    function ENT:Use(activator)
        if not IsValid(activator) or not activator:IsPlayer() then return end
        if self:GiveTo(activator) then
            activator:EmitSound(self.PickupSound, 60)
            self:Remove()
        else
            activator:PrintMessage(HUD_PRINTCENTER, "You can't carry any more of these")
        end
    end
end
