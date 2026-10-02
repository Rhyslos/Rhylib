--[[
    Admin server core: rank storage, bans, warnings, the log, finding
    targets and running commands (chat, the staff menu, the console).

    Data module "admin" (keys "s"..SteamID64, never bare numbers):
        r<sid>   staff rank id          b<sid>  ban { reason, by, byName, at, untilT (0 = forever), name }
        w<sid>   warnings { { reason, byName, at } }
        bans     index { ["s"..sid] = name }     log  { { t, text } } newest first (LOG_CAP)
    Mute / gag / freeze / return spots are for the session only.

    Admin.Exec(caller, id, words): words are the parts after the command
    (target first if the command has one). Replies go to the caller
    (admin.msg); actions are logged and echoed (config echo).
    Admin.SetRank(sid64, rankId, byName), Admin.Ban(sid64, minutes, reason, caller, name), Admin.Unban(sid64, byName)
    Admin.handlers[id] = function(caller, target, args, ctx) -> echo text or nil, error
]]

local Admin = Rhylib.Admin
local Data = Rhylib.Data

for _, n in ipairs({ "admin.msg", "admin.announce", "admin.list", "admin.countdown" }) do Rhylib.Net.Register(n) end

local LOG_CAP = 300
local KEY = "admin"

local function sidKey(prefix, sid) return prefix .. "s" .. sid end
local function nameOf(p) return IsValid(p) and p:Nick() or "Console" end

--------------------------------------------------------------------------
-- Messages
--------------------------------------------------------------------------

-- Short note to one player (or the server console).
function Admin.Tell(ply, text, bad)
    if not IsValid(ply) then print("[Admin] " .. text) return end
    Rhylib.Net.Start("admin.msg")
    net.WriteBool(bad and true or false)
    net.WriteString(text)
    net.Send(ply)
end

-- An action everyone (config echo) or only staff hear about.
local function echo(text)
    print("[Admin] " .. text)
    local list = {}
    for _, p in ipairs(player.GetHumans()) do
        if Admin.Cfg("echo") or Admin.Level(p) > 0 then list[#list + 1] = p end
    end
    if #list == 0 then return end
    Rhylib.Net.Start("admin.msg")
    net.WriteBool(false)
    net.WriteString(text)
    net.Send(list)
end
Admin.Echo = echo

function Admin.Log(text)
    local log = Data.Get(KEY, "log")
    if not istable(log) then log = {} end
    table.insert(log, 1, { t = os.time(), text = text })
    while #log > LOG_CAP do table.remove(log) end
    Data.Set(KEY, "log", log)
    if ServerLog then ServerLog("[Rhylib Admin] " .. text .. "\n") end
end

--------------------------------------------------------------------------
-- Ranks
--------------------------------------------------------------------------

local function isOwnerId(sid)
    for _, o in ipairs(Admin.Cfg("owners") or {}) do
        if tostring(o) == sid then return true end
    end
    return false
end

local function storedRank(sid)
    local r = Data.Get(KEY, sidKey("r", sid))
    return isstring(r) and Admin.RankById(r) and r or nil
end

-- Our storage (and owners / the listen host) is the only source of ranks.
local function applyRank(ply)
    if not IsValid(ply) or ply:IsBot() then return end
    local sid = ply:SteamID64() or ""
    local want
    if isOwnerId(sid) or ply:IsListenServerHost() then
        want = Admin.TopRank().id
    else
        want = storedRank(sid) or "user"
    end
    local old = ply:GetUserGroup()
    if old ~= want then
        ply.rhylibSettingRank = true
        ply:SetUserGroup(want)
        ply.rhylibSettingRank = nil
        if CAMI and CAMI.SignalUserGroupChanged then CAMI.SignalUserGroupChanged(ply, old, want, "Rhylib") end
    end
end
Admin.ApplyRank = applyRank

Rhylib.Hook.Add("PlayerInitialSpawn", "admin.rank", function(ply)
    -- After the engine's own users.txt / listen-host group (which we replace).
    timer.Simple(0, function() applyRank(ply) end)
end)

-- Another admin mod changing a group: put ours back (use !rank instead).
Rhylib.Hook.Add("CAMI.PlayerUsergroupChanged", "admin.rank", function(ply, old, new, source)
    if source == "Rhylib" or not IsValid(ply) or ply.rhylibSettingRank then return end
    timer.Simple(0, function() applyRank(ply) end)
end)

local function onlineBySid(sid)
    for _, p in ipairs(player.GetHumans()) do
        if p:SteamID64() == sid then return p end
    end
end
Admin.OnlineBySid = onlineBySid

function Admin.SetRank(sid, rankId, byName)
    if not Admin.RankById(rankId) then return false end
    if rankId == "user" then Data.Delete(KEY, sidKey("r", sid)) else Data.Set(KEY, sidKey("r", sid), rankId) end
    local p = onlineBySid(sid)
    if IsValid(p) then applyRank(p) end
    return true
end

--------------------------------------------------------------------------
-- Bans and warnings
--------------------------------------------------------------------------

local function banIndex()
    local t = Data.Get(KEY, "bans")
    return istable(t) and t or {}
end

function Admin.GetBan(sid)
    local b = Data.Get(KEY, sidKey("b", sid))
    if not istable(b) then return nil end
    if (b.untilT or 0) > 0 and b.untilT <= os.time() then
        Admin.Unban(sid, nil)   -- ran out
        return nil
    end
    return b
end

function Admin.Ban(sid, minutes, reason, caller, name)
    local b = {
        reason = reason ~= "" and reason or "No reason given",
        by = IsValid(caller) and caller:SteamID64() or "console", byName = nameOf(caller),
        at = os.time(), untilT = minutes > 0 and os.time() + minutes * 60 or 0, name = name or sid,
    }
    Data.Set(KEY, sidKey("b", sid), b)
    local idx = banIndex()
    idx["s" .. sid] = b.name
    Data.Set(KEY, "bans", idx)
    local why = "Banned " .. Admin.FormatMinutes(minutes) .. ": " .. b.reason
    local p = onlineBySid(sid)
    if IsValid(p) then
        p:Kick(why)
    else
        game.KickID(util.SteamIDFrom64(sid), why)   -- still loading in
    end
    -- Family-shared accounts of the banned one.
    for _, o in ipairs(player.GetHumans()) do
        if o.OwnerSteamID64 and o:OwnerSteamID64() == sid and o:SteamID64() ~= sid then o:Kick(why) end
    end
    return b
end

function Admin.Unban(sid, byName)
    local had = Data.Get(KEY, sidKey("b", sid)) ~= nil
    Data.Delete(KEY, sidKey("b", sid))
    local idx = banIndex()
    if idx["s" .. sid] then
        idx["s" .. sid] = nil
        Data.Set(KEY, "bans", idx)
    end
    return had
end

local function timeLeft(b)
    if (b.untilT or 0) <= 0 then return "permanent" end
    return Admin.FormatMinutes(math.max(1, math.ceil((b.untilT - os.time()) / 60))) .. " left"
end

-- Banned players can't join.
Rhylib.Hook.Add("CheckPassword", "admin.ban", function(sid64)
    local b = Admin.GetBan(sid64)
    if b then return false, "You are banned (" .. timeLeft(b) .. "): " .. (b.reason or "") end
end)

-- Also once they're in (family sharing: the account that owns the game too).
local function checkJoined(ply)
    if not IsValid(ply) or ply:IsBot() then return end
    for _, sid in ipairs({ ply:SteamID64(), ply.OwnerSteamID64 and ply:OwnerSteamID64() or nil }) do
        local b = sid and sid ~= "0" and Admin.GetBan(sid)
        if b then
            ply:Kick("You are banned (" .. timeLeft(b) .. "): " .. (b.reason or ""))
            return
        end
    end
end
Rhylib.Hook.Add("PlayerAuthed", "admin.ban", function(ply) timer.Simple(0, function() checkJoined(ply) end) end)
Rhylib.Hook.Add("PlayerInitialSpawn", "admin.ban", function(ply) timer.Simple(1, function() checkJoined(ply) end) end)

function Admin.Warn(sid, reason, byName)
    local w = Data.Get(KEY, sidKey("w", sid))
    if not istable(w) then w = {} end
    w[#w + 1] = { reason = reason, byName = byName, at = os.time() }
    while #w > 50 do table.remove(w, 1) end
    Data.Set(KEY, sidKey("w", sid), w)
    return #w
end

function Admin.Warnings(sid)
    local w = Data.Get(KEY, sidKey("w", sid))
    return istable(w) and w or {}
end

--------------------------------------------------------------------------
-- Targets
--------------------------------------------------------------------------

-- An online player from a name part, SteamID, SteamID64, ^ (you) or @
-- (who you look at). Returns player or nil, error.
function Admin.FindPlayer(caller, q)
    q = string.Trim(q or "")
    if q == "" then return nil, "Who? Give a name" end
    if q == "^" then
        if IsValid(caller) then return caller end
        return nil, "The console isn't a player"
    end
    if q == "@" then
        if not IsValid(caller) then return nil, "The console can't aim" end
        local e = caller:GetEyeTrace().Entity
        local L = Rhylib.Lying
        if L and L.Owner and L.Owner(e) then e = L.Owner(e) end
        if IsValid(e) and e:IsPlayer() then return e end
        return nil, "You aren't looking at a player"
    end
    local lower = string.lower(q)
    for _, p in ipairs(player.GetAll()) do
        if p:SteamID() == q or p:SteamID64() == q then return p end
    end
    local found
    for _, p in ipairs(player.GetAll()) do
        local n = string.lower(p:Nick())
        if n == lower then return p end
        if string.find(n, lower, 1, true) then
            if found then return nil, "More than one player matches \"" .. q .. "\"; be more exact" end
            found = p
        end
    end
    if found then return found end
    return nil, "No player matches \"" .. q .. "\""
end

-- A SteamID64 from an online player's name, a SteamID or a SteamID64.
-- Returns sid64, player (if online) or nil, error.
function Admin.FindId(caller, q)
    q = string.Trim(q or "")
    if string.match(q, "^%d+$") and #q >= 15 and #q <= 20 then return q, onlineBySid(q) end
    if string.match(q, "^STEAM_%d:%d:%d+$") then
        local sid = util.SteamIDTo64(q)
        if sid and sid ~= "0" then return sid, onlineBySid(sid) end
    end
    local p, err = Admin.FindPlayer(caller, q)
    if not p then return nil, err end
    if p:IsBot() then return nil, "That's a bot" end
    return p:SteamID64(), p
end

--------------------------------------------------------------------------
-- Running commands
--------------------------------------------------------------------------

Admin.handlers = Admin.handlers or {}

local function parseArg(kind, word)
    if kind == "number" then
        local n = tonumber(word)
        if not n or n ~= n or n == math.huge or n == -math.huge then return nil, "Expected a number, got \"" .. tostring(word) .. "\"" end
        return n
    elseif kind == "duration" then
        local m = Admin.ParseDuration(word)
        if not m then return nil, "Length like 30m, 2h, 1d, 1w or perm" end
        return m
    elseif kind == "onoff" then
        local w = string.lower(word or "")
        if w == "on" or w == "1" or w == "yes" or w == "true" then return true end
        if w == "off" or w == "0" or w == "no" or w == "false" then return false end
        return nil, "Expected on or off"
    end
    return word
end

-- caller: a player or NULL/nil (console). words: list of strings.
function Admin.Exec(caller, id, words)
    local cmd = Admin.byAlias[string.lower(id or "")]
    if not IsValid(caller) then caller = nil end   -- the server console
    if not cmd then return Admin.Tell(caller, "Unknown command: " .. tostring(id), true) end
    -- "<perm>.self" lets a rank use a command on itself only.
    local full = Admin.Has(caller, cmd.perm)
    if not full and not (cmd.target and Admin.Has(caller, cmd.perm .. ".self")) then
        return Admin.Tell(caller, "You don't have permission for " .. cmd.id, true)
    end
    words = words or {}
    local i = 1

    -- Target.
    local target, sid
    if cmd.target then
        local q = words[1]
        if (q == nil or q == "") and cmd.target == "opt" then
            -- (no target)
        elseif (q == nil or q == "") and cmd.target == "self" then
            target = caller
            if not IsValid(target) then return Admin.Tell(caller, "Give a player name", true) end
        elseif q == nil or q == "" then
            return Admin.Tell(caller, "Usage: !" .. cmd.id .. " <player>" .. (cmd.args[1] and " ..." or ""), true)
        else
            i = 2
            local err
            if cmd.target == "id" then
                sid, target = Admin.FindId(caller, q)
                if not sid then return Admin.Tell(caller, target, true) end
            else
                target, err = Admin.FindPlayer(caller, q)
                if not target then return Admin.Tell(caller, err, true) end
            end
        end
        if not full and target ~= caller then
            return Admin.Tell(caller, "You can only use " .. cmd.id .. " on yourself", true)
        end
        if IsValid(target) and not Admin.CanTarget(caller, target) then
            return Admin.Tell(caller, target:Nick() .. " has the same rank as you or higher", true)
        end
        if cmd.target == "id" and not IsValid(target) and sid and IsValid(caller) then
            -- Offline: their stored rank still counts.
            local r = Admin.RankById(storedRank(sid) or "user")
            if isOwnerId(sid) or (r and (r.level or 0) >= Admin.Level(caller)) then
                return Admin.Tell(caller, "That player has the same rank as you or higher", true)
            end
        end
        if IsValid(target) and not sid and target:IsPlayer() and not target:IsBot() then sid = target:SteamID64() end
    end

    -- Arguments.
    local args = {}
    for n, a in ipairs(cmd.args) do
        local key, label, kind = a[1], a[2], a[3]
        local word
        if kind == "text" then
            word = table.concat(words, " ", i)
            i = #words + 1
        else
            word = words[i]
            i = i + 1
        end
        if (word == nil or word == "") and kind ~= "text" then
            return Admin.Tell(caller, "Missing " .. string.lower(label) .. " (!" .. cmd.id .. ")", true)
        end
        local v, err = parseArg(kind, word or "")
        if v == nil then return Admin.Tell(caller, err, true) end
        args[key] = v
    end

    local fn = Admin.handlers[cmd.id]
    if not fn then return Admin.Tell(caller, "Not available: " .. cmd.id, true) end
    local ok, text, err = pcall(fn, caller, target, args, { sid = sid, cmd = cmd })
    if not ok then
        ErrorNoHalt("[Rhylib Admin] " .. cmd.id .. ": " .. tostring(text) .. "\n")
        return Admin.Tell(caller, "That failed (see the server console)", true)
    end
    if err then return Admin.Tell(caller, err, true) end
    if text then
        echo(text)
        Admin.Log(text)
    end
end

-- Chat: !command ... or /command ... (only our commands; others pass on).
-- Muted players can't talk (but can still use commands they have).
local TALK = { ["/"] = true, ooc = true, a = true, advert = true, pm = true, w = true, y = true, me = true,
    radio = true, g = true, group = true, broadcast = true, comms = true, looc = true }
Rhylib.Hook.Add("PlayerSay", "admin.chat", function(ply, text)
    local first = string.sub(text, 1, 1)
    local isPrefix = false
    for _, p in ipairs(Admin.Cfg("prefixes") or {}) do
        if first == p then isPrefix = true end
    end
    if isPrefix then
        local words = Admin.Split(string.sub(text, 2))
        local id = table.remove(words, 1)
        -- "/" commands DarkRP knows (/give money, ...) stay DarkRP's.
        local darkrp = first == "/" and id and DarkRP and DarkRP.getChatCommand and DarkRP.getChatCommand(string.lower(id))
        if id and not darkrp and Admin.byAlias[string.lower(id)] then
            Admin.Exec(ply, id, words)
            return ""
        end
        -- Muted: other commands still work, talking ones don't.
        if darkrp and not TALK[string.lower(id)] then return end
    end
    if Admin.muted and Admin.muted[ply] then
        Admin.Tell(ply, "You are muted", true)
        return ""
    end
end, -50)

-- Console: rhylib_admin <command> <args...> (server console = owner).
concommand.Add("rhylib_admin", function(ply, _, args)
    local id = table.remove(args, 1)
    if not id then
        local names = {}
        for _, c in ipairs(Admin.COMMANDS) do names[#names + 1] = c.id end
        return Admin.Tell(ply, "rhylib_admin <command> ...: " .. table.concat(names, ", "))
    end
    Admin.Exec(ply, id, args)
end)

-- The staff menu: admin.run (command id, words).
Rhylib.Net.Receive("admin.run", function(ply)
    local id = net.ReadString()
    local n = net.ReadUInt(4)
    local words = {}
    for k = 1, n do words[k] = string.sub(net.ReadString(), 1, 200) end
    Admin.Exec(ply, id, words)
end, { rate = 4, burst = 8 })

-- Lists for the staff menu: 1 bans, 2 log, 3 warnings of a SteamID64.
Rhylib.Net.Receive("admin.listget", function(ply)
    local which = net.ReadUInt(2)
    local arg = net.ReadString()
    if which == 1 and not Admin.Has(ply, "bans") and not Admin.Has(ply, "ban") then return end
    if which == 2 and not Admin.Has(ply, "logs") then return end
    if which == 3 and not Admin.Has(ply, "warn") then return end
    local rows = {}
    if which == 1 then
        for k in pairs(banIndex()) do
            local sid = string.sub(k, 2)
            local b = Admin.GetBan(sid)
            if b then rows[#rows + 1] = { sid, b.name or sid, b.reason or "", b.byName or "?", timeLeft(b) } end
        end
    elseif which == 2 then
        local log = Data.Get(KEY, "log")
        for k, e in ipairs(istable(log) and log or {}) do
            if k > 150 then break end
            rows[#rows + 1] = { tostring(e.t or 0), e.text or "" }
        end
    elseif which == 3 and string.match(arg, "^%d+$") then
        for _, w in ipairs(Admin.Warnings(arg)) do
            rows[#rows + 1] = { tostring(w.at or 0), w.reason or "", w.byName or "?" }
        end
    end
    Rhylib.Net.Start("admin.list")
    net.WriteUInt(which, 2)
    net.WriteUInt(math.min(#rows, 255), 8)
    for k = 1, math.min(#rows, 255) do
        local r = rows[k]
        net.WriteUInt(#r, 3)
        for _, v in ipairs(r) do net.WriteString(string.sub(v, 1, 300)) end
    end
    net.Send(ply)
end, { rate = 2, burst = 4 })
