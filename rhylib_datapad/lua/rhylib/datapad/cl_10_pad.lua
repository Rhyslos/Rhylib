--[[
    Datapad window. Left click with the datapad out opens it.
    Tabs: Notes (everyone), and for MPs Records, Officer logs, Arrest.
]]

local D = Rhylib.Datapad

local function K() return Rhylib.Menus and Rhylib.Menus.Kit end
local function when(t) return t and t > 0 and os.date("%d %b %H:%M", t) or "" end

D.state = D.state or nil
local panel, content
local tab = "notes"
local view = {}          -- what the current tab shows (set by replies)
local wantOpen = false

local function send(name, fn)
    Rhylib.Net.Start(name)
    if fn then fn() end
    net.SendToServer()
end

--------------------------------------------------------------------------
-- Building blocks
--------------------------------------------------------------------------

local function clear()
    if IsValid(content) then content:Clear() end
end

-- A clickable list row: left text, dim right text. reserve: width kept
-- free on the right (for buttons docked into the row).
local function row(parent, left, right, onClick, tag, reserve)
    local k = K()
    local s = k.S
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    b:SetTall(s(34))
    b:Dock(TOP)
    b:DockMargin(0, 0, s(8), s(3))
    function b:Paint(w, h)
        k.SetCol(self:IsHovered() and onClick and k.C.rowHover or k.C.row)
        surface.DrawRect(0, 0, w, h)
        k.SetCol(k.C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        local x = s(12)
        if tag then
            k.Caps(tag, x, h * 0.5, k.C.accent)
            x = x + s(52)
        end
        local rw = reserve or 0
        if right and right ~= "" then
            surface.SetFont(k.Font(12))
            rw = surface.GetTextSize(right) + s(24)
            draw.SimpleText(right, k.Font(12), w - s(12), h * 0.5, k.C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
        draw.SimpleText(k.Fit(left, k.Font(14, 500), w - x - rw - s(12)), k.Font(14, 500), x, h * 0.5, k.C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        return true
    end
    function b:DoClick()
        if not onClick then return end
        surface.PlaySound("ui/buttonclick.wav")
        onClick()
    end
    return b
end

local function bar(parent)
    local k = K()
    local p = vgui.Create("DPanel", parent)
    p:Dock(TOP)
    p:SetTall(k.S(30))
    p:DockMargin(0, 0, 0, k.S(8))
    p.Paint = nil
    return p
end

local function barButton(p, text, fn, opts)
    local k = K()
    local b = k.Button(p, text, fn, opts or { small = true })
    b:Dock(LEFT)
    surface.SetFont(k.Font(12, 700))
    b:SetWide(surface.GetTextSize(string.upper(text)) + k.S(30))
    b:DockMargin(0, 0, k.S(6), 0)
    return b
end

local function heading(text)
    local k = K()
    local h = k.Heading(content, text)
    h:Dock(TOP)
    h:DockMargin(0, 0, 0, k.S(6))
    return h
end

local function label(parent, text, col)
    local k = K()
    local l = k.Label(parent, text, 13, 400, col or k.C.textDim)
    l:Dock(TOP)
    l:DockMargin(0, 0, k.S(8), k.S(6))
    return l
end

-- Read-only text: title, by-line, body.
local function reader(title, by, body, back)
    clear()
    local k = K()
    local b = bar(content)
    barButton(b, "Back", back)
    heading(title)
    label(content, by)
    local sp = k.Scroll(content)
    sp:Dock(FILL)
    local l = k.Label(sp, body ~= "" and body or "(empty)", 14, 400, k.C.text)
    l:Dock(TOP)
    l:DockMargin(0, 0, k.S(10), 0)
end

--------------------------------------------------------------------------
-- Notes
--------------------------------------------------------------------------

local buildTab

-- i = note id (0 = new).
local function editor(i, kind, patient)
    clear()
    local k = K()
    local st = D.state
    local note
    for _, n in ipairs(st.notes) do
        if n.id == i then note = n end
    end
    if i > 0 and not note then buildTab() return end
    view.edit = i
    local b = bar(content)
    barButton(b, "Back", function() view.edit = nil buildTab() end)
    local isMed = (note and note.kind or kind) == D.KIND_MED
    heading(i == 0 and (isMed and "New medical record" or "New log") or "Edit note")
    local pn = note and note.pn or (IsValid(patient) and patient:Nick() or "")
    if isMed then label(content, "Patient: " .. pn .. " · upload at the medical holotable") end

    local title = k.TextEntry(content, "Title")
    title:Dock(TOP)
    title:DockMargin(0, 0, k.S(8), k.S(6))
    title:SetText(note and note.title or "")
    local foot = vgui.Create("DPanel", content)
    foot:Dock(BOTTOM)
    foot:SetTall(k.S(32))
    foot.Paint = nil
    local body = k.TextEntry(content, "Write here…")
    body:SetMultiline(true)
    body:Dock(FILL)
    body:DockMargin(0, 0, k.S(8), k.S(8))
    view.body = body
    if i > 0 then send("dp.get", function() net.WriteUInt(i, 16) end) end
    local save = k.Button(foot, "Save", function()
        send("dp.save", function()
            net.WriteUInt(i, 16)
            net.WriteUInt(isMed and D.KIND_MED or D.KIND_LOG, 1)
            net.WriteString(string.sub(title:GetText() or "", 1, 400))
            net.WriteString(string.sub(body:GetText() or "", 1, 8000))
            net.WriteEntity(IsValid(patient) and patient or NULL)
        end)
        view.edit = nil
    end, { accent = true })
    save:Dock(RIGHT)
    save:SetWide(k.S(120))
    if i > 0 then
        local del = k.Button(foot, "Delete", function()
            send("dp.del", function() net.WriteUInt(i, 16) end)
            view.edit = nil
        end, { danger = true })
        del:Dock(LEFT)
        del:SetWide(k.S(120))
    end
end

local function notesTab()
    local k = K()
    local st = D.state
    local b = bar(content)
    local full = st.limit > 0 and #st.notes >= st.limit
    barButton(b, "New log", function() editor(0, D.KIND_LOG) end,
        { small = true, accent = true, enabled = not full and not st.banned })
    if st.medic then
        barButton(b, "New medical record", function()
            local m = k.Menu()
            for _, p in ipairs(player.GetAll()) do
                m:AddOption(p:Nick(), function() editor(0, D.KIND_MED, p) end)
            end
            m:Open()
        end, { small = true, enabled = not full })
    end
    heading("Notes on this datapad")
    local where = st.bn ~= "" and ("the " .. st.bn .. " computer") or "your battalion computer"
    if st.limit > 0 then
        label(content, string.format("%d / %d notes. When it's full, upload at %s.", #st.notes, st.limit, where),
            full and k.C.warn or nil)
    else
        label(content, "No note limit. Upload logs at " .. where .. (st.medic and ", medical records at the medical holotable." or "."))
    end
    if st.banned then label(content, "You're banned from your battalion's logs.", k.C.bad) end
    local sp = k.Scroll(content)
    sp:Dock(FILL)
    if #st.notes == 0 then label(sp, "Nothing written yet.") end
    for _, n in ipairs(st.notes) do
        local tag = n.kind == D.KIND_MED and "MED" or "LOG"
        row(sp, n.title .. (n.pn ~= "" and ("  ·  " .. n.pn) or ""), when(n.t), function() editor(n.id) end, tag)
    end
end

--------------------------------------------------------------------------
-- MP tabs
--------------------------------------------------------------------------

local function logList(parent, list, back)
    for _, r in ipairs(list) do
        row(parent, r.title .. "  ·  " .. r.author, r.bn .. "  " .. when(r.t), function()
            view.readBack = back
            send("dp.lread", function()
                net.WriteString(r.bn)
                net.WriteUInt(r.id, 20)
            end)
        end)
    end
end

local function recordView()
    clear()
    local k = K()
    local rec = view.record
    local b = bar(content)
    barButton(b, "Back", function() view.record = nil buildTab() end)
    heading(rec.name)
    local sp = k.Scroll(content)
    sp:Dock(FILL)
    local h1 = k.Heading(sp, "Arrests (" .. #rec.jails .. ")")
    h1:Dock(TOP)
    if #rec.jails == 0 then label(sp, "No arrests on file.") end
    for _, j in ipairs(rec.jails) do
        row(sp, j.why ~= "" and j.why or "No reason given", j.min .. " min · by " .. j.by .. "  " .. when(j.t))
    end
    local h2 = k.Heading(sp, "Logs they wrote (" .. #rec.logs .. ")")
    h2:Dock(TOP)
    h2:DockMargin(0, k.S(10), 0, 0)
    if #rec.logs == 0 then label(sp, "No uploaded logs.") end
    logList(sp, rec.logs, recordView)
end

local function recordsTab()
    local k = K()
    if view.record then recordView() return end
    local b = bar(content)
    local q = k.TextEntry(b, "Search by name")
    q:Dock(LEFT)
    q:SetWide(k.S(320))
    q:DockMargin(0, 0, k.S(6), 0)
    q:SetText(view.query or "")
    local function go()
        view.query = q:GetText()
        send("dp.find", function() net.WriteString(string.sub(view.query, 1, 64)) end)
    end
    q.OnEnter = go
    barButton(b, "Search", go, { small = true, accent = true })
    heading("Records")
    local sp = k.Scroll(content)
    sp:Dock(FILL)
    if not view.found then
        label(sp, "Find anyone on file: arrests and the logs they uploaded.")
        return
    end
    if #view.found == 0 then label(sp, "Nobody found.") end
    for _, f in ipairs(view.found) do
        row(sp, f.name, f.arrests .. " arrest" .. (f.arrests == 1 and "" or "s"), function()
            send("dp.rec", function() net.WriteString(f.sid) end)
        end)
    end
end

local function ologsTab()
    local k = K()
    heading("Logs written by MPs")
    local sp = k.Scroll(content)
    sp:Dock(FILL)
    if not view.ologs then
        label(sp, "Loading…")
        send("dp.olog")
        view.ologs = {}
        view.ologsPending = true
        return
    end
    if #view.ologs == 0 and not view.ologsPending then label(sp, "No MP logs uploaded yet.") end
    logList(sp, view.ologs, function() buildTab() end)
end

local function arrestTab()
    local k = K()
    local st = D.state
    local MP = Rhylib.MP
    heading("Cuffed prisoners near you")
    label(content, "Search them, or jail them straight from the datapad.")
    local sp = k.Scroll(content)
    sp:Dock(FILL)
    local any = false
    for _, p in ipairs(st.cuffed) do
        if IsValid(p) then
            any = true
            local r = row(sp, p:Nick(), "", nil, nil, k.S(200))
            local jail = k.Button(r, "Jail", function()
                local minutes = 5
                local f = k.Prompt("Jail " .. p:Nick(), "Reason (sentence is set next)", "", function(why)
                    k.Prompt("Sentence", "Minutes (1-" .. (MP and MP.Cfg("maxSentence") or 60) .. ")", "5", function(m)
                        minutes = math.Clamp(math.floor(tonumber(m) or 5), 1, 127)
                        send("dp.jail", function()
                            net.WriteEntity(p)
                            net.WriteUInt(minutes, 7)
                            net.WriteString(string.sub(why, 1, 120))
                        end)
                    end)
                end)
                return f
            end, { small = true, accent = true })
            jail:Dock(RIGHT)
            jail:SetWide(k.S(90))
            jail:DockMargin(0, k.S(4), k.S(4), k.S(4))
            local search = k.Button(r, "Search", function()
                if MP and MP.OpenSearch then MP.OpenSearch(p) end  -- opens on top of the datapad
            end, { small = true })
            search:Dock(RIGHT)
            search:SetWide(k.S(90))
            search:DockMargin(0, k.S(4), k.S(4), k.S(4))
        end
    end
    if not any then label(sp, "Nobody cuffed nearby. Cuff them first, or escort them here.") end
end

--------------------------------------------------------------------------
-- Battalion: what was last downloaded from the battalion computer
--------------------------------------------------------------------------

D.sync = D.sync or nil      -- { bn, v, at, logs, posts } (kept until you leave)
D.latest = D.latest or {}   -- [battalion] = newest version the server told us about
local dl                    -- a download in progress: { start, dur, data }

local function latestVer()
    local st = D.state
    if not st or st.bn == "" then return 0 end
    return math.max(D.latest[st.bn] or 0, st.ver or 0)
end

local function hasNew()
    local st = D.state
    if not st or st.bn == "" then return false end
    local mine = (D.sync and D.sync.bn == st.bn) and D.sync.v or 0
    return latestVer() > mine
end

local function startDownload()
    if dl or not D.state or D.state.bn == "" then return end
    dl = { start = RealTime(), dur = math.Rand(3, 15) }
    send("dp.dl")
    surface.PlaySound("buttons/button24.wav")
end

local function countdown(at)
    local d = at - os.time()
    if d <= 0 then return "now" end
    if d < 3600 then return "in " .. math.ceil(d / 60) .. " min" end
    if d < 86400 then return string.format("in %d h %d min", math.floor(d / 3600), math.floor(d % 3600 / 60)) end
    return string.format("in %d d %d h", math.floor(d / 86400), math.floor(d % 86400 / 3600))
end

local function battalionTab()
    local k = K()
    local st = D.state
    local sy = D.sync
    if view.read then
        local r = view.read
        reader(r.title, r.by, r.body or "Loading…", function() view.read = nil buildTab() end)
        return
    end
    heading(st.bn .. " computer (downloaded)")
    if not sy or sy.bn ~= st.bn then
        label(content, "Nothing downloaded yet. Press the refresh light at the top right to download the battalion's board and logs. Uploading still happens at the computer.")
        return
    end
    label(content, "Downloaded " .. os.date("%d %b %H:%M", sy.at) .. (hasNew() and "  ·  the computer has newer changes" or "  ·  up to date"),
        hasNew() and k.C.good or nil)
    local sp = k.Scroll(content)
    sp:Dock(FILL)
    local function sub(text)
        local h = k.Heading(sp, text)
        h:Dock(TOP)
        h:DockMargin(0, k.S(6), k.S(8), k.S(4))
    end
    local function open(kind, id, title, by)
        view.read = { kind = kind, id = id, title = title, by = by }
        send("dp.dread", function()
            net.WriteUInt(kind, 1)
            net.WriteUInt(id, 20)
        end)
        buildTab()
    end
    -- Current orders first.
    local o = sy.orders
    if o and o.txt ~= "" then
        sub("Orders")
        local by = label(sp, "From " .. o.by .. " · " .. when(o.t))
        by:DockMargin(0, 0, k.S(8), k.S(4))
        local ot = k.Label(sp, o.txt, 14, 400, k.C.text)
        ot:Dock(TOP)
        ot:DockMargin(0, 0, k.S(8), k.S(6))
    end
    -- Board: pinned, upcoming sessions, plans, info.
    local now = os.time()
    local groups = { { "Pinned", {} }, { "Upcoming sessions", {} }, { "Plans", {} }, { "Info", {} }, { "After-action reports", {} } }
    for _, p in ipairs(sy.posts) do
        local g
        if p.pin then g = 1
        elseif p.sec == 3 then g = p.at > now - 3600 and 2 or nil
        elseif p.sec == 4 then g = 5
        elseif p.sec == 2 then g = 3
        else g = 4 end
        if g then table.insert(groups[g][2], p) end
    end
    table.sort(groups[2][2], function(a, b) return a.at < b.at end)
    for _, g in ipairs(groups) do
        if #g[2] > 0 then
            sub(g[1])
            for _, p in ipairs(g[2]) do
                local right = p.sec == 3 and (when(p.at) .. "  (" .. countdown(p.at) .. ")") or when(p.t)
                local tag = p.sec == 3 and "SES" or (p.sec == 4 and ({ "WIN", "MIX", "FAIL" })[p.oc] or (p.sec == 4 and "AAR")) or nil
                row(sp, p.title, right, function() open(1, p.id, p.title, "By " .. p.author .. " · " .. right) end, tag)
            end
        end
    end
    sub("Logs (" .. #sy.logs .. ")")
    if #sy.logs == 0 then label(sp, "No logs.") end
    for _, e in ipairs(sy.logs) do
        row(sp, e.title .. "  ·  " .. e.author, when(e.t), function() open(0, e.id, e.title, "By " .. e.author .. " · " .. when(e.t)) end, e.mp and "MP" or nil)
    end
end

local TABS = {
    { id = "notes", name = "Notes", build = notesTab },
    { id = "battalion", name = "Battalion", build = battalionTab, bn = true },
    { id = "records", name = "Records", build = recordsTab, mp = true },
    { id = "ologs", name = "Officer logs", build = ologsTab, mp = true },
    { id = "arrest", name = "Arrest", build = arrestTab, mp = true },
}

function buildTab()
    if not IsValid(content) or not D.state then return end
    clear()
    for _, t in ipairs(TABS) do
        if t.id == tab then t.build() return end
    end
end

--------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------

local function openWindow()
    local k = K()
    if not k then return end
    if IsValid(panel) then panel:Remove() end
    local s = k.S
    panel = vgui.Create("EditablePanel")
    panel:SetSize(s(960), s(620))
    panel:Center()
    panel:MakePopup()
    panel:DockPadding(s(14), s(52), s(14), s(14))
    function panel:Paint(w, h)
        local st = D.state
        k.Plate(0, 0, w, h, { title = "Datapad", ticks = "all", header = s(38) })
        local right = w - s(54)
        if dl then
            -- Download progress, left of the refresh light.
            local f = math.Clamp((RealTime() - dl.start) / dl.dur, 0, dl.data and 1 or 0.97)
            local bw = s(200)
            local bx, by = right - bw, s(15)
            k.SetCol(k.C.row)
            surface.DrawRect(bx, by, bw, s(8))
            k.SetCol(k.C.good)
            surface.DrawRect(bx, by, bw * f, s(8))
            draw.SimpleText("Downloading " .. math.floor(f * 100) .. "%", k.Font(11), bx - s(8), by + s(4), k.C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        elseif st and st.bn ~= "" then
            draw.SimpleText(st.bn, k.Font(13), right, s(19), k.C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
    end
    function panel:Think()
        local ply = LocalPlayer()
        if not ply:Alive() or not D.Holding(ply) then self:Remove() return end
        -- Download finished: show it.
        if dl and dl.data and RealTime() - dl.start >= dl.dur then
            D.sync = dl.data
            D.sync.at = os.time()
            dl = nil
            surface.PlaySound("buttons/button14.wav")
            if tab == "battalion" then buildTab() end
        end
    end
    function panel:OnRemove() dl = nil end   -- closing the pad cancels a download

    -- The refresh light: blinks green when the computer has something new.
    local refresh = vgui.Create("DButton", panel)
    refresh:SetText("")
    refresh:SetSize(s(30), s(30))
    refresh:SetPos(s(960) - s(14) - s(30), s(4))
    refresh:SetTooltip("Download from the battalion computer")
    function refresh:Paint(w, h)
        local st = D.state
        if not st or st.bn == "" then return true end
        local cx, cy, r = w * 0.5, h * 0.5, s(9)
        local new = hasNew()
        local col = (dl and k.C.textDim) or (new and k.C.good) or k.C.text
        if new and not dl and math.floor(RealTime() * 2.5) % 2 == 0 then
            surface.SetDrawColor(k.C.good.r, k.C.good.g, k.C.good.b, 60)
            draw.NoTexture()
            surface.DrawRect(0, 0, w, h)
        end
        -- A circular arrow: most of a ring, and an arrowhead at its end.
        surface.SetDrawColor(col)
        local a0 = dl and (RealTime() * 6) or 0.7
        local steps = 14
        for i = 0, steps - 1 do
            local t0 = a0 + (i / steps) * 5.2
            local t1 = a0 + ((i + 1) / steps) * 5.2
            surface.DrawLine(cx + math.cos(t0) * r, cy + math.sin(t0) * r, cx + math.cos(t1) * r, cy + math.sin(t1) * r)
            surface.DrawLine(cx + math.cos(t0) * (r - 1), cy + math.sin(t0) * (r - 1), cx + math.cos(t1) * (r - 1), cy + math.sin(t1) * (r - 1))
        end
        local te = a0 + 5.2
        local ex, ey = cx + math.cos(te) * r, cy + math.sin(te) * r
        local tx, ty = -math.sin(te), math.cos(te)   -- along the ring
        local nx, ny = math.cos(te), math.sin(te)    -- outward
        draw.NoTexture()
        surface.DrawPoly({
            { x = ex + tx * s(5), y = ey + ty * s(5) },
            { x = ex + nx * s(4), y = ey + ny * s(4) },
            { x = ex - nx * s(4), y = ey - ny * s(4) },
        })
        return true
    end
    function refresh:DoClick() startDownload() end
    if Rhylib.Menus.RegisterCloser then
        Rhylib.Menus.RegisterCloser("datapad", function()
            if IsValid(panel) then panel:Remove() return true end
            return false
        end)
    end
    local nav = vgui.Create("DPanel", panel)
    nav:Dock(LEFT)
    nav:SetWide(s(170))
    nav:DockMargin(0, 0, s(14), 0)
    nav.Paint = nil
    local function allowed(t) return (not t.mp or D.state.mp) and (not t.bn or D.state.bn ~= "") end
    for _, t in ipairs(TABS) do
        if allowed(t) then
            local b = k.Button(nav, t.name, function()
                tab = t.id
                view = {}
                buildTab()
            end, { align = "left", selected = function() return tab == t.id end })
            b:Dock(TOP)
            b:DockMargin(0, 0, 0, s(4))
        end
    end
    local close = k.Button(nav, "Close", function() panel:Remove() end, { small = true })
    close:Dock(BOTTOM)
    content = vgui.Create("DPanel", panel)
    content:Dock(FILL)
    content.Paint = nil
    local ok = false
    for _, t in ipairs(TABS) do
        if t.id == tab and allowed(t) then ok = true end
    end
    if not ok then tab = "notes" end
    view = {}
    buildTab()
end

-- Left click with the datapad out.
local nextOpen = 0
Rhylib.Hook.Add("PlayerBindPress", "datapad.open", function(ply, bind, pressed)
    if not pressed or not string.find(bind, "+attack", 1, true) or string.find(bind, "+attack2", 1, true) then return end
    if not D.Holding(ply) or vgui.CursorVisible() then return end
    if CurTime() >= nextOpen then
        nextOpen = CurTime() + 0.5
        wantOpen = true
        send("dp.open")
    end
    return true
end)

--------------------------------------------------------------------------
-- Replies
--------------------------------------------------------------------------

Rhylib.Net.Receive("dp.state", function()
    local st = { notes = {}, cuffed = {} }
    st.bn = net.ReadString()
    st.mp = net.ReadBool()
    st.medic = net.ReadBool()
    st.banned = net.ReadBool()
    st.limit = net.ReadUInt(8)
    st.ver = net.ReadUInt(32)
    for i = 1, net.ReadUInt(8) do
        st.notes[i] = { id = net.ReadUInt(16), kind = net.ReadUInt(1), title = net.ReadString(), pn = net.ReadString(), t = net.ReadUInt(32) }
    end
    for i = 1, net.ReadUInt(4) do st.cuffed[i] = net.ReadEntity() end
    D.state = st
    if wantOpen then
        wantOpen = false
        openWindow()
    elseif IsValid(panel) and not view.edit then
        buildTab()
    end
end)

Rhylib.Net.Receive("dp.body", function()
    local i = net.ReadUInt(16)
    local body = net.ReadString()
    if view.edit == i and IsValid(view.body) then view.body:SetText(body) end
end)

Rhylib.Net.Receive("dp.found", function()
    local list = {}
    for i = 1, net.ReadUInt(5) do
        list[i] = { sid = net.ReadString(), name = net.ReadString(), arrests = net.ReadUInt(8) }
    end
    view.found = list
    if IsValid(panel) and tab == "records" then buildTab() end
end)

local function readLogs()
    local out = {}
    for i = 1, net.ReadUInt(7) do
        out[i] = { bn = net.ReadString(), id = net.ReadUInt(20), author = net.ReadString(), title = net.ReadString(), t = net.ReadUInt(32) }
    end
    return out
end

Rhylib.Net.Receive("dp.record", function()
    local rec = { sid = net.ReadString(), name = net.ReadString(), jails = {} }
    for i = 1, net.ReadUInt(6) do
        rec.jails[i] = { t = net.ReadUInt(32), by = net.ReadString(), min = net.ReadUInt(10), why = net.ReadString() }
    end
    rec.logs = readLogs()
    view.record = rec
    if IsValid(panel) and tab == "records" then recordView() end
end)

Rhylib.Net.Receive("dp.ologs", function()
    view.ologs = readLogs()
    view.ologsPending = nil
    if IsValid(panel) and tab == "ologs" then buildTab() end
end)

Rhylib.Net.Receive("dp.lbody", function()
    local author, title, t, body = net.ReadString(), net.ReadString(), net.ReadUInt(32), net.ReadString()
    if not IsValid(panel) then return end
    local back = view.readBack or buildTab
    reader(title, "By " .. author .. " · " .. when(t), body, back)
end)

Rhylib.Net.Receive("dp.ver", function()
    local bn, v = net.ReadString(), net.ReadUInt(32)
    D.latest[bn] = v
end)

Rhylib.Net.Receive("dp.dldata", function()
    local d = { logs = {}, posts = {} }
    d.bn = net.ReadString()
    d.v = net.ReadUInt(32)
    for i = 1, net.ReadUInt(8) do
        d.logs[i] = { id = net.ReadUInt(20), author = net.ReadString(), title = net.ReadString(), t = net.ReadUInt(32), mp = net.ReadBool() }
    end
    for i = 1, net.ReadUInt(7) do
        d.posts[i] = { id = net.ReadUInt(16), sec = net.ReadUInt(3), title = net.ReadString(), author = net.ReadString(),
            t = net.ReadUInt(32), at = net.ReadUInt(32), pin = net.ReadBool(), oc = net.ReadUInt(2) }
    end
    d.orders = { txt = net.ReadString(), by = net.ReadString(), t = net.ReadUInt(32) }
    D.latest[d.bn] = math.max(D.latest[d.bn] or 0, d.v)
    if dl then dl.data = d end   -- shown when the progress bar is done
end)

Rhylib.Net.Receive("dp.dbody", function()
    local kind, id, body = net.ReadUInt(1), net.ReadUInt(20), net.ReadString()
    local r = view.read
    if r and r.kind == kind and r.id == id then
        r.body = body ~= "" and body or "(empty)"
        if IsValid(panel) and tab == "battalion" then buildTab() end
    end
end)
