--[[
    Stamina use and recovery. Runs in SetupMove on both server and client,
    so the client predicts it: sprint stops the moment you run dry, with
    no rubber-banding.

    Sprinting = holding sprint, pressing a movement key, on the ground.
    Jumps are free for jetpack wearers (the jetpack does the work).
]]

local S = Rhylib.Stamina
local Config = Rhylib.Config
local J_DT_HAS = 31  -- rhylib_jetpack's "wearing a jetpack" bool

local function cfg(key)
    return Config.Get("stamina", key)
end

Rhylib.Hook.Add("SetupMove", "stamina.move", function(ply, mv)
    if not ply:Alive() or ply:GetMoveType() ~= MOVETYPE_WALK or ply:InVehicle() then return end

    local dt = FrameTime()
    local now = CurTime()
    local max = cfg("max")
    local st = ply:GetDTFloat(S.DT_STAMINA)
    local used = ply:GetDTFloat(S.DT_USED)
    local exhausted = ply:GetDTBool(S.DT_EXHAUSTED)
    local penalty, over = S.Penalty(ply)
    local onGround = ply:OnGround()

    -- Sprinting
    local moving = mv:GetForwardSpeed() ~= 0 or mv:GetSideSpeed() ~= 0
    local wantsSprint = mv:KeyDown(IN_SPEED) and moving and onGround and not mv:KeyDown(IN_DUCK)
    local canSprint = not exhausted and not over and st > 0

    if wantsSprint and canSprint then
        st = st - cfg("sprintDrain") * (1 + penalty) * dt
        used = now
        if st <= 0 then
            st = 0
            exhausted = true
        end
    elseif wantsSprint then
        -- Can't sprint right now: hold the player to walking speed.
        mv:SetMaxClientSpeed(math.min(mv:GetMaxClientSpeed(), ply:GetWalkSpeed()))
    end

    -- Over the carry cap: slower walk.
    if over then
        mv:SetMaxClientSpeed(math.min(mv:GetMaxClientSpeed(), ply:GetWalkSpeed() * cfg("overloadWalkMult")))
    end

    -- Jumping
    if mv:KeyPressed(IN_JUMP) and onGround and not ply:GetDTBool(J_DT_HAS) then
        local cost = cfg("jumpCost")
        if st >= cost then
            st = st - cost
            used = now
        else
            mv:SetButtons(bit.band(mv:GetButtons(), bit.bnot(IN_JUMP)))  -- too tired to jump
        end
    end

    -- Recovery after a short rest
    if st < max and now - used >= cfg("regenDelay") then
        st = math.min(max, st + cfg("regen") * (1 - penalty * 0.5) * dt)
    end
    if exhausted and st >= cfg("exhaustedUntil") then exhausted = false end

    ply:SetDTFloat(S.DT_STAMINA, st)
    if used ~= ply:GetDTFloat(S.DT_USED) then ply:SetDTFloat(S.DT_USED, used) end
    if exhausted ~= ply:GetDTBool(S.DT_EXHAUSTED) then ply:SetDTBool(S.DT_EXHAUSTED, exhausted) end
end)

if SERVER then
    -- Everyone spawns rested.
    Rhylib.Hook.Add("PlayerSpawn", "stamina.reset", function(ply)
        ply:SetDTFloat(S.DT_STAMINA, cfg("max"))
        ply:SetDTFloat(S.DT_USED, 0)
        ply:SetDTBool(S.DT_EXHAUSTED, false)
    end)
end
