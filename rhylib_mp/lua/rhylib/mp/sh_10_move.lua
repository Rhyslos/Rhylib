--[[
    Movement and pose (shared, runs in prediction).

    Stunned: no input at all, lying in a death pose (last frame).
    Cuffed:  slow walk, no sprint, jump, crouch, attack or use. Escorted
             prisoners are pulled toward the MP when they fall behind.
]]

local MP = Rhylib.MP
local band, bor, bnot = bit.band, bit.bor, bit.bnot

local CUFF_STRIP = bor(IN_ATTACK, IN_ATTACK2, IN_RELOAD, IN_USE, IN_SPEED, IN_JUMP, IN_DUCK, IN_ZOOM)

-- Stunned view: facing where they fell, a little up/down look.
local function stunView(ply, ang)
    return Angle(math.Clamp(math.NormalizeAngle(ang.p), -25, 35), ply:GetNW2Float("rhylib_stunYaw", 0), 0)
end

Rhylib.Hook.Add("StartCommand", "mp.input", function(ply, cmd)
    if MP.IsStunned(ply) then
        cmd:ClearButtons()
        cmd:ClearMovement()
        cmd:SetViewAngles(stunView(ply, cmd:GetViewAngles()))
    elseif MP.IsCuffed(ply) then
        cmd:RemoveKey(CUFF_STRIP)
    end
end, -150)

if CLIENT then
    Rhylib.Hook.Add("CreateMove", "mp.stunview", function(cmd)
        local ply = LocalPlayer()
        if IsValid(ply) and MP.IsStunned(ply) then cmd:SetViewAngles(stunView(ply, cmd:GetViewAngles())) end
    end)
end

Rhylib.Hook.Add("SetupMove", "mp.move", function(ply, mv)
    if MP.IsStunned(ply) then
        mv:SetForwardSpeed(0)
        mv:SetSideSpeed(0)
        mv:SetUpSpeed(0)
        mv:SetButtons(0)
        return
    end
    if not MP.IsCuffed(ply) then return end
    mv:SetButtons(band(mv:GetButtons(), bnot(CUFF_STRIP)))
    mv:SetMaxClientSpeed(math.min(mv:GetMaxClientSpeed(), MP.Cfg("cuffWalk")))
    -- Escort: walk toward the MP when too far behind.
    local by = MP.EscortedBy(ply)
    if by then
        local to = by:GetPos() - ply:GetPos()
        to.z = 0
        local dist = to:Length()
        if dist > MP.Cfg("escortLeash") then
            local speed = math.min(by:GetVelocity():Length2D() + 60, 260)
            local v = to / dist * speed
            local cur = mv:GetVelocity()
            mv:SetVelocity(Vector(v.x, v.y, cur.z))
            mv:SetMaxClientSpeed(speed)
            mv:SetMaxSpeed(speed)
        end
    end
end, -95)

-- No switching weapons while cuffed or stunned.
Rhylib.Hook.Add("PlayerSwitchWeapon", "mp.noswitch", function(ply, old, new)
    if (MP.IsCuffed(ply) or MP.IsStunned(ply)) and not (IsValid(new) and new.IsRhylibStowed) then return true end
end)

--------------------------------------------------------------------------
-- Lying pose while stunned (same on server and client, so hitboxes match)
--------------------------------------------------------------------------

local function stunSequence(ply)
    local mdl = ply:GetModel()
    if ply.rhylibStunMdl ~= mdl then
        ply.rhylibStunMdl = mdl
        ply.rhylibStunSeq = -1
        local list = MP.Cfg("poses")
        if istable(list) then
            for _, name in ipairs(list) do
                local seq = ply:LookupSequence(name)
                if seq and seq > 0 then
                    ply.rhylibStunSeq = seq
                    break
                end
            end
        end
    end
    return ply.rhylibStunSeq
end

Rhylib.Hook.Add("CalcMainActivity", "mp.pose", function(ply)
    if not MP.IsStunned(ply) then return end
    local seq = stunSequence(ply)
    if seq > 0 then return ACT_MP_STAND_IDLE, seq end
end)

Rhylib.Hook.Add("UpdateAnimation", "mp.pose", function(ply)
    if not MP.IsStunned(ply) or stunSequence(ply) <= 0 then return end
    ply:SetPlaybackRate(0)
    ply:SetCycle(0.99)
    ply:SetPoseParameter("aim_yaw", 0)
    ply:SetPoseParameter("aim_pitch", 0)
    ply:SetPoseParameter("head_yaw", 0)
    ply:SetPoseParameter("head_pitch", 0)
    if CLIENT then ply:SetRenderAngles(Angle(0, ply:GetNW2Float("rhylib_stunYaw", 0), 0)) end
    return true
end)
