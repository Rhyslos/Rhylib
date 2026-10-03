--[[
    Radio and squads (shared).

    Voice: the normal voice key is local (3D, within localRange). The radio
    key sends on your selected radio channel (Squad, Channel 1, Channel 2),
    or on a hail call while you're in one. People near you still hear you.
    Channels and squads live in memory and reset on map change.

    Everyone's radio state is one NW2Int "rhylib_radio", changed only on
    events (R.Bits / R.Pack):
      bit 0     radio off
      bit 1     muted (can't send on the radio)
      bit 2     deafened (hears no radio)
      bits 3-4  sending on: 0 nothing / local, 1 squad, 2 channel, 3 call
      bits 5-13 id of that squad / channel / call
      bits 14-22 squad id (0 = none)
      bits 23-27 role (R.ROLES index)
      bit 28    squad leader
      bit 29    radio operator

    Files: sv_10_radio (state, voice, squads, channels), sv_20_hails
    (calls), cl_05_icons, cl_10_client (keys, state), cl_20_hud (visor
    squares, meters, markers), cl_30_page (the Radio page).
]]

Rhylib.Radio = Rhylib.Radio or {}
local R = Rhylib.Radio
local Config = Rhylib.Config

Config.Register("radio", "localRange", 800, "Local voice reaches this far (units, 800 = 15 m)")
Config.Register("radio", "maxChannels", 200, "Most custom channels on the server at once")
Config.Register("radio", "hailTime", 30, "Seconds a hail rings before it counts as missed")
Config.Register("radio", "squadNames", { "Aurek", "Besh", "Cresh", "Dorn", "Esk", "Forn", "Grek", "Herf", "Isk", "Jenth" }, "Squad name suggestions (with a number after)")

function R.Cfg(k) return Config.Get("radio", k) end

R.ID_BITS = 9
R.MAX_ID = 511
R.NAME_LEN = 24

R.TX_NONE, R.TX_SQUAD, R.TX_CHAN, R.TX_CALL = 0, 1, 2, 3

-- Roles: visual only. { id, name, icon }
R.ROLES = {
    { "rifleman", "Rifleman", "rifle" },
    { "assault", "Assault", "bolt" },
    { "spearhead", "Spearhead", "spear" },
    { "autorifleman", "Autorifleman", "mag" },
    { "ammo", "Ammo bearer", "ammo" },
    { "marksman", "Marksman", "crosshair" },
    { "heavy", "Heavy", "barrels" },
    { "antitank", "Anti-tank", "rocket" },
    { "breacher", "Breacher", "door" },
    { "grenadier", "Grenadier", "grenade" },
    { "medic", "Combat medic", "cross" },
    { "chemist", "Chemist", "cross" },
    { "airborne", "Airborne", "wings" },
    { "officer", "Officer", "star" },
    { "shock", "Shock trooper", "shield" },
}

local band, bor, lshift, rshift = bit.band, bit.bor, bit.lshift, bit.rshift

-- Unpacked radio state of a player (a small table, new each call).
function R.Unpack(v)
    return {
        off = band(v, 1) ~= 0,
        muted = band(v, 2) ~= 0,
        deaf = band(v, 4) ~= 0,
        txKind = band(rshift(v, 3), 3),
        txId = band(rshift(v, 5), 511),
        squad = band(rshift(v, 14), 511),
        role = band(rshift(v, 23), 31),
        leader = band(v, lshift(1, 28)) ~= 0,
        ro = band(v, lshift(1, 29)) ~= 0,
    }
end

function R.Pack(t)
    local v = 0
    if t.off then v = bor(v, 1) end
    if t.muted then v = bor(v, 2) end
    if t.deaf then v = bor(v, 4) end
    v = bor(v, lshift(band(t.txKind or 0, 3), 3))
    v = bor(v, lshift(band(t.txId or 0, 511), 5))
    v = bor(v, lshift(band(t.squad or 0, 511), 14))
    v = bor(v, lshift(band(t.role or 0, 31), 23))
    if t.leader then v = bor(v, lshift(1, 28)) end
    if t.ro then v = bor(v, lshift(1, 29)) end
    return v
end

function R.Raw(ply) return ply:GetNW2Int("rhylib_radio", 0) end
-- Unpacked state, kept per player until the value changes (read only).
function R.State(ply)
    local v = R.Raw(ply)
    local c = ply.rhylibRadioC
    if c and c.v == v then return c.t end
    local t = R.Unpack(v)
    ply.rhylibRadioC = { v = v, t = t }
    return t
end

-- Cheap single reads (used every frame and in the voice hook).
function R.SquadOf(ply) return band(rshift(R.Raw(ply), 14), 511) end
function R.RoleOf(ply)
    local r = band(rshift(R.Raw(ply), 23), 31)
    return R.ROLES[r] and r or 1
end
function R.IsLeader(ply) return band(R.Raw(ply), lshift(1, 28)) ~= 0 end
function R.IsRO(ply) return band(R.Raw(ply), lshift(1, 29)) ~= 0 end

-- Battalion: rhylib_roster's, else the DarkRP job category.
function R.Battalion(ply)
    local bn = ply:GetNW2String("rhylib_bn", "")
    if bn ~= "" then return bn end
    local job = RPExtraTeams and RPExtraTeams[ply:Team()]
    return job and job.category or ""
end

function R.CleanName(s)
    s = string.Trim(string.gsub(tostring(s or ""), "[%c]", ""))
    return string.sub(s, 1, R.NAME_LEN)
end

-- Channel access modes.
R.MODE_OPEN, R.MODE_PASS, R.MODE_BN = 0, 1, 2
