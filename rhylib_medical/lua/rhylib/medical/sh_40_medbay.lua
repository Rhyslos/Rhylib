--[[
    Med bay, shared: who is in a bacta tank (NW2Entity rhylib_tank on the
    player). Inside, no shooting and no walking; Jump or E climbs out
    (sv_40_medbay.lua).
]]

local Med = Rhylib.Medical

function Med.InTank(ply)
    local t = ply:GetNW2Entity("rhylib_tank")
    return IsValid(t) and t or nil
end

local band, bnot, bor = bit.band, bit.bnot, bit.bor
local STRIP = bor(IN_ATTACK, IN_ATTACK2, IN_RELOAD, IN_DUCK, IN_SPEED, IN_WALK)

-- Lying on a med sofa (NW2Entity rhylib_sofa).
function Med.OnSofa(ply)
    local s = ply:GetNW2Entity("rhylib_sofa")
    return IsValid(s) and s or nil
end

Rhylib.Hook.Add("StartCommand", "medical.tank", function(ply, cmd)
    if not (Med.InTank(ply) or Med.OnSofa(ply)) then return end
    cmd:SetButtons(band(cmd:GetButtons(), bnot(STRIP)))
    cmd:ClearMovement()
end)
