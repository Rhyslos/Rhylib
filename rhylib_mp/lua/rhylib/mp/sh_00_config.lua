--[[
    Military police: stun weapons, stun baton, handcuffs, searching, and a
    jail with cells and sentences.

      Stun        a stun ring (stun guns, SWEP.Stun) or a baton hit makes
                  the target collapse for stunTime seconds: they lie still
                  and can be cuffed.
      Cuffs       an MP cuffs a stunned or downed player (handcuffs LMB),
                  uncuffs (RMB on a cuffed player) and escorts (Reload:
                  the prisoner is pulled along behind you). Cuffed players
                  walk slowly, can't sprint, jump, shoot, switch weapons or
                  use their inventory.
      Search      with the stun baton in hand, RMB on a player shows their
                  inventory (look only). If they're cuffed, items can be
                  taken. MPs can also open locked lockers.
      Jail        admins place cells and a jail terminal (spawn menu,
                  rhylib_mp_save). At the terminal an MP jails a cuffed
                  prisoner nearby: minutes and a reason. Their items go to
                  evidence (returned on release unless an MP removes them),
                  they're put in a free cell, and released when the time
                  is up. Sentences survive reconnects and map changes.

    Who is an MP: a DarkRP job with mp = true (or answer Rhylib.IsMP).

    State is NW2 on the player, changed only on events:
      rhylib_stunEnd (CurTime), rhylib_stunYaw, rhylib_cuffed (bool),
      rhylib_escortBy (entity), rhylib_jailEnd (CurTime), rhylib_jailWhy
]]

Rhylib.MP = Rhylib.MP or {}
local MP = Rhylib.MP
local Config = Rhylib.Config

Config.Register("mp", "stunTime", 8, "Seconds a stun hit keeps someone down")
Config.Register("mp", "stunImmune", 3, "Seconds after getting up before they can be stunned again")
Config.Register("mp", "batonRange", 85, "Stun baton reach (units)")
Config.Register("mp", "batonDelay", 1.2, "Seconds between baton swings")
Config.Register("mp", "cuffRange", 85, "How close you must be to cuff or uncuff")
Config.Register("mp", "cuffTime", 1.5, "Seconds to put cuffs on")
Config.Register("mp", "cuffWalk", 110, "Walk speed while cuffed")
Config.Register("mp", "escortLeash", 60, "How far behind the MP an escorted prisoner walks")
Config.Register("mp", "searchRange", 100, "How close you must be to search someone")
Config.Register("mp", "maxSentence", 60, "Longest sentence in minutes")
Config.Register("mp", "jailRadius", 350, "A prisoner further than this from their cell is put back")
Config.Register("mp", "terminalRange", 400, "Cuffed prisoners this close to a jail terminal can be jailed there")
Config.Register("mp", "poses", { "death_04", "death_03", "death_02", "death_01", "zombie_slump_idle_02" }, "Lying poses while stunned, first that exists on the model wins")

function MP.Cfg(k) return Config.Get("mp", k) end

MP.TERM_USE = 180   -- how close an MP must stay to a terminal to use it

function MP.IsMP(ply)
    if not IsValid(ply) then return false end
    local r = hook.Run("Rhylib.IsMP", ply)
    if r ~= nil then return r end
    local job = RPExtraTeams and RPExtraTeams[ply:Team()]
    return job and job.mp == true or false
end

function MP.IsStunned(ply) return ply:GetNW2Float("rhylib_stunEnd", 0) > CurTime() end
function MP.IsCuffed(ply) return ply:GetNW2Bool("rhylib_cuffed", false) end
function MP.EscortedBy(ply)
    local e = ply:GetNW2Entity("rhylib_escortBy")
    return IsValid(e) and e or nil
end
function MP.IsJailed(ply) return ply:GetNW2Float("rhylib_jailEnd", 0) > 0 end
function MP.JailLeft(ply) return math.max(0, ply:GetNW2Float("rhylib_jailEnd", 0) - CurTime()) end

-- Cuffed, stunned or jailed: no inventory use (rhylib_inventory asks this).
Rhylib.Hook.Add("Rhylib.InventoryLocked", "mp.lock", function(ply)
    if MP.IsCuffed(ply) or MP.IsStunned(ply) or MP.IsJailed(ply) then return true end
end)

-- The player an MP is aiming at, within range.
function MP.Target(ply, range)
    local tr = util.TraceHull({
        start = ply:EyePos(),
        endpos = ply:EyePos() + ply:GetAimVector() * range,
        filter = ply,
        mins = Vector(-6, -6, -6), maxs = Vector(6, 6, 6),
        mask = MASK_SHOT_HULL,
    })
    local e = tr.Entity
    if IsValid(e) and e:IsPlayer() and e:Alive() then return e end
    -- Lying bodies (stunned or downed) are low: try a little lower too.
    local tr2 = util.TraceHull({
        start = ply:EyePos(),
        endpos = ply:EyePos() + (ply:GetAimVector() + Vector(0, 0, -0.35)):GetNormalized() * range,
        filter = ply,
        mins = Vector(-10, -10, -10), maxs = Vector(10, 10, 10),
        mask = MASK_SHOT_HULL,
    })
    e = tr2.Entity
    if IsValid(e) and e:IsPlayer() and e:Alive() then return e end
end
