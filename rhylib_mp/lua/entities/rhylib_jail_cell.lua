--[[
    Jail cell marker (admins place it where a prisoner should stand, then
    rhylib_mp_save). Invisible to normal players; MPs and admins see a
    faint ring.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Jail cell"
ENT.Category = "Rhylib: Military police"
ENT.Spawnable = true
ENT.AdminOnly = true

function ENT:Initialize()
    self:SetModel("models/hunter/plates/plate1x1.mdl")
    self:DrawShadow(false)
    if SERVER then
        self:SetSolid(SOLID_NONE)
        self:SetMoveType(MOVETYPE_NONE)
    end
end

if SERVER then
    function ENT:SpawnFunction(ply, tr, class)
        if not tr.Hit then return end
        local e = ents.Create(class)
        e:SetPos(tr.HitPos + Vector(0, 0, 1))
        e:SetAngles(Angle(0, ply:EyeAngles().y + 180, 0))
        e:Spawn()
        return e
    end
else
    local matRing = Material("effects/select_ring")
    local col = Color(120, 200, 255, 120)
    function ENT:Draw()
        local ply = LocalPlayer()
        if not (ply:IsAdmin() or (Rhylib.MP and Rhylib.MP.IsMP(ply))) then return end
        render.SetMaterial(matRing)
        render.DrawQuadEasy(self:GetPos() + Vector(0, 0, 1), Vector(0, 0, 1), 48, 48, col, 0)
    end
end
