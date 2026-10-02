--[[
    Battalion computer: orders, leave, applications, session sign-ups.
    Ranks come from rhylib_roster (Rhylib.Roster): "managers" are rank
    manageRank+ (SGT), "officers" boardRank+ (LT), admins always.

    Orders        Data "dp_orders"/bn = { txt, by, t }. Officers set them;
                  online members get a chat note and the sync light.
    Leave         Data "dp_loa"/bn = list { id, s, n, from, to, why }.
                  Members file their own; managers can remove any. Shown on
                  the roster page while it runs (Rhylib.RosterNote).
    Applications  Data "dp_apps"/bn = list { id, s, n, txt, t, st, by }
                  (st 0 pending, 1 accepted, 2 declined, 3 withdrawn) and
                  Data "dp_myapp"/sid = { bn, id, st }. A CT without a
                  battalion applies at its computer; managers accept or
                  decline. Accepted: a popup (now, or when they next join)
                  to join or turn it down. Not required: NCOs can still
                  whitelist directly on the roster page.
    Sessions      board posts (section Session) carry rv = { ["s"..sid] =
                  { n, s } } (1 attending, 2 maybe, 3 can't) and ci =
                  { ["s"..sid] = name } (checked in at the computer, from
                  15 min before to 60 min after the start; counts as the
                  "at" stat).

      dp.uopen  entity -> dp.unit (orders, leave, my application, pending list)
      dp.uorders / dp.uloa / dp.uloadel / dp.uapply / dp.udecide   entity, ...
      dp.ursvp / dp.ucheck   entity, post id (, choice)
      dp.uwithdraw entity: withdraw your pending application
      dp.uanswer  (anywhere) join? for an accepted application
      dp.uprompt  server -> player: 0 pending note, 1 accepted popup, 2 declined
]]

local D = Rhylib.Datapad
local Data = Rhylib.Data

for _, n in ipairs({ "dp.unit", "dp.uprompt" }) do Rhylib.Net.Register(n) end

local function sid(ply) return ply:SteamID64() or "" end
local function R() return Rhylib.Roster end

local function rankOf(ply, bn)
    local Ro = R()
    if not Ro then return 0 end
    local c = Ro.Get(ply)
    return c.bn == bn and c.rank or 0
end
local function atLeast(ply, bn, cfgKey, fallback)
    local Ro = R()
    local need = Ro and Ro.RankIndex(Ro.Cfg(cfgKey)) or fallback
    return rankOf(ply, bn) >= need
end
local function isManager(ply, bn, admin) return admin or atLeast(ply, bn, "manageRank", 4) end
local function isOfficer(ply, bn, admin) return admin or atLeast(ply, bn, "boardRank", 6) end
local function isMember(ply, bn) return bn ~= "" and D.Battalion(ply) == bn end
D.UnitRank, D.IsUnitManager, D.IsUnitOfficer, D.IsUnitMember = rankOf, isManager, isOfficer, isMember

local function list(ns, bn)
    local t = D.Load(ns, bn, nil)
    if not t.list then t.next, t.list = 1, {} end
    return t
end

local function note(ply, msg) if IsValid(ply) then ply:ChatPrint(msg) end end

local function battalionPlayers(bn)
    local out = {}
    for _, p in ipairs(player.GetHumans()) do
        if D.Battalion(p) == bn then out[#out + 1] = p end
    end
    return out
end

--------------------------------------------------------------------------
-- Leave of absence
--------------------------------------------------------------------------

-- Leave that hasn't ended yet (drops old ones).
local function activeLeave(bn)
    local t = list("dp_loa", bn)
    local now = os.time()
    local keep, changed = {}, false
    for _, e in ipairs(t.list) do
        if (e.to or 0) + 86400 >= now then keep[#keep + 1] = e else changed = true end
    end
    if changed then
        t.list = keep
        D.Store("dp_loa", bn, t)
    end
    return t
end

Rhylib.Hook.Add("Rhylib.RosterNote", "datapad.loa", function(bn, id)
    local now = os.time()
    for _, e in ipairs(activeLeave(bn).list) do
        if e.s == id and e.from <= now + 86400 then
            return (e.from > now and "leave from " .. os.date("%d %b", e.from) or "on leave") .. " until " .. os.date("%d %b", e.to)
        end
    end
end)

--------------------------------------------------------------------------
-- Applications
--------------------------------------------------------------------------

local function myApp(id)
    local t = Data.Get("dp_myapp", id)
    if not istable(t) then return nil end
    -- Pending, but gone from the battalion's list (renamed, cleared): forget it.
    if t.st == 0 then
        local found = false
        for _, a in ipairs(list("dp_apps", t.bn or "").list) do
            if a.id == t.id and a.st == 0 then found = true break end
        end
        if not found then
            Data.Delete("dp_myapp", id)
            return nil
        end
    end
    return t
end

local function setApp(bn, appId, st, by)
    local t = list("dp_apps", bn)
    for _, a in ipairs(t.list) do
        if a.id == appId then
            a.st, a.by = st, by or a.by
            D.Store("dp_apps", bn, t)
            return a
        end
    end
end

-- What the applicant should be told (now, or when they join).
local function prompt(ply, kind, bn, by)
    Rhylib.Net.Start("dp.uprompt")
    net.WriteUInt(kind, 2)
    net.WriteString(bn)
    net.WriteString(by or "")
    net.Send(ply)
end

local function checkApplicant(ply)
    local id = sid(ply)
    local m = myApp(id)
    if not m then return end
    if m.st == 0 then
        prompt(ply, 0, m.bn)
    elseif m.st == 1 then
        prompt(ply, 1, m.bn, m.by)
    elseif m.st == 2 then
        prompt(ply, 2, m.bn, m.by)
        Data.Delete("dp_myapp", id)   -- told once
    end
end

Rhylib.Hook.Add("PlayerInitialSpawn", "datapad.apps", function(ply)
    timer.Simple(12, function() if IsValid(ply) then checkApplicant(ply) end end)
end)

-- Whitelisted another way: the application is done.
Rhylib.Hook.Add("Rhylib.RosterJoined", "datapad.apps", function(id, bn)
    local m = myApp(id)
    if m then
        if m.st == 0 or m.st == 1 then setApp(m.bn, m.id, m.bn == bn and 1 or 3) end
        Data.Delete("dp_myapp", id)
    end
end)

-- The applicant's answer to an accepted application (from the popup, anywhere).
Rhylib.Net.Receive("dp.uanswer", function(ply)
    local join = net.ReadBool()
    local id = sid(ply)
    local m = myApp(id)
    if not m or m.st ~= 1 then return end
    if join then
        local Ro = R()
        if Ro and Ro.AddMember(id, m.bn, ((m.by or "") ~= "" and m.by or "An officer") .. " accepted the application of") then
            Data.Delete("dp_myapp", id)   -- (RosterJoined clears it too)
            note(ply, "Welcome to the " .. m.bn .. "!")
        else
            note(ply, "You couldn't be added right now (already in a battalion, or not a trained trooper?)")
        end
    else
        Data.Delete("dp_myapp", id)
        setApp(m.bn, m.id, 3)
        note(ply, "You turned down the " .. m.bn .. ".")
    end
end, { rate = 2, burst = 3 })

--------------------------------------------------------------------------
-- The unit page
--------------------------------------------------------------------------

local STATUS = { [0] = "pending", [1] = "accepted", [2] = "declined", [3] = "withdrawn" }

function D.SendUnit(ply, ent, a)
    local bn = ent:GetBattalion()
    local admin = a.admin
    local member = isMember(ply, bn)
    local manager = isManager(ply, bn, admin)
    local orders = a.view and D.Load("dp_orders", bn, {}) or {}   -- members, MPs, admins
    local leave = activeLeave(bn).list
    local m = myApp(sid(ply))
    local Ro = R()
    local c = Ro and Ro.Get(ply)

    Rhylib.Net.Start("dp.unit")
    net.WriteEntity(ent)
    net.WriteBool(member)
    net.WriteBool(manager)
    net.WriteBool(isOfficer(ply, bn, admin))
    -- Can apply: trained, no battalion, nothing pending.
    net.WriteBool(c and c.trained and c.bn == "" and not (m and (m.st == 0 or m.st == 1)) or false)
    net.WriteString(m and m.bn or "")
    net.WriteUInt(m and m.st or 0, 2)
    net.WriteString(orders.txt or "")
    net.WriteString(orders.by or "")
    net.WriteUInt(orders.t or 0, 32)
    -- Leave (members and up see it).
    local nl = (member or admin) and math.min(#leave, 63) or 0
    net.WriteUInt(nl, 6)
    for i = 1, nl do
        local e = leave[i]
        net.WriteUInt(e.id, 16)
        net.WriteString(e.n or "?")
        net.WriteUInt(e.from or 0, 32)
        net.WriteUInt(e.to or 0, 32)
        net.WriteString(e.why or "")
        net.WriteBool(e.s == sid(ply))
    end
    -- Applications (managers): pending first, then the last few decided.
    local apps = {}
    if manager then
        for _, x in ipairs(list("dp_apps", bn).list) do
            if x.st == 0 and #apps < 63 then apps[#apps + 1] = x end
        end
        for _, x in ipairs(list("dp_apps", bn).list) do
            if x.st ~= 0 and #apps < 63 then apps[#apps + 1] = x end
        end
    end
    net.WriteUInt(#apps, 6)
    for _, x in ipairs(apps) do
        net.WriteUInt(x.id, 16)
        net.WriteString(x.n or "?")
        net.WriteString(x.txt or "")
        net.WriteUInt(x.t or 0, 32)
        net.WriteUInt(x.st or 0, 2)
        net.WriteString(x.by or "")
    end
    net.Send(ply)
end

local function unitTerm(ent) return not D.IsMedTerm(ent) and ent:GetBattalion() ~= "" end

D.TermRecv("dp.uopen", {
    run = function(ply, ent, a)
        if unitTerm(ent) then D.SendUnit(ply, ent, a) end
    end,
}, { rate = 3, burst = 4 })

D.TermRecv("dp.uorders", {
    read = function() return D.Clip(net.ReadString(), D.Cfg("bodyMax"), true) end,
    run = function(ply, ent, a, txt)
        if not unitTerm(ent) then return end
        local bn = ent:GetBattalion()
        if not isOfficer(ply, bn, a.admin) then return end
        D.Store("dp_orders", bn, { txt = txt, by = ply:Nick(), t = os.time() })
        D.Touch(bn)
        for _, p in ipairs(battalionPlayers(bn)) do
            if p ~= ply then p:ChatPrint("New orders for the " .. bn .. " from " .. ply:Nick() .. ". Check the battalion computer or your datapad.") end
        end
        D.SendUnit(ply, ent, a)
    end,
}, { rate = 2, burst = 3 })

D.TermRecv("dp.uloa", {
    read = function() return { from = net.ReadUInt(32), to = net.ReadUInt(32), why = D.Clip(net.ReadString(), 120) } end,
    run = function(ply, ent, a, arg)
        if not unitTerm(ent) then return end
        local bn = ent:GetBattalion()
        if not isMember(ply, bn) then return end
        local now = os.time()
        if arg.to < arg.from or arg.to < now - 86400 or arg.to - arg.from > 120 * 86400 then
            note(ply, "Check the dates (at most 120 days, and not in the past)")
            return
        end
        local t = activeLeave(bn)
        -- One open leave per person: a new one replaces it.
        for i = #t.list, 1, -1 do
            if t.list[i].s == sid(ply) then table.remove(t.list, i) end
        end
        table.insert(t.list, 1, { id = t.next, s = sid(ply), n = ply:Nick(), from = arg.from, to = arg.to, why = arg.why })
        t.next = t.next % 65535 + 1
        D.Store("dp_loa", bn, t)
        D.SendUnit(ply, ent, a)
    end,
}, { rate = 2, burst = 3 })

D.TermRecv("dp.uloadel", {
    read = function() return net.ReadUInt(16) end,
    run = function(ply, ent, a, id)
        if not unitTerm(ent) then return end
        local bn = ent:GetBattalion()
        local t = activeLeave(bn)
        for i, e in ipairs(t.list) do
            if e.id == id and (e.s == sid(ply) or isManager(ply, bn, a.admin)) then
                table.remove(t.list, i)
                D.Store("dp_loa", bn, t)
                break
            end
        end
        D.SendUnit(ply, ent, a)
    end,
})

D.TermRecv("dp.uapply", {
    read = function() return D.Clip(net.ReadString(), 600, true) end,
    run = function(ply, ent, a, txt)
        if not unitTerm(ent) then return end
        local bn = ent:GetBattalion()
        local Ro = R()
        local c = Ro and Ro.Get(ply)
        local id = sid(ply)
        if id == "" or not c or not c.trained or c.bn ~= "" then
            note(ply, "Only clone troopers without a battalion can apply")
            return
        end
        local m = myApp(id)
        if m and (m.st == 0 or m.st == 1) then
            note(ply, "You already have an application with the " .. m.bn)
            return
        end
        if txt == "" then txt = "(no message)" end
        local t = list("dp_apps", bn)
        table.insert(t.list, 1, { id = t.next, s = id, n = ply:Nick(), txt = txt, t = os.time(), st = 0 })
        Data.Set("dp_myapp", id, { bn = bn, id = t.next, st = 0 })
        t.next = t.next % 65535 + 1
        -- Keep 100: drop the oldest decided ones (pending ones stay).
        for i = #t.list, 1, -1 do
            if #t.list <= 100 then break end
            if t.list[i].st ~= 0 then table.remove(t.list, i) end
        end
        D.Store("dp_apps", bn, t)
        note(ply, "Application sent to the " .. bn .. ". Check its status here at the battalion computer.")
        -- Tell the battalion's managers who are online.
        for _, p in ipairs(battalionPlayers(bn)) do
            if isManager(p, bn, false) then p:ChatPrint(ply:Nick() .. " applied to the " .. bn .. " (battalion computer, Applications)") end
        end
        D.SendUnit(ply, ent, a)
    end,
}, { rate = 1, burst = 2 })

-- Withdraw your pending application (at that battalion's computer).
D.TermRecv("dp.uwithdraw", {
    run = function(ply, ent, a)
        if not unitTerm(ent) then return end
        local id = sid(ply)
        local m = myApp(id)
        if not m or m.st ~= 0 or m.bn ~= ent:GetBattalion() then return end
        setApp(m.bn, m.id, 3)
        Data.Delete("dp_myapp", id)
        note(ply, "Application withdrawn.")
        D.SendUnit(ply, ent, a)
    end,
}, { rate = 1, burst = 2 })

D.TermRecv("dp.udecide", {
    read = function() return { id = net.ReadUInt(16), ok = net.ReadBool() } end,
    run = function(ply, ent, a, arg)
        if not unitTerm(ent) then return end
        local bn = ent:GetBattalion()
        if not isManager(ply, bn, a.admin) then return end
        local app
        for _, x in ipairs(list("dp_apps", bn).list) do
            if x.id == arg.id then app = x end
        end
        if not app or app.st ~= 0 then return end
        local st = arg.ok and 1 or 2
        setApp(bn, app.id, st, ply:Nick())
        local m = myApp(app.s)
        if m and m.bn == bn and m.id == app.id then
            m.st, m.by = st, ply:Nick()
            Data.Set("dp_myapp", app.s, m)
        end
        local target = player.GetBySteamID64(app.s)
        if IsValid(target) then checkApplicant(target) end
        D.SendUnit(ply, ent, a)
    end,
})

--------------------------------------------------------------------------
-- Sessions: sign-ups and check-in
--------------------------------------------------------------------------

local function findPost(bn, id)
    local b = D.Board(bn)
    for _, p in ipairs(b.list) do
        if p.id == id then return p, b end
    end
end

D.TermRecv("dp.ursvp", {
    read = function() return { id = net.ReadUInt(16), s = net.ReadUInt(2) } end,
    run = function(ply, ent, a, arg)
        if not unitTerm(ent) then return end
        local bn = ent:GetBattalion()
        if not isMember(ply, bn) or arg.s < 1 or arg.s > 3 then return end
        local p, b = findPost(bn, arg.id)
        if not p or p.sec ~= D.SEC_SESSION then return end
        p.rv = p.rv or {}
        p.rv["s" .. sid(ply)] = { n = ply:Nick(), s = arg.s }
        D.StoreQuiet("dp_board", bn, b)
        D.SendPost(ply, p)
    end,
})

D.TermRecv("dp.ucheck", {
    read = function() return net.ReadUInt(16) end,
    run = function(ply, ent, a, id)
        if not unitTerm(ent) then return end
        local bn = ent:GetBattalion()
        if not isMember(ply, bn) then return end
        local p, b = findPost(bn, id)
        if not p or p.sec ~= D.SEC_SESSION then return end
        local now = os.time()
        if now < (p.at or 0) - 15 * 60 or now > (p.at or 0) + 60 * 60 then
            note(ply, "Check-in opens 15 minutes before the session and closes an hour after it starts")
            return
        end
        p.ci = p.ci or {}
        local key = "s" .. sid(ply)
        if p.ci[key] then return end
        p.ci[key] = ply:Nick()
        D.StoreQuiet("dp_board", bn, b)
        if D.AddStat then D.AddStat(ply, "at", 1) end
        note(ply, "Checked in for " .. (p.ti or "the session"))
        D.SendPost(ply, p)
    end,
})
