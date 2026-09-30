--[[
    Jetpack flight. Runs in SetupMove on both server and client, so the
    client predicts it and it feels as responsive as walking.

    Hold jump in the air to climb, or shift to hover at your current
    height. Vertical speed is steered toward climbSpeed (or 0 when
    hovering). Braking a fall is limited by brakeAccel: a short drop is
    caught in about a second, but a fall at top speed takes about five
    seconds to stop, so you have to start braking early. Climbing uses
    the stronger maxAccel so take-off stays responsive.

    Fuel drains while thrusting and refills once you've been on the
    ground for rechargeDelay. Running dry locks the jetpack until the
    tank is back to unlockAt.
]]

local J = Rhylib.Jetpack
local Config = Rhylib.Config
local gravityVar = GetConVar("sv_gravity")

local function cfg(key)
    return Config.Get("jetpack", key)
end

Rhylib.Hook.Add("SetupMove", "jetpack.move", function(ply, mv)
    if not ply:GetDTBool(J.DT_HAS) then return end

    local dt = FrameTime()
    local now = CurTime()
    local fuel = ply:GetDTFloat(J.DT_FUEL)
    local locked = ply:GetDTBool(J.DT_LOCKED)
    local onGround = ply:OnGround()

    -- Refill on the ground.
    if onGround then
        local landed = ply:GetDTFloat(J.DT_LANDED)
        if landed == 0 then
            landed = now
            ply:SetDTFloat(J.DT_LANDED, now)
        end
        if now - landed >= cfg("rechargeDelay") then
            fuel = math.min(1, fuel + dt / cfg("rechargeTime"))
        end
        if locked and fuel >= cfg("unlockAt") then locked = false end
    elseif ply:GetDTFloat(J.DT_LANDED) ~= 0 then
        ply:SetDTFloat(J.DT_LANDED, 0)
    end

    -- Shift hovers (holds height); jump climbs. Shift wins if both are held.
    local hover = mv:KeyDown(IN_SPEED)
    local thrusting = not onGround and not locked and fuel > 0
        and (mv:KeyDown(IN_JUMP) or hover)
        and ply:GetMoveType() == MOVETYPE_WALK
        and ply:WaterLevel() < 2

    if thrusting then
        fuel = fuel - dt / cfg("fuelTime")
        if fuel <= 0 then
            fuel = 0
            locked = true
        end

        local vel = mv:GetVelocity()

        -- Vertical: steer toward the climb speed, hard when falling.
        local vz = vel.z
        local target = hover and 0 or cfg("climbSpeed")
        local tau = vz < 0 and cfg("brakeTau") or cfg("climbTau")
        local change = (target - vz) * (1 - math.exp(-dt / tau))
        local cap = (vz < 0 and cfg("brakeAccel") or cfg("maxAccel")) * dt
        change = math.Clamp(change, -cap, cap)
        local g = gravityVar:GetFloat() * (ply:GetGravity() ~= 0 and ply:GetGravity() or 1)
        vel.z = vz + change + g * dt  -- also cancels the engine's gravity for this tick

        -- Sideways: the jetpack holds you still unless you press a
        -- movement key, and cancels drift that isn't where you're going.
        local ang = mv:GetMoveAngles()
        local yaw = Angle(0, ang.y, 0)
        local wish = yaw:Forward() * mv:GetForwardSpeed() + yaw:Right() * mv:GetSideSpeed()
        wish.z = 0
        local h = Vector(vel.x, vel.y, 0)
        local damp = math.exp(-dt / cfg("airStopTau"))
        if wish:LengthSqr() > 1 then
            wish:Normalize()
            local along = h:Dot(wish)
            h = wish * along + (h - wish * along) * damp   -- keep the wanted direction, kill sideways drift
            local speed = h:Length()
            local nh = h + wish * (cfg("airAccel") * dt)
            local limit = math.max(cfg("maxAirSpeed"), speed)
            if nh:Length() > limit then nh = nh:GetNormalized() * limit end
            -- Faster than the jetpack's own top speed (e.g. launched): bleed it off.
            if limit > cfg("maxAirSpeed") then nh = nh * damp end
            h = nh
        else
            h = h * damp  -- no keys: slow to a stop and hover in place
        end
        vel.x, vel.y = h.x, h.y

        mv:SetVelocity(vel)
    end

    ply:SetDTFloat(J.DT_FUEL, fuel)
    ply:SetDTBool(J.DT_LOCKED, locked)
    if ply:GetDTBool(J.DT_THRUST) ~= thrusting then ply:SetDTBool(J.DT_THRUST, thrusting) end
end)
