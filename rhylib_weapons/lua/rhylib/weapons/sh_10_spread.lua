--[[
    Spread and crosshair recoil, shared by server and client.

    The crosshair is not decoration: it is drawn from exactly these values.
    Every shot lands inside the current crosshair circle, and the arc
    closest to the shot gets kicked outward (see the design plan).

    All spread values are cone angles in degrees. State is stored in the
    weapon's predicted network vars, so server and client always agree:
        Bloom, Kick1, Kick2, Kick3, KickTime, Streak, LastArc, Aiming
    Values decay over time, calculated from KickTime, so nothing has to
    be sent while they settle.
]]

local Spread = {}
Rhylib.Weapons.Spread = Spread

-- Arc centre directions in screen space (0 = right, 90 = down):
-- 1 = down-left, 2 = top, 3 = down-right.
Spread.ARC_CENTRES = { math.rad(150), math.rad(270), math.rad(30) }

Spread.KICK_TAU = 0.12       -- per-arc kick decay, seconds
Spread.BLOOM_TAU = 0.45      -- shared bloom decay, seconds
Spread.STREAK_WINDOW = 0.6   -- seconds between same-arc shots to keep a streak
Spread.STREAK_MAX = 4

-- Decayed values at time t: bloom, kick1, kick2, kick3.
function Spread.GetState(wep, t)
    local dt = math.max(0, t - wep:GetKickTime())
    local kd = math.exp(-dt / Spread.KICK_TAU)
    local bd = math.exp(-dt / Spread.BLOOM_TAU)
    return wep:GetBloom() * bd, wep:GetKick1() * kd, wep:GetKick2() * kd, wep:GetKick3() * kd
end

-- Resting cone size (the arc radius).
function Spread.BaseCone(wep)
    return wep:GetAiming() and wep.Spread.aim or wep.Spread.hip
end

-- How far each arc has moved outward, in degrees. Low stamina (with
-- rhylib_stamina) pushes all three arcs out evenly.
function Spread.Offsets(wep, t)
    local bloom, k1, k2, k3 = Spread.GetState(wep, t)
    local m = wep:GetAiming() and wep.Spread.aimOffsetMult or 1
    local tired = 0
    local S = Rhylib.Stamina
    local owner = wep:GetOwner()
    if S and IsValid(owner) and owner:IsPlayer() then
        tired = S.SpreadPenalty(owner, Spread.BaseCone(wep))
    end
    return (bloom + k1) * m + tired, (bloom + k2) * m + tired, (bloom + k3) * m + tired
end

-- Average cone: the area shots actually land in.
function Spread.MeanCone(wep, t)
    local o1, o2, o3 = Spread.Offsets(wep, t)
    return Spread.BaseCone(wep) + (o1 + o2 + o3) / 3
end

function Spread.NearestArc(a)
    local best, bestD = 1, math.huge
    for i = 1, 3 do
        local d = math.abs(math.NormalizeAngle(math.deg(a - Spread.ARC_CENTRES[i])))
        if d < bestD then
            best, bestD = i, d
        end
    end
    return best
end

--[[
    Direction for one shot. Uses util.SharedRandom, which is seeded from the
    player's command, so the server and the shooter's client pick the same
    direction without sending anything.
    Returns the direction and the screen angle the shot went to.
]]
function Spread.ShotDirection(wep, aimAng, index)
    local cone = Spread.MeanCone(wep, CurTime())
    local a = util.SharedRandom("rhylib.spread.a", 0, 2 * math.pi, index or 0)
    local u = util.SharedRandom("rhylib.spread.r", 0, 1, index or 0)
    local off = math.tan(math.rad(cone) * math.sqrt(u) * 0.95)

    local dir = aimAng:Forward() + aimAng:Right() * (math.cos(a) * off) - aimAng:Up() * (math.sin(a) * off)
    dir:Normalize()
    return dir, a
end

-- Record a shot that went toward the given arc: decay, then add kicks.
function Spread.AddShot(wep, arc, t)
    local cfg = wep.Spread
    local bloom, k1, k2, k3 = Spread.GetState(wep, t)

    local streak = 1
    if arc == wep:GetLastArc() and t - wep:GetKickTime() < Spread.STREAK_WINDOW then
        streak = math.min(wep:GetStreak() + 1, Spread.STREAK_MAX)
    end

    local m = wep:GetAiming() and cfg.aimKickMult or 1
    local main, side = cfg.kickMain * streak * m, cfg.kickSide * m

    wep:SetKick1(k1 + (arc == 1 and main or side))
    wep:SetKick2(k2 + (arc == 2 and main or side))
    wep:SetKick3(k3 + (arc == 3 and main or side))
    wep:SetBloom(math.min(bloom + cfg.bloomPerShot * m, cfg.bloomMax))
    wep:SetKickTime(t)
    wep:SetStreak(streak)
    wep:SetLastArc(arc)
end
