--[[
    Battalion stats, shown on the battalion computer.

    Counted for the player's battalion (job category) when it happens:
      kd droid/NPC kills   kp player kills (not your own battalion)
      de deaths            rv revives given     he heals given (rhylib_medical)
      ar arrests (rhylib_mp)   mi minutes played   mo money earned (DarkRP)
      at sessions attended (checked in at the computer)

    Each battalion keeps buckets: all time, today, this and last week, this
    month (older day/week/month buckets are dropped). Each bucket has the
    totals and one row per member. Counts gather in memory and are saved
    once a minute (and at shutdown).

      dp.stats   entity, period -> dp.statsr: totals and members

    Data "dp_stats"/battalion = { b = { [bucket] = { t = {...}, p = { ["s"..sid] = {n = name, ...} } } } }
    (member keys are prefixed: JSON would turn a bare SteamID64 into a number)
]]

local D = Rhylib.Datapad

Rhylib.Net.Register("dp.statsr")

D.STAT_KEYS = { "kd", "kp", "de", "rv", "he", "ar", "mi", "mo", "at" }
D.PERIODS = { "today", "week", "lastweek", "month", "all" }   -- index sent on the network

local dirty = {}   -- [battalion] = true

local function bucketKeys(now)
    now = now or os.time()
    return {
        today = "d" .. os.date("%Y%m%d", now),
        week = "w" .. os.date("%Y-%W", now),
        lastweek = "w" .. os.date("%Y-%W", now - 7 * 86400),
        month = "m" .. os.date("%Y%m", now),
        all = "all",
    }
end

local function stats(bn)
    local s = D.Load("dp_stats", bn, nil)
    s.b = s.b or {}
    return s
end

-- Drop day/week/month buckets that are no longer shown.
local function prune(s)
    local keep = {}
    for _, k in pairs(bucketKeys()) do keep[k] = true end
    for k in pairs(s.b) do
        if not keep[k] then s.b[k] = nil end
    end
end

-- Add n to stat for this player's battalion.
function D.AddStat(ply, stat, n)
    if not (IsValid(ply) and ply:IsPlayer()) or ply:IsBot() then return end
    local bn = D.Battalion(ply)
    if bn == "" or n == 0 then return end
    local s = stats(bn)
    local key = "s" .. (ply:SteamID64() or "0")
    local keys = bucketKeys()
    for _, bk in ipairs({ keys.today, keys.week, keys.month, keys.all }) do   -- (last week is only read)
        local b = s.b[bk]
        if not b then
            b = { t = {}, p = {} }
            s.b[bk] = b
        end
        b.t[stat] = (b.t[stat] or 0) + n
        local p = b.p[key]
        if not p then
            p = {}
            b.p[key] = p
        end
        p.n = ply:Nick()
        p[stat] = (p[stat] or 0) + n
    end
    dirty[bn] = true
end

local function flush()
    for bn in pairs(dirty) do
        local s = stats(bn)
        prune(s)
        D.Store("dp_stats", bn, s)
    end
    dirty = {}
end
timer.Create("Rhylib.Datapad.Stats", 60, 0, function()
    -- A minute played for everyone in a battalion.
    for _, p in ipairs(player.GetHumans()) do
        D.AddStat(p, "mi", 1)
    end
    flush()
end)
Rhylib.Hook.Add("ShutDown", "datapad.stats", flush, -10)  -- before Data flushes at 0

--------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------

Rhylib.Hook.Add("OnNPCKilled", "datapad.stats", function(npc, attacker)
    if IsValid(attacker) and attacker:IsPlayer() then D.AddStat(attacker, "kd", 1) end
end)

Rhylib.Hook.Add("PlayerDeath", "datapad.stats", function(victim, _, attacker)
    D.AddStat(victim, "de", 1)
    if IsValid(attacker) and attacker:IsPlayer() and attacker ~= victim
        and D.Battalion(attacker) ~= D.Battalion(victim) then
        D.AddStat(attacker, "kp", 1)
    end
end)

Rhylib.Hook.Add("Rhylib.PlayerRevived", "datapad.stats", function(ply, by)
    if IsValid(by) and by ~= ply then D.AddStat(by, "rv", 1) end
end)

Rhylib.Hook.Add("Rhylib.PlayerHealed", "datapad.stats", function(ply, by)
    if IsValid(by) then D.AddStat(by, "he", 1) end
end)

Rhylib.Hook.Add("Rhylib.PlayerJailed", "datapad.stats", function(ply, by)
    if IsValid(by) then D.AddStat(by, "ar", 1) end
end)

-- DarkRP: money gained (salary, sales, ...), not money spent.
Rhylib.Hook.Add("playerWalletChanged", "datapad.stats", function(ply, amount)
    if isnumber(amount) and amount > 0 then D.AddStat(ply, "mo", math.floor(amount)) end
end)

--------------------------------------------------------------------------
-- Reading
--------------------------------------------------------------------------

D.TermRecv("dp.stats", {
    read = function() return net.ReadUInt(3) end,
    run = function(ply, ent, a, period)
        if D.IsMedTerm(ent) or not a.view then return end
        local bn = ent:GetBattalion()
        if bn == "" then return end
        local pname = D.PERIODS[period] or "all"
        local b = stats(bn).b[bucketKeys()[pname]] or { t = {}, p = {} }
        local members = {}
        for _, p in pairs(b.p) do members[#members + 1] = p end
        -- Most active first (by minutes played), at most 60 rows.
        table.sort(members, function(x, y) return (x.mi or 0) > (y.mi or 0) end)
        Rhylib.Net.Start("dp.statsr")
        net.WriteUInt(period, 3)
        for _, k in ipairs(D.STAT_KEYS) do net.WriteUInt(math.Clamp(b.t[k] or 0, 0, 2 ^ 31), 32) end
        local n = math.min(#members, 60)
        net.WriteUInt(n, 7)
        for i = 1, n do
            local p = members[i]
            net.WriteString(p.n or "?")
            for _, k in ipairs(D.STAT_KEYS) do net.WriteUInt(math.Clamp(p[k] or 0, 0, 2 ^ 31), 32) end
        end
        net.Send(ply)
    end,
}, { rate = 3, burst = 4 })
