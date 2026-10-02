--[[
    Roster: characters, battalion membership and ranks.

    Character: a 4-digit clone number (unique on the server) and a
    nickname, chosen once on first join (admins can reset it). The name
    shown everywhere (DarkRP rpname) is PREFIX-NUMBER Nickname:
        CC   cadet (job namePrefix = "CC")
        CT   passed basic training (job namePrefix = "CT")
        rank prefix in a battalion (PVT-1234 Nickname, SGT-..., ...)

    Career: Cadet -> basic training (a SGT+ marks them trained) -> CT ->
    added to a battalion as PVT by its SGT+ -> promoted up the ladder.
    One shared rank ladder for every battalion.

    Jobs (DarkRP, jobs.lua) say what they need:
        needsTraining = true          passed basic training (CT)
        battalion = "501st"           a member of that battalion ...
        minRank = "SGT"               ... with at least this rank
    Unavailable jobs show the reason in the job list.

    Promoting: within your own battalion, members ranked below you, up to
    one rank below yours. Adding members and passing cadets needs
    manageRank or higher. Admins (rhylib.roster.admin) can do anything.

    Player NW2 (set on change): rhylib_char (bool), rhylib_num, rhylib_nick,
    rhylib_trained (bool), rhylib_bn, rhylib_rank (index, 0 = none).
]]

Rhylib.Roster = Rhylib.Roster or {}
local R = Rhylib.Roster
local Config = Rhylib.Config

Config.Register("roster", "ranks", {
    { "PVT", "Private" }, { "PFC", "Private First Class" }, { "CPL", "Corporal" },
    { "SGT", "Sergeant" }, { "SSG", "Staff Sergeant" }, { "LT", "Lieutenant" },
    { "CPT", "Captain" }, { "MAJ", "Major" }, { "CMD", "Commander" },
}, "The rank ladder, lowest first: { prefix, name }")
Config.Register("roster", "manageRank", "SGT", "Lowest rank that can add members, pass cadets and promote")
Config.Register("roster", "boardRank", "LT", "Lowest rank that can post on the battalion board")
Config.Register("roster", "blockedNumbers", { "1337", "6969", "0420", "6767", "6967", "6769" }, "Clone numbers nobody can take")
Config.Register("roster", "nickMax", 20, "Longest nickname")

function R.Cfg(k) return Config.Get("roster", k) end

function R.Ranks() return R.Cfg("ranks") or {} end

-- Rank index by prefix ("SGT" -> 4), or nil.
function R.RankIndex(prefix)
    if not prefix then return nil end
    for i, r in ipairs(R.Ranks()) do
        if r[1] == prefix then return i end
    end
end

function R.RankPrefix(i) local r = R.Ranks()[i] return r and r[1] or nil end
function R.RankName(i) local r = R.Ranks()[i] return r and r[2] or "None" end

-- Number rules: 4 digits, never two zeros in a row, not blocked.
function R.ValidNumber(num)
    num = tostring(num or "")
    if not string.match(num, "^%d%d%d%d$") then return false, "The number must be exactly 4 digits" end
    if string.find(num, "00", 1, true) then return false, "No two zeros in a row (0411 is fine, 0011 isn't)" end
    for _, b in ipairs(R.Cfg("blockedNumbers") or {}) do
        if tostring(b) == num then return false, "That number isn't allowed" end
    end
    return true
end

-- Nickname: 2 to nickMax characters, no control characters, single spaces.
function R.CleanNick(nick)
    nick = string.gsub(tostring(nick or ""), "%c", "")
    nick = string.Trim((string.gsub(nick, "%s+", " ")))   -- (brackets: gsub's count must not reach Trim)
    return nick
end

function R.ValidNick(nick)
    local len = utf8.len(nick)
    if not len then return false, "Use normal letters" end
    if len < 2 then return false, "The nickname needs at least 2 characters" end
    if len > R.Cfg("nickMax") then return false, "The nickname is too long (max " .. R.Cfg("nickMax") .. ")" end
    return true
end

-- What a player is, from their networked state.
function R.Get(ply)
    return {
        has = ply:GetNW2Bool("rhylib_char", false),
        num = ply:GetNW2String("rhylib_num", ""),
        nick = ply:GetNW2String("rhylib_nick", ""),
        trained = ply:GetNW2Bool("rhylib_trained", false),
        bn = ply:GetNW2String("rhylib_bn", ""),
        rank = ply:GetNW2Int("rhylib_rank", 0),
    }
end

local function job(ply) return RPExtraTeams and RPExtraTeams[ply:Team()] end

-- The name prefix for this player's current job.
function R.Prefix(ply, j)
    j = j or job(ply)
    if j and j.namePrefix then return j.namePrefix end
    local c = R.Get(ply)
    if j and j.battalion and c.bn == j.battalion and c.rank > 0 then return R.RankPrefix(c.rank) or "CT" end
    return c.trained and "CT" or "CC"
end

function R.FullName(ply, j)
    local c = R.Get(ply)
    if not c.has then return nil end
    return R.Prefix(ply, j) .. "-" .. c.num .. " " .. c.nick
end

-- Why a player can't take a job right now, or nil.
function R.JobBlock(ply, j)
    local c = R.Get(ply)
    if not c.has and (j.needsTraining or j.battalion) then return "Create your character first" end
    if j.needsTraining and not c.trained then return "Needs basic training (ask a Sergeant or higher)" end
    if j.battalion then
        if c.bn ~= j.battalion then return "Only for members of the " .. j.battalion end
        local need = R.RankIndex(j.minRank)
        if need and c.rank < need then return "Needs rank " .. R.RankName(need) .. " or higher" end
    end
    return nil
end

-- Add our rules to the DarkRP jobs (customCheck runs on both sides and
-- in the F4 / job list). Done once the jobs exist.
local function wrapJobs()
    if not RPExtraTeams then return end
    for _, j in pairs(RPExtraTeams) do
        if (j.needsTraining or j.battalion) and not j.rhylibWrapped then
            j.rhylibWrapped = true
            local oldCheck, oldMsg = j.customCheck, j.CustomCheckFailMsg
            j.customCheck = function(ply)
                if R.JobBlock(ply, j) then return false end
                return not oldCheck or oldCheck(ply)
            end
            j.CustomCheckFailMsg = function(ply, jj)
                local why = R.JobBlock(ply, j)
                if why then return why end
                if isfunction(oldMsg) then return oldMsg(ply, jj) end
                return oldMsg
            end
        end
    end
end
Rhylib.Hook.Add("InitPostEntity", "roster.jobs", wrapJobs)
Rhylib.Hook.Add("DarkRPFinishedLoading", "roster.jobs", wrapJobs)
wrapJobs()  -- (Lua refresh)
