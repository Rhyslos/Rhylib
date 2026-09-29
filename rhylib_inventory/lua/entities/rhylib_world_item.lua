--[[
    An inventory item lying in the world (dropped by a player).
    Press E to pick it up. Anything that doesn't fit stays on the ground.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Item"
ENT.Spawnable = false

local FALLBACK_MODEL = "models/props_junk/cardboard_box004a.mdl"

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "ItemName")
    self:NetworkVar("Int", 0, "ItemCount")
end

if SERVER then
    -- Call before Spawn().
    function ENT:SetItem(id, count, data)
        self.itemId = id
        self.itemCount = count or 1
        self.itemData = data and table.Copy(data) or {}
    end

    function ENT:Initialize()
        local def = Rhylib.Items.Get(self.itemId or "")
        local model = def and def.model
        if not model or not util.IsValidModel(model) then model = FALLBACK_MODEL end

        self:SetModel(model)
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetUseType(SIMPLE_USE)
        self:SetCollisionGroup(COLLISION_GROUP_WEAPON)  -- players walk through it
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:Wake() end

        self:SetItemName(def and def.name or "Unknown item")
        self:SetItemCount(self.itemCount or 1)
    end

    function ENT:Use(ply)
        if not IsValid(ply) or not ply:IsPlayer() or not self.itemId then return end
        local left = Rhylib.Inventory.AddItem(ply, self.itemId, self.itemCount, self.itemData)
        if left <= 0 then
            ply:EmitSound("items/ammo_pickup.wav", 60)
            self:Remove()
        elseif left < self.itemCount then
            self.itemCount = left
            self:SetItemCount(left)
            ply:EmitSound("items/ammo_pickup.wav", 60)
        else
            ply:PrintMessage(HUD_PRINTCENTER, "No room in your inventory")
        end
    end
end

if CLIENT then
    -- Show the name when looking at it up close.
    function ENT:Draw()
        self:DrawModel()
        local ply = LocalPlayer()
        if ply:GetEyeTrace().Entity ~= self or ply:GetPos():DistToSqr(self:GetPos()) > 150 * 150 then return end

        local count = self:GetItemCount()
        local text = self:GetItemName() .. (count > 1 and (" x" .. count) or "")
        local pos = self:GetPos() + Vector(0, 0, self:OBBMaxs().z + 6)
        local ang = Angle(0, ply:EyeAngles().y - 90, 90)
        cam.Start3D2D(pos, ang, 0.1)
            draw.SimpleTextOutlined(text, Rhylib.UI.Font(24), 0, 0, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
        cam.End3D2D()
    end
end
