--[[
    Battalion computer / medical holotable window.

    Top: upload your notes; admins set the battalion. Tabs:
      Logs     search (title, text, author), time filter, MP-only filter;
               reader; moderators delete entries and ban authors
      Board    battalion computers: Info, Plans and Sessions posts, pinned
               first, upcoming sessions with a countdown, past ones archived
      Stats    battalion totals and members for a period
      Bans     moderators: who can't upload
    The medical holotable has Records (and Bans) only.
]]

local D = Rhylib.Datapad

local function K() return Rhylib.Menus and Rhylib.Menus.Kit end
local function when(t) return t and t > 0 and os.date("%d %b %Y %H:%M", t) or "" end

local panel
local term            -- last dp.term
local tab = "logs"
local selected        -- selected log id
local bodies = {}     -- [log id] = text
local filter = { q = "", days = 0, mp = false, ids = nil }   -- ids: set from the last search
local board, boardSel, boardBodies, editing = nil, nil, {}, nil
local statsPeriod, statsData, statsSort = 2, nil, "mi"

local SECTIONS = { "Info", "Plans", "Session" }
local STAT_NAMES = {
    kd = "Droid kills", kp = "Player kills", de = "Deaths", rv = "Revives",
    he = "Heals", ar = "Arrests", mi = "Hours", mo = "Money",
}
local STAT_KEYS = { "kd", "kp", "de", "rv", "he", "ar", "mi", "mo" }
local PERIOD_NAMES = { "Today", "This week", "Last week", "This month", "All time" }

local function send(name, fn)
    Rhylib.Net.Start(name)
    net.WriteEntity(term.ent)
    if fn then fn() end
    net.SendToServer()
end

local build

local function statText(k, v)
    if k == "mi" then return string.format("%.1f", (v or 0) / 60) end
    if k == "mo" then return string.Comma and string.Comma(v or 0) or tostring(v or 0) end
    return tostring(v or 0)
end

local function countdown(at)
    local d = at - os.time()
    if d <= 0 then return "now" end
    if d < 3600 then return "in " .. math.ceil(d / 60) .. " min" end
    if d < 86400 then return string.format("in %d h %d min", math.floor(d / 3600), math.floor(d % 3600 / 60)) end
    return string.format("in %d d %d h", math.floor(d / 86400), math.floor(d % 86400 / 3600))
end

-- A two-line list row: title, dim line under it.
local function listRow(parent, title, sub, isSel, onClick, tag)
    local k = K()
    local s = k.S
    local b = k.Button(parent, "", onClick, { small = true, align = "left", selected = isSel })
    b:SetTall(s(44))
    b:Dock(TOP)
    b:DockMargin(0, 0, s(8), s(3))
    local paint = b.Paint
    function b:Paint(w, hh)
        paint(self, w, hh)
        local x = s(14)
        if tag then
            k.Caps(tag, x, s(14), k.C.accent)
            surface.SetFont(k.Font(12, 700))
            x = x + surface.GetTextSize(string.upper(tag)) + s(8)
        end
        draw.SimpleText(k.Fit(title, k.Font(14, 600), w - x - s(12)), k.Font(14, 600), x, s(6), k.C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText(k.Fit(sub, k.Font(11), w - s(26)), k.Font(11), s(14), hh - s(6), k.C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
        return true
    end
    return b
end

local function label(parent, text, col, size)
    local k = K()
    local l = k.Label(parent, text, size or 13, 400, col or k.C.textDim)
    l:Dock(TOP)
    return l
end

local function columns(body)
    local k = K()
    local s = k.S
    local left = vgui.Create("DPanel", body)
    left:Dock(LEFT)
    left:SetWide(s(430))
    left.Paint = nil
    local right = vgui.Create("DPanel", body)
    right:Dock(FILL)
    right:DockMargin(s(16), 0, 0, 0)
    right.Paint = nil
    return left, right
end

--------------------------------------------------------------------------
-- Logs
--------------------------------------------------------------------------

local function entryById(id)
    for _, e in ipairs(term.entries) do
        if e.id == id then return e end
    end
end

local function logReader(parent)
    local k = K()
    local s = k.S
    local e = selected and entryById(selected)
    if not e then
        label(parent, "Pick an entry to read it.")
        return
    end
    local h = k.Heading(parent, e.title)
    h:Dock(TOP)
    local by = label(parent, "By " .. e.author .. (e.pn ~= "" and (" · patient " .. e.pn) or "") .. " · " .. when(e.t))
    by:DockMargin(0, s(4), 0, s(8))
    if term.mod then
        local row = vgui.Create("DPanel", parent)
        row:Dock(BOTTOM)
        row:SetTall(s(30))
        row:DockMargin(0, s(8), 0, 0)
        row.Paint = nil
        local del = k.Button(row, "Delete entry", function()
            send("dp.tdel", function() net.WriteUInt(e.id, 20) end)
            selected = nil
        end, { small = true, danger = true })
        del:Dock(LEFT)
        del:SetWide(s(140))
        local ban = k.Button(row, "Ban author", function()
            send("dp.tban", function() net.WriteUInt(e.id, 20) end)
        end, { small = true, danger = true })
        ban:Dock(LEFT)
        ban:SetWide(s(140))
        ban:DockMargin(s(6), 0, 0, 0)
    end
    local sp = k.Scroll(parent)
    sp:Dock(FILL)
    local body = k.Label(sp, bodies[e.id] or "Loading…", 14, 400, k.C.text)
    body:Dock(TOP)
    body:DockMargin(0, 0, s(10), 0)
    if not bodies[e.id] then send("dp.tread", function() net.WriteUInt(e.id, 20) end) end
end

local function runSearch()
    if filter.q == "" and filter.days == 0 then
        filter.ids = nil
        build()
        return
    end
    send("dp.tfind", function()
        net.WriteString(string.sub(filter.q, 1, 64))
        net.WriteUInt(filter.days, 10)
    end)
end

local function logsTab(body)
    local k = K()
    local s = k.S
    -- Search bar.
    local bar = vgui.Create("DPanel", body)
    bar:Dock(TOP)
    bar:SetTall(s(30))
    bar:DockMargin(0, 0, 0, s(8))
    bar.Paint = nil
    local q = k.TextEntry(bar, "Search title, text or author")
    q:Dock(LEFT)
    q:SetWide(s(300))
    q:SetText(filter.q)
    q.OnEnter = function(self)
        filter.q = string.Trim(self:GetText() or "")
        runSearch()
    end
    local go = k.Button(bar, "Search", function() q:OnEnter() end, { small = true, accent = true })
    go:Dock(LEFT)
    go:SetWide(s(80))
    go:DockMargin(s(6), 0, s(12), 0)
    if not term.med then
        local mp = k.Button(bar, "MP only", function()
            filter.mp = not filter.mp
            build()
        end, { small = true, selected = function() return filter.mp end })
        mp:Dock(RIGHT)
        mp:SetWide(s(90))
        mp:DockMargin(s(6), 0, 0, 0)
    end
    local days = k.Choices(bar, { { 0, "Any time" }, { 1, "Today" }, { 7, "Week" }, { 30, "Month" } },
        function() return filter.days end,
        function(v)
            filter.days = v
            filter.q = string.Trim(q:GetText() or "")
            runSearch()
        end)
    days:Dock(FILL)

    local left, right = columns(body)
    local shown = {}
    for _, e in ipairs(term.entries) do
        if (not filter.ids or filter.ids[e.id]) and (not filter.mp or e.mp) then shown[#shown + 1] = e end
    end
    local h = k.Heading(left, (term.med and "Medical records" or "Logs") .. " (" .. #shown .. (#shown ~= #term.entries and (" of " .. #term.entries) or "") .. ")")
    h:Dock(TOP)
    local sp = k.Scroll(left)
    sp:Dock(FILL)
    if #shown == 0 then label(sp, #term.entries == 0 and "Nothing uploaded yet." or "Nothing matches.") end
    for _, e in ipairs(shown) do
        local sub = e.author .. (e.pn ~= "" and (" → " .. e.pn) or "") .. "  ·  " .. when(e.t)
        listRow(sp, e.title, sub, function() return selected == e.id end, function()
            selected = e.id
            build()
        end, e.mp and "MP" or nil)
    end
    logReader(right)
end

--------------------------------------------------------------------------
-- Board
--------------------------------------------------------------------------

local function postById(id)
    if not board then return nil end
    for _, p in ipairs(board.posts) do
        if p.id == id then return p end
    end
end

local function postSub(p)
    local s = p.author .. "  ·  " .. when(p.t)
    if p.sec == 3 and p.at > 0 then
        s = when(p.at) .. (p.at > os.time() and ("  (" .. countdown(p.at) .. ")") or "  (past)") .. "  ·  " .. p.author
    end
    return s
end

local function editor(parent, p)
    local k = K()
    local s = k.S
    local sec = p and p.sec or 1
    local h = k.Heading(parent, p and "Edit post" or "New post")
    h:Dock(TOP)
    local secRow = vgui.Create("DPanel", parent)
    secRow:Dock(TOP)
    secRow:SetTall(s(30))
    secRow:DockMargin(0, s(6), 0, s(6))
    secRow.Paint = nil
    local whenRow
    local secs = k.Choices(secRow, { { 1, "Info" }, { 2, "Plans" }, { 3, "Session" } }, function() return sec end, function(v)
        sec = v
        if IsValid(whenRow) then
            whenRow:SetVisible(sec == 3)
            parent:InvalidateLayout()
        end
    end)
    secs:Dock(LEFT)
    secs:SetWide(s(300))
    local title = k.TextEntry(parent, "Title")
    title:Dock(TOP)
    title:SetText(p and p.title or "")
    title:DockMargin(0, 0, 0, s(6))

    -- Session time, in your own time zone.
    whenRow = vgui.Create("DPanel", parent)
    whenRow:Dock(TOP)
    whenRow:SetTall(s(30))
    whenRow:DockMargin(0, 0, 0, s(6))
    whenRow.Paint = nil
    local at = (p and p.at > 0) and p.at or (os.time() + 86400)
    local date = k.TextEntry(whenRow, "YYYY-MM-DD")
    date:Dock(LEFT)
    date:SetWide(s(140))
    date:SetText(os.date("%Y-%m-%d", at))
    local clock = k.TextEntry(whenRow, "HH:MM")
    clock:Dock(LEFT)
    clock:SetWide(s(90))
    clock:DockMargin(s(6), 0, 0, 0)
    clock:SetText(os.date("%H:%M", at))
    local hint = k.Label(whenRow, "your local time", 12, 400, k.C.textDim)
    hint:Dock(LEFT)
    hint:DockMargin(s(10), s(8), 0, 0)
    hint:SetWide(s(160))
    whenRow:SetVisible(sec == 3)

    local foot = vgui.Create("DPanel", parent)
    foot:Dock(BOTTOM)
    foot:SetTall(s(32))
    foot:DockMargin(0, s(8), 0, 0)
    foot.Paint = nil
    local body = k.TextEntry(parent, "Write here…")
    body:SetMultiline(true)
    body:Dock(FILL)
    body:SetText(p and (boardBodies[p.id] or "") or "")
    local save = k.Button(foot, "Post", function()
        local t = 0
        if sec == 3 then
            local y, mo, d = string.match(date:GetText() or "", "^%s*(%d%d%d%d)%-(%d%d?)%-(%d%d?)%s*$")
            local hh, mm = string.match(clock:GetText() or "", "^%s*(%d%d?):(%d%d)%s*$")
            if not (y and hh) then
                Derma_Message("Write the date as YYYY-MM-DD and the time as HH:MM.", "Session time", "OK")
                return
            end
            t = os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = tonumber(hh), min = tonumber(mm), sec = 0 }) or 0
        end
        send("dp.bsave", function()
            net.WriteUInt(p and p.id or 0, 16)
            net.WriteUInt(sec, 2)
            net.WriteString(string.sub(title:GetText() or "", 1, 400))
            net.WriteString(string.sub(body:GetText() or "", 1, 8000))
            net.WriteUInt(math.max(0, t), 32)
        end)
        editing = nil
    end, { accent = true })
    save:Dock(RIGHT)
    save:SetWide(s(120))
    local cancel = k.Button(foot, "Cancel", function()
        editing = nil
        build()
    end)
    cancel:Dock(RIGHT)
    cancel:SetWide(s(120))
    cancel:DockMargin(0, 0, s(6), 0)
end

local function boardReader(parent)
    local k = K()
    local s = k.S
    local p = boardSel and postById(boardSel)
    if not p then
        label(parent, board.canPost and "Pick a post, or write a new one." or "Pick a post to read it.")
        return
    end
    local h = k.Heading(parent, (p.pin and "★ " or "") .. p.title)
    h:Dock(TOP)
    local by = label(parent, SECTIONS[p.sec] .. "  ·  " .. postSub(p))
    by:DockMargin(0, s(4), 0, s(8))
    if board.canPost then
        local row = vgui.Create("DPanel", parent)
        row:Dock(BOTTOM)
        row:SetTall(s(30))
        row:DockMargin(0, s(8), 0, 0)
        row.Paint = nil
        local function btn(text, fn, opts)
            local b = k.Button(row, text, fn, opts or { small = true })
            b:Dock(LEFT)
            b:SetWide(s(110))
            b:DockMargin(0, 0, s(6), 0)
        end
        btn("Edit", function()
            editing = p.id
            build()
        end)
        btn(p.pin and "Unpin" or "Pin", function() send("dp.bpin", function() net.WriteUInt(p.id, 16) end) end)
        btn("Delete", function()
            send("dp.bdel", function() net.WriteUInt(p.id, 16) end)
            boardSel = nil
        end, { small = true, danger = true })
    end
    local sp = k.Scroll(parent)
    sp:Dock(FILL)
    local body = k.Label(sp, boardBodies[p.id] or "Loading…", 14, 400, k.C.text)
    body:Dock(TOP)
    body:DockMargin(0, 0, s(10), 0)
    if not boardBodies[p.id] then send("dp.bget", function() net.WriteUInt(p.id, 16) end) end
end

local function boardTab(body)
    local k = K()
    local s = k.S
    if not board then
        label(body, "Loading the board…")
        board = { posts = {}, canPost = false, loading = true }
        send("dp.bopen")
        return
    end
    if board.loading then
        label(body, "Loading the board…")
        return
    end
    local left, right = columns(body)
    if board.canPost then
        local new = k.Button(left, "New post", function()
            editing = 0
            build()
        end, { small = true, accent = true })
        new:Dock(TOP)
        new:DockMargin(0, 0, s(8), s(8))
    end
    local sp = k.Scroll(left)
    sp:Dock(FILL)

    -- Group: pinned, upcoming sessions (soonest first), plans, info, archive.
    local now = os.time()
    local groups = { { "Pinned", {} }, { "Upcoming sessions", {} }, { "Plans", {} }, { "Info", {} }, { "Past sessions", {} } }
    for _, p in ipairs(board.posts) do
        local g
        if p.pin then g = 1
        elseif p.sec == 3 then g = p.at > now - 3600 and 2 or 5   -- a session stays "upcoming" for its first hour
        elseif p.sec == 2 then g = 3
        else g = 4 end
        table.insert(groups[g][2], p)
    end
    table.sort(groups[2][2], function(a, b) return a.at < b.at end)
    table.sort(groups[5][2], function(a, b) return a.at > b.at end)
    local any = false
    for _, g in ipairs(groups) do
        if #g[2] > 0 then
            any = true
            local hd = k.Heading(sp, g[1])
            hd:Dock(TOP)
            hd:DockMargin(0, s(4), s(8), s(4))
            for _, p in ipairs(g[2]) do
                listRow(sp, p.title, postSub(p), function() return boardSel == p.id end, function()
                    boardSel = p.id
                    editing = nil
                    build()
                end, p.sec == 3 and "Session" or nil)
            end
        end
    end
    if not any then label(sp, "Nothing posted yet.") end

    if editing then
        editor(right, editing ~= 0 and postById(editing) or nil)
    else
        boardReader(right)
    end
end

--------------------------------------------------------------------------
-- Stats
--------------------------------------------------------------------------

local function statsTab(body)
    local k = K()
    local s = k.S
    local bar = vgui.Create("DPanel", body)
    bar:Dock(TOP)
    bar:SetTall(s(30))
    bar:DockMargin(0, 0, 0, s(10))
    bar.Paint = nil
    local opts = {}
    for i, n in ipairs(PERIOD_NAMES) do opts[i] = { i, n } end
    local ch = k.Choices(bar, opts, function() return statsPeriod end, function(v)
        statsPeriod = v
        statsData = nil
        build()
    end)
    ch:Dock(LEFT)
    ch:SetWide(s(560))

    if not statsData or statsData.period ~= statsPeriod then
        label(body, "Loading…")
        if not (statsData and statsData.pending == statsPeriod) then
            statsData = { pending = statsPeriod }
            send("dp.stats", function() net.WriteUInt(statsPeriod, 3) end)
        end
        return
    end

    -- Totals: one tile per stat.
    local tiles = vgui.Create("DPanel", body)
    tiles:Dock(TOP)
    tiles:SetTall(s(64))
    tiles:DockMargin(0, 0, 0, s(12))
    function tiles:Paint(w, h)
        local n = #STAT_KEYS
        local gap = s(6)
        local tw = (w - gap * (n - 1)) / n
        for i, key in ipairs(STAT_KEYS) do
            local x = (i - 1) * (tw + gap)
            k.Plate(x, 0, tw, h, {})
            draw.SimpleText(statText(key, statsData.totals[key]), k.Font(20, 700), x + tw * 0.5, h * 0.42, k.C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            k.Caps(STAT_NAMES[key], x + tw * 0.5, h * 0.78, k.C.label, TEXT_ALIGN_CENTER)
        end
    end

    -- Members: click a column to sort by it.
    local head = vgui.Create("DPanel", body)
    head:Dock(TOP)
    head:SetTall(s(26))
    head.Paint = nil
    local nameW = s(200)
    local function colX(i, w) return nameW + (i - 1) * ((w - nameW) / #STAT_KEYS) end
    local nameBtn = vgui.Create("DButton", head)
    nameBtn:SetText("")
    nameBtn:SetPos(0, 0)
    nameBtn:SetSize(nameW, s(26))
    nameBtn.Paint = function(_, w, h)
        k.Caps("Member", s(8), h * 0.5, statsSort == "name" and k.C.accent or k.C.label)
        return true
    end
    nameBtn.DoClick = function()
        statsSort = "name"
        build()
    end
    function head:PerformLayout(w, h)
        for i, key in ipairs(STAT_KEYS) do
            local b = self["c" .. i]
            if not IsValid(b) then
                b = vgui.Create("DButton", self)
                b:SetText("")
                b.Paint = function(_, bw, bh)
                    k.Caps(STAT_NAMES[key], bw - s(8), bh * 0.5, statsSort == key and k.C.accent or k.C.label, TEXT_ALIGN_RIGHT)
                    return true
                end
                b.DoClick = function()
                    statsSort = key
                    build()
                end
                self["c" .. i] = b
            end
            local x0, x1 = colX(i, w), colX(i + 1, w)
            b:SetPos(x0, 0)
            b:SetSize(x1 - x0, h)
        end
    end

    local rows = {}
    for _, m in ipairs(statsData.members) do rows[#rows + 1] = m end
    table.sort(rows, function(a, b)
        if statsSort == "name" then return string.lower(a.name) < string.lower(b.name) end
        return (a[statsSort] or 0) > (b[statsSort] or 0)
    end)
    local sp = k.Scroll(body)
    sp:Dock(FILL)
    if #rows == 0 then label(sp, "Nothing recorded for this period yet.") end
    for i, m in ipairs(rows) do
        local r = vgui.Create("DPanel", sp)
        r:Dock(TOP)
        r:SetTall(s(26))
        r:DockMargin(0, 0, s(8), s(2))
        function r:Paint(w, h)
            k.SetCol(i % 2 == 0 and k.C.rowAlt or k.C.row)
            surface.DrawRect(0, 0, w, h)
            draw.SimpleText(k.Fit(m.name, k.Font(13, 600), nameW - s(12)), k.Font(13, 600), s(8), h * 0.5, k.C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            for c, key in ipairs(STAT_KEYS) do
                draw.SimpleText(statText(key, m[key]), k.Font(13), colX(c + 1, w) - s(8), h * 0.5, statsSort == key and k.C.text or k.C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            end
        end
    end
end

--------------------------------------------------------------------------
-- Bans
--------------------------------------------------------------------------

local function bansTab(body)
    local k = K()
    local s = k.S
    local h = k.Heading(body, "Banned from uploading")
    h:Dock(TOP)
    local sp = k.Scroll(body)
    sp:Dock(FILL)
    if #term.bans == 0 then label(sp, "Nobody is banned.") end
    for _, b in ipairs(term.bans) do
        local r = k.Row(sp, b.name, b.sid)
        r:Dock(TOP)
        r:DockMargin(0, 0, s(8), s(3))
        r.right:SetWide(s(110))
        local u = k.Button(r.right, "Unban", function()
            send("dp.tunban", function() net.WriteString(b.sid) end)
        end, { small = true })
        u:Dock(FILL)
    end
end

--------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------

local function tabs()
    local list = { { "logs", term.med and "Records" or "Logs", logsTab } }
    if not term.med then
        list[#list + 1] = { "board", "Board", boardTab }
        list[#list + 1] = { "stats", "Stats", statsTab }
    end
    if term.mod then list[#list + 1] = { "bans", "Bans (" .. #term.bans .. ")", bansTab } end
    return list
end

function build()
    local k = K()
    if not IsValid(panel) or not term then return end
    local s = k.S
    panel.body:Clear()
    local body = panel.body

    -- Top bar: upload, set battalion; tabs on the right.
    local top = vgui.Create("DPanel", body)
    top:Dock(TOP)
    top:SetTall(s(32))
    top:DockMargin(0, 0, 0, s(10))
    top.Paint = nil
    local function topButton(text, fn, opts, side)
        local b = k.Button(top, text, fn, opts)
        b:Dock(side or LEFT)
        surface.SetFont(k.Font(13, 700))
        b:SetWide(surface.GetTextSize(string.upper(text)) + s(34))
        if side == RIGHT then b:DockMargin(s(6), 0, 0, 0) else b:DockMargin(0, 0, s(6), 0) end
        return b
    end
    local n = term.upload
    topButton(n > 0 and ("Upload " .. n .. " note" .. (n == 1 and "" or "s")) or "Nothing to upload", function()
        send("dp.tup")
    end, { accent = true, enabled = n > 0 and not term.banned })
    if term.admin and not term.med then
        topButton("Set battalion", function()
            local m = k.Menu()
            local cats = DarkRP and DarkRP.getCategories and DarkRP.getCategories().jobs or {}
            for _, c in ipairs(cats) do
                if c.name then
                    m:AddOption(c.name, function() send("dp.tset", function() net.WriteString(c.name) end) end)
                end
            end
            m:AddOption("Type a name…", function()
                k.Prompt("Battalion", "The DarkRP job category this computer belongs to", term.bn, function(t)
                    send("dp.tset", function() net.WriteString(t) end)
                end)
            end)
            m:Open()
        end)
    end
    if term.banned then
        local l = k.Label(top, "You're banned from uploading here", 13, 700, k.C.bad)
        l:Dock(LEFT)
        l:DockMargin(s(8), s(8), 0, 0)
        l:SetWide(s(260))
    end

    if not term.med and term.bn == "" then
        label(body, "This computer has no battalion yet. An admin sets it with Set battalion.", k.C.warn, 14)
        return
    end
    if not term.view then
        label(body, term.med and "Medical records are for medics only." or
            ("This is the " .. term.bn .. " battalion's computer. Only its members and military police can read it."), nil, 14)
        return
    end

    local list = tabs()
    local valid = false
    for _, t in ipairs(list) do
        if t[1] == tab then valid = true end
    end
    if not valid then tab = "logs" end
    for i = #list, 1, -1 do
        local t = list[i]
        topButton(t[2], function()
            tab = t[1]
            build()
        end, { selected = function() return tab == t[1] end }, RIGHT)
    end

    for _, t in ipairs(list) do
        if t[1] == tab then t[3](body) end
    end
end

local function open()
    local k = K()
    if not k then return end
    local s = k.S
    if not IsValid(panel) then
        panel = vgui.Create("EditablePanel")
        panel:SetSize(s(1100), s(660))
        panel:Center()
        panel:MakePopup()
        panel:DockPadding(s(14), s(52), s(14), s(14))
        function panel:Paint(w, h)
            if not term then return end
            local title = term.med and "Medical holotable" or (term.bn ~= "" and (term.bn .. " computer") or "Battalion computer")
            k.Plate(0, 0, w, h, { title = title, sub = term.med and "Medical records" or "Battalion", ticks = "all", header = s(38) })
        end
        function panel:Think()
            local r = D.Cfg("useRange") + 20
            if not term or not IsValid(term.ent) or LocalPlayer():GetPos():DistToSqr(term.ent:GetPos()) > r * r then self:Remove() end
        end
        local close = k.Button(panel, "Close", function() panel:Remove() end, { small = true })
        close:Dock(BOTTOM)
        close:DockMargin(0, s(10), 0, 0)
        panel.body = vgui.Create("DPanel", panel)
        panel.body:Dock(FILL)
        panel.body.Paint = nil
        if Rhylib.Menus.RegisterCloser then
            Rhylib.Menus.RegisterCloser("datapad.term", function()
                if IsValid(panel) then panel:Remove() return true end
                return false
            end)
        end
    end
    build()
end

Rhylib.Net.Receive("dp.term", function()
    local t = { entries = {}, bans = {} }
    t.ent = net.ReadEntity()
    t.bn = net.ReadString()
    t.view = net.ReadBool()
    t.mod = net.ReadBool()
    t.admin = net.ReadBool()
    t.banned = net.ReadBool()
    t.upload = net.ReadUInt(8)
    for i = 1, net.ReadUInt(8) do
        t.entries[i] = { id = net.ReadUInt(20), author = net.ReadString(), title = net.ReadString(), pn = net.ReadString(), t = net.ReadUInt(32), mp = net.ReadBool() }
    end
    for i = 1, net.ReadUInt(8) do
        t.bans[i] = { sid = net.ReadString(), name = net.ReadString() }
    end
    if not IsValid(t.ent) then return end
    t.med = t.ent:GetClass() == "rhylib_med_holotable"
    -- A different computer (or newly opened): start fresh.
    if not term or term.ent ~= t.ent or not IsValid(panel) then
        selected, bodies, tab = nil, {}, "logs"
        filter = { q = "", days = 0, mp = false, ids = nil }
        board, boardSel, boardBodies, editing = nil, nil, {}, nil
        statsData = nil
    end
    term = t
    if selected and not entryById(selected) then selected = nil end
    open()
end)

Rhylib.Net.Receive("dp.tbody", function()
    local id = net.ReadUInt(20)
    bodies[id] = net.ReadString()
    if IsValid(panel) and selected == id and tab == "logs" then build() end
end)

Rhylib.Net.Receive("dp.tfound", function()
    local ids = {}
    for _ = 1, net.ReadUInt(8) do ids[net.ReadUInt(20)] = true end
    filter.ids = ids
    if IsValid(panel) and tab == "logs" then build() end
end)

Rhylib.Net.Receive("dp.board", function()
    local ent = net.ReadEntity()
    local b = { canPost = net.ReadBool(), posts = {} }
    for i = 1, net.ReadUInt(8) do
        b.posts[i] = { id = net.ReadUInt(16), sec = net.ReadUInt(2), title = net.ReadString(), author = net.ReadString(),
            t = net.ReadUInt(32), at = net.ReadUInt(32), pin = net.ReadBool() }
    end
    if not term or term.ent ~= ent then return end
    board = b
    boardBodies = {}   -- posts may have been edited
    if boardSel and not postById(boardSel) then boardSel = nil end
    if IsValid(panel) and tab == "board" then build() end
end)

Rhylib.Net.Receive("dp.bbody", function()
    local id = net.ReadUInt(16)
    boardBodies[id] = net.ReadString()
    if IsValid(panel) and tab == "board" and (boardSel == id or editing == id) then build() end
end)

Rhylib.Net.Receive("dp.statsr", function()
    local d = { period = net.ReadUInt(3), totals = {}, members = {} }
    for _, k in ipairs(STAT_KEYS) do d.totals[k] = net.ReadUInt(32) end
    for i = 1, net.ReadUInt(7) do
        local m = { name = net.ReadString() }
        for _, k in ipairs(STAT_KEYS) do m[k] = net.ReadUInt(32) end
        d.members[i] = m
    end
    statsData = d
    if IsValid(panel) and tab == "stats" then build() end
end)
