--[[
    Test dummy (admins, spawn menu: Rhylib Medical). A bot player that
    stands where you placed it and never moves or shoots, so everything
    that works on players works on it: damage, armour, going down,
    stabilising, dragging, revives, healing, the scoreboard.

    The entity itself is an invisible marker; the bot stands on it and
    comes back there 3 seconds after dying. Removing the marker (undo,
    remover tool, cleanup) kicks the bot. Each dummy takes a player slot.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Test dummy"
ENT.Category = "Rhylib Medical"
ENT.Spawnable = true
ENT.AdminOnly = true

local MODEL = "models/aussiwozzi/cgi/base/unassigned_cpt.mdl"
local MARKER = "models/hunter/blocks/cube025x025x025.mdl"

if CLIENT then
    function ENT:Draw() end  -- the marker is invisible; the bot is what you see
    return
end

local count = 0

function ENT:SpawnFunction(ply, tr, class)
    if not tr.Hit then return end
    local ent = ents.Create(class)
    ent:SetPos(tr.HitPos)
    ent:SetAngles(Angle(0, ply:EyeAngles().y + 180, 0))  -- facing you
    ent:Spawn()
    return ent
end

function ENT:Initialize()
    self:SetModel(MARKER)
    self:SetNoDraw(true)
    self:SetSolid(SOLID_NONE)
    self:SetMoveType(MOVETYPE_NONE)
    self:DrawShadow(false)

    if not player.CreateNextBot then
        self:Remove()
        return
    end
    count = count + 1
    local bot = player.CreateNextBot("Test dummy " .. count)
    if not IsValid(bot) then
        -- No free player slot.
        for _, p in ipairs(player.GetHumans()) do
            if p:IsAdmin() then p:ChatPrint("Test dummy: no free player slot") end
        end
        self:Remove()
        return
    end
    bot.rhylibDummy = self
    self.bot = bot
    -- The bot spawns on its own next tick; put it here once it has.
    timer.Simple(0.1, function()
        if IsValid(self) and IsValid(bot) then self:PlaceBot() end
    end)
end

function ENT:PlaceBot()
    local bot = self.bot
    if not IsValid(bot) then return end
    if not bot:Alive() then bot:Spawn() end
    bot:StripWeapons()
    bot:SetModel(MODEL)
    bot:SetPos(self:GetPos())
    bot:SetEyeAngles(self:GetAngles())
    bot:SetVelocity(-bot:GetVelocity())
end

function ENT:OnRemove()
    local bot = self.bot
    if IsValid(bot) then bot:Kick("Test dummy removed") end
end

local function dummyOf(ply)
    local ent = ply.rhylibDummy
    return IsValid(ent) and ent or nil
end

-- Stand still: no movement, no buttons, no turning.
Rhylib.Hook.Add("StartCommand", "dummy.still", function(ply, cmd)
    if not ply:IsBot() or not dummyOf(ply) then return end
    cmd:ClearMovement()
    cmd:ClearButtons()
end, -200)

-- Every spawn: back on the marker, with the dummy model and no weapons.
Rhylib.Hook.Add("PlayerSpawn", "dummy.place", function(ply)
    local ent = ply:IsBot() and dummyOf(ply)
    if not ent then return end
    timer.Simple(0, function()
        if IsValid(ent) and IsValid(ply) then ent:PlaceBot() end
    end)
end, 100)

Rhylib.Hook.Add("PlayerSetModel", "dummy.model", function(ply)
    if ply:IsBot() and dummyOf(ply) then
        ply:SetModel(MODEL)
        return true
    end
end)

-- Back up 3 seconds after dying.
Rhylib.Hook.Add("PlayerDeath", "dummy.respawn", function(ply)
    local ent = ply:IsBot() and dummyOf(ply)
    if not ent then return end
    timer.Simple(3, function()
        if IsValid(ent) and IsValid(ply) and not ply:Alive() then ent:PlaceBot() end
    end)
end)

-- The bot left (kicked, map change): remove its marker too.
Rhylib.Hook.Add("PlayerDisconnected", "dummy.cleanup", function(ply)
    local ent = ply.rhylibDummy
    if IsValid(ent) then
        ent.bot = nil
        ent:Remove()
    end
end)
