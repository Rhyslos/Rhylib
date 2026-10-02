--[[
    Test dummy (admins, spawn menu: Rhylib Medical). A bot player that
    stands where you placed it and never moves or shoots, so everything
    that works on players works on it: damage, armour, going down,
    stabilising, dragging, revives, healing, the scoreboard.

    The entity itself is an invisible marker; the bot stands on it and
    comes back there 3 seconds after dying. Removing the marker (undo,
    remover tool, cleanup) kicks the bot. Each dummy takes a player slot.

    rhylib_dummy_move still|walk|run (admins): every dummy stands still,
    or walks / runs back and forth (turning every 2.5 s), for testing
    falls and moving targets.
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

    -- Bots need a multiplayer game (a local game with 2+ player slots).
    if game.SinglePlayer() or not player.CreateNextBot then
        for _, p in ipairs(player.GetHumans()) do
            if p:IsAdmin() then p:ChatPrint("Test dummy: needs a multiplayer game. Start your local game with 2 or more player slots.") end
        end
        self:Remove()
        return
    end
    count = count + 1
    -- (pcall: the engine errors instead of returning nil in some setups)
    local ok, bot = pcall(player.CreateNextBot, "Test dummy " .. count)
    if not ok or not IsValid(bot) then
        local why = (not ok and string.find(tostring(bot), "singleplayer", 1, true))
            and "needs a multiplayer game. Start your local game with 2 or more player slots."
            or "no free player slot"
        for _, p in ipairs(player.GetHumans()) do
            if p:IsAdmin() then p:ChatPrint("Test dummy: " .. why) end
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

DUMMY_MOVE = DUMMY_MOVE or "still"   -- still, walk, run (all dummies)

-- Stand still, or walk/run back and forth from the marker's facing.
Rhylib.Hook.Add("StartCommand", "dummy.still", function(ply, cmd)
    if not ply:IsBot() then return end
    local ent = dummyOf(ply)
    if not ent then return end
    cmd:ClearMovement()
    cmd:ClearButtons()
    if DUMMY_MOVE == "still" then return end
    local back = math.floor(CurTime() / 2.5) % 2 == 1
    cmd:SetViewAngles(Angle(0, ent:GetAngles().y + (back and 180 or 0), 0))
    cmd:SetForwardMove(10000)
    if DUMMY_MOVE == "run" then cmd:SetButtons(IN_SPEED) end
end, -200)

concommand.Add("rhylib_dummy_move", function(ply, _, args)
    if IsValid(ply) and not ply:IsAdmin() then return end
    local m = string.lower(args[1] or "")
    if m ~= "still" and m ~= "walk" and m ~= "run" then
        local msg = "rhylib_dummy_move still|walk|run (now: " .. DUMMY_MOVE .. ")"
        if IsValid(ply) then ply:ChatPrint(msg) else print(msg) end
        return
    end
    DUMMY_MOVE = m
    if IsValid(ply) then ply:ChatPrint("Test dummies: " .. m) end
end)

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
