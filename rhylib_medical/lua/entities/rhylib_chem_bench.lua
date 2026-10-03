--[[
    Chemistry bench (med bay). Chemist medics (skill Chemistry) press E to
    turn medical supplies into stims, burn gel, painkillers, splints,
    blood packs and medkits (config medical chemRecipes). Logic:
    rhylib_medical sv_40_medbay.lua. Saved per map with
    rhylib_medical_save.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Chemistry bench"
ENT.Category = "Rhylib Medical"
ENT.Spawnable = true
ENT.AdminOnly = true

local FALLBACK = "models/props_c17/FurnitureTable001a.mdl"

function ENT:SpawnFunction(ply, tr, class)
    if not tr.Hit then return end
    local ent = ents.Create(class)
    ent:SetPos(tr.HitPos)
    ent:SetAngles(Angle(0, ply:EyeAngles().y + 180, 0))
    ent:Spawn()
    ent:SetPos(tr.HitPos - Vector(0, 0, ent:OBBMins().z))
    return ent
end

function ENT:Initialize()
    if CLIENT then return end
    local Med = Rhylib.Medical
    local m = Med and Med.Cfg("benchModel") or FALLBACK
    if not isstring(m) or not util.IsValidModel(m) then m = FALLBACK end
    self:SetModel(m)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:EnableMotion(false) end
end

if SERVER then
    function ENT:Use(ply)
        local Med = Rhylib.Medical
        if Med and Med.BenchUse and IsValid(ply) and ply:IsPlayer() then Med.BenchUse(self, ply) end
    end
end

if CLIENT then
    function ENT:Draw()
        self:DrawModel()
        local Med = Rhylib.Medical
        if Med and Med.DrawEntLabel then Med.DrawEntLabel(self, "Chemistry bench", "Chemists · Press E") end
    end
end
