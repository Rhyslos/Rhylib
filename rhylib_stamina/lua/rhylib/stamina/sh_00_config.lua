--[[
    Stamina settings and the maths shared by server, client and HUD.

    Stamina runs from 0 to max. Sprinting and jumping use it; it comes
    back after a short rest. Running completely dry leaves you exhausted:
    no sprinting until you're back to exhaustedUntil.

    Carried weight (from rhylib_inventory) makes it drain faster and
    recover slower:
        load    = weight / carry cap
        penalty = maxPenalty * load ^ penaltyCurve     (capped at load 1)
        drain   = sprintDrain * (1 + penalty)
        regen   = regen * (1 - penalty / 2)
    maxPenalty is lower with a backpack worn. Over the carry cap you
    can't sprint and walk slower (overloadWalkMult).

    State lives in the player's own network vars, predicted like movement:
        DTFloat 28  stamina
        DTFloat 29  last time stamina was used (regen waits regenDelay)
        DTBool  28  exhausted
    The jetpack uses slots 29-31 for its bools and 30-31 for its floats.
]]

Rhylib.Stamina = Rhylib.Stamina or {}
local S = Rhylib.Stamina

S.DT_STAMINA = 28
S.DT_USED = 29
S.DT_EXHAUSTED = 28

local Config = Rhylib.Config
Config.Register("stamina", "max", 100, "Full stamina")
Config.Register("stamina", "sprintDrain", 12, "Stamina per second while sprinting with no load (100 / 12 = about 8 s of sprint)")
Config.Register("stamina", "jumpCost", 8, "Stamina per jump")
Config.Register("stamina", "regen", 20, "Stamina per second while resting, with no load")
Config.Register("stamina", "regenDelay", 1, "Seconds after sprinting or jumping before stamina comes back")
Config.Register("stamina", "exhaustedUntil", 25, "After running dry, no sprinting until stamina is back to this")
Config.Register("stamina", "maxPenalty", 0.6, "Penalty at a full load without a backpack")
Config.Register("stamina", "maxPenaltyPack", 0.45, "Penalty at a full load with a backpack worn")
Config.Register("stamina", "penaltyCurve", 1.5, "Higher = light loads cost less, the last kilos cost more")
Config.Register("stamina", "overloadWalkMult", 0.8, "Walk speed multiplier while over the carry cap")
Config.Register("stamina", "lowAimBelow", 20, "Below this stamina, spread starts to grow")
Config.Register("stamina", "lowAimSpread", 0.5, "Extra spread at zero stamina, as a fraction of the weapon's resting cone")

local function cfg(key)
    return Config.Get("stamina", key)
end

function S.Get(ply)
    return ply:GetDTFloat(S.DT_STAMINA)
end

function S.Frac(ply)
    return math.Clamp(ply:GetDTFloat(S.DT_STAMINA) / cfg("max"), 0, 1)
end

function S.Exhausted(ply)
    return ply:GetDTBool(S.DT_EXHAUSTED)
end

-- Weight and carry cap from rhylib_inventory (0 and the base cap without it).
function S.Load(ply)
    local weight = ply:GetNW2Float("rhylib_weight", 0)
    local base = Config.Get("inventory", "baseCarry") or 20
    local cap = ply:GetNW2Float("rhylib_carry", base)
    if cap <= 0 then cap = base end
    return weight / cap, cap > base
end

-- Penalty from 0 to maxPenalty, and whether the player is over the cap.
function S.Penalty(ply)
    local load, pack = S.Load(ply)
    local maxPen = pack and cfg("maxPenaltyPack") or cfg("maxPenalty")
    return maxPen * math.min(load, 1) ^ cfg("penaltyCurve"), load > 1
end

-- Extra spread in degrees for a weapon whose owner is low on stamina.
-- Used by rhylib_weapons (sh_10_spread.lua); all arcs grow evenly.
function S.SpreadPenalty(ply, baseCone)
    local below = cfg("lowAimBelow")
    local st = ply:GetDTFloat(S.DT_STAMINA)
    if st >= below then return 0 end
    return (1 - st / below) * cfg("lowAimSpread") * baseCone
end
