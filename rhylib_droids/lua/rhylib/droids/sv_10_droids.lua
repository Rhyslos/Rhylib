--[[
    Droids (server): who can be targeted (one list for every droid,
    rebuilt a few times a second), the active cap, and no droid-on-droid
    damage.
]]

local D = Rhylib.Droids

D.active = D.active or {}   -- [droid] = true

function D.Count()
    local n = 0
    for e in pairs(D.active) do
        if IsValid(e) then n = n + 1 else D.active[e] = nil end
    end
    return n
end

-- Living players droids may shoot: not noclipping, spectating or downed.
local targets, targetsAt = {}, 0
function D.Targets()
    local now = CurTime()
    if now - targetsAt < 0.25 then return targets end
    targetsAt = now
    targets = {}
    for _, p in ipairs(player.GetAll()) do
        if p:Alive() and p:GetMoveType() ~= MOVETYPE_NOCLIP and p:GetObserverMode() == OBS_MODE_NONE
            and not p.rhylibDown and not p:IsFlagSet(FL_NOTARGET) then
            targets[#targets + 1] = p
        end
    end
    return targets
end

-- Droids don't shoot each other to pieces.
Rhylib.Hook.Add("EntityTakeDamage", "droids.friendly", function(ent, dmg)
    if not ent.IsRhylibDroid then return end
    local att = dmg:GetAttacker()
    if IsValid(att) and att.IsRhylibDroid then return true end
end, -200)
