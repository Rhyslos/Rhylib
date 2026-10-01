--[[
    Medical: downed state, bleed-out, stabilise, drag, revive and heal.

    At 0 HP a player goes down instead of dying. While down:
      - a bleed-out timer runs (bleedTime); at 0 they die
      - their health becomes a small pool (downHealth); damage while down
        comes off it, and at 0 they die (they can be finished off)
      - holding Jump for giveUpTime gives up (dies at once)
      - they lie in a death pose: same entity, same place on every screen,
        hits use the lying hitboxes
    Anyone can stabilise (E menu, pauses the timer, helper is locked in
    place) or drag (hold attack with empty hands). Medics (DarkRP job with
    medic = true) revive with a revive kit or first aid kit, picked by the
    medic. Medkits heal only.

    State, all NW2 (changes only on events):
      downed player:  rhylib_down (bool), rhylib_downEnd (CurTime when the
                      timer runs out), rhylib_downLeft (seconds left while
                      paused), rhylib_stabBy, rhylib_dragBy (entities),
                      rhylib_downYaw (body yaw when going down)
      helper:         rhylib_medAct (action, see A_*), rhylib_medT (target),
                      rhylib_medS / rhylib_medE (start / end time),
                      rhylib_dragging (entity being dragged)
]]

Rhylib.Medical = Rhylib.Medical or {}
local Med = Rhylib.Medical
local Config = Rhylib.Config

Config.Register("medical", "enabled", true, "Players go down at 0 HP instead of dying")
Config.Register("medical", "bleedTime", 120, "Seconds a downed player lasts before bleeding out")
Config.Register("medical", "downHealth", 50, "Health while downed; damage while down comes off this")
Config.Register("medical", "giveUpTime", 3, "Seconds of holding Jump to give up")
Config.Register("medical", "range", 90, "How close a helper must be (units; ~2.3 m)")
Config.Register("medical", "reviveKitTime", 5, "Seconds to revive with a revive kit")
Config.Register("medical", "reviveKitHealth", 1, "Health after a revive kit, as a share of max health")
Config.Register("medical", "firstAidReviveTime", 15, "Seconds to revive with a first aid kit")
Config.Register("medical", "firstAidReviveHealth", 30, "Health after a first aid revive")
Config.Register("medical", "firstAidHealTime", 4, "Seconds to fully heal someone who is up with a first aid kit")
Config.Register("medical", "medkitHealTime", 2, "Seconds per medkit use on someone else")
Config.Register("medical", "medkitHeal", 25, "Health per medkit use")
Config.Register("medical", "medkitUses", 5, "Uses in a full medkit")
Config.Register("medical", "medkitMedicOnly", false, "Only medics can use medkits")
Config.Register("medical", "selfMult", 2, "Healing yourself takes this many times longer")
Config.Register("medical", "dragSpeed", 100, "Top speed while dragging someone")
Config.Register("medical", "dragLeash", 45, "How far behind the dragger the body trails")
Config.Register("medical", "dragWeapons", { rhylib_stowed = true, keys = true }, "Weapons that count as empty hands for dragging")
Config.Register("medical", "noTarget", true, "NPCs ignore downed players")
Config.Register("medical", "downSequences", { "death_04", "death_03", "death_02", "death_01", "zombie_slump_idle_02" }, "Lying poses to try, first that exists on the model wins (last frame is used)")
Config.Register("medical", "markerRange", 2500, "Downed markers show within this distance")

function Med.Cfg(key)
    return Config.Get("medical", key)
end

-- Actions a helper can be doing.
Med.A_NONE = 0
Med.A_STAB = 1      -- stabilising (open-ended)
Med.A_REVIVE = 2    -- reviving with a revive kit
Med.A_FA_REVIVE = 3 -- reviving with a first aid kit
Med.A_FA_HEAL = 4   -- full heal with a first aid kit
Med.A_MEDKIT = 5    -- one medkit use
Med.ACT_BITS = 3

Med.ActName = {
    [1] = "Stabilising",
    [2] = "Reviving",
    [3] = "Reviving (first aid)",
    [4] = "Treating",
    [5] = "Healing",
}

-- Kit weapon classes.
Med.REVIVE_KIT = "rhylib_revivekit"
Med.FIRST_AID = "rhylib_firstaid"
Med.MEDKIT = "rhylib_medkit"

--------------------------------------------------------------------------
-- State readers (shared)
--------------------------------------------------------------------------

function Med.IsDown(ply)
    return ply:GetNW2Bool("rhylib_down", false)
end

function Med.StabilisedBy(ply)
    local e = ply:GetNW2Entity("rhylib_stabBy")
    return IsValid(e) and e or nil
end

function Med.DraggedBy(ply)
    local e = ply:GetNW2Entity("rhylib_dragBy")
    return IsValid(e) and e or nil
end

function Med.Dragging(ply)
    local e = ply:GetNW2Entity("rhylib_dragging")
    return IsValid(e) and e or nil
end

-- Seconds of bleed-out left.
function Med.TimeLeft(ply)
    if Med.StabilisedBy(ply) then return ply:GetNW2Float("rhylib_downLeft", 0) end
    return math.max(0, ply:GetNW2Float("rhylib_downEnd", 0) - CurTime())
end

-- action, target, start, end
function Med.Action(ply)
    local a = ply:GetNW2Int("rhylib_medAct", 0)
    if a == 0 then return 0 end
    return a, ply:GetNW2Entity("rhylib_medT"), ply:GetNW2Float("rhylib_medS", 0), ply:GetNW2Float("rhylib_medE", 0)
end

-- DarkRP job flag (medic = true). Other gamemodes can answer the
-- Rhylib.IsMedic hook.
function Med.IsMedic(ply)
    local r = hook.Run("Rhylib.IsMedic", ply)
    if r ~= nil then return r end
    local job = RPExtraTeams and RPExtraTeams[ply:Team()]
    return job and job.medic == true or false
end

function Med.HoldingHands(ply)
    local wep = ply:GetActiveWeapon()
    if not IsValid(wep) then return true end
    local list = Med.Cfg("dragWeapons")
    return wep.IsRhylibStowed or (istable(list) and list[wep:GetClass()]) or false
end

-- Centre of a lying body (for aiming and range checks).
function Med.BodyPos(ply)
    return ply:GetPos() + Vector(0, 0, 10)
end

--[[
    The downed player `ply` is aiming at, within range. Lying bodies are
    small, so this checks aim direction against every downed player
    instead of tracing for hitboxes. The list is short.
]]
function Med.FindDowned(ply, list)
    local eye = ply:EyePos()
    local dir = ply:GetAimVector()
    local range = Med.Cfg("range") + 40  -- eyes are well above the body
    local best, bestDot
    for _, t in ipairs(list or player.GetAll()) do
        if t ~= ply and IsValid(t) and t:Alive() and Med.IsDown(t) then
            local to = Med.BodyPos(t) - eye
            local dist = to:Length()
            if dist > 1 and dist <= range then
                local dot = dir:Dot(to / dist)
                -- A body about 30 units around, plus some slack.
                local need = math.cos(math.min(math.atan(30 / dist) + 0.1, 1.2))
                if dot >= need and (not best or dot > bestDot) then
                    local tr = util.TraceLine({ start = eye, endpos = Med.BodyPos(t), filter = { ply, t }, mask = MASK_SOLID_BRUSHONLY })
                    if not tr.Hit then best, bestDot = t, dot end
                end
            end
        end
    end
    return best
end

-- A standing player in front of `ply`, within range.
function Med.FindStanding(ply)
    local tr = util.TraceHull({
        start = ply:EyePos(),
        endpos = ply:EyePos() + ply:GetAimVector() * (Med.Cfg("range") + 20),
        filter = ply,
        mins = Vector(-4, -4, -4), maxs = Vector(4, 4, 4),
        mask = MASK_SHOT_HULL,
    })
    local e = tr.Entity
    if IsValid(e) and e:IsPlayer() and e:Alive() and not Med.IsDown(e) then return e end
end
