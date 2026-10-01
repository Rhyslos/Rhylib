--[[
    Battalion computer / medical holotable window: upload your notes, read
    the entries; moderators delete entries and manage the ban list; admins
    set a computer's battalion.
]]

local D = Rhylib.Datapad

local function K() return Rhylib.Menus and Rhylib.Menus.Kit end
local function when(t) return t and t > 0 and os.date("%d %b %Y %H:%M", t) or "" end

local panel
local term          -- last dp.term
local selected      -- selected entry id
local showBans = false
local bodies = {}   -- [id] = text

local function send(name, fn)
    Rhylib.Net.Start(name)
    net.WriteEntity(term.ent)
    if fn then fn() end
    net.SendToServer()
end

local build

local function entryById(id)
    for _, e in ipairs(term.entries) do
        if e.id == id then return e end
    end
end

local function readerPanel(parent)
    local k = K()
    local s = k.S
    local e = selected and entryById(selected)
    if not e then
        local l = k.Label(parent, term.view and "Pick an entry to read it." or "", 13, 400, k.C.textDim)
        l:Dock(TOP)
        return
    end
    local h = k.Heading(parent, e.title)
    h:Dock(TOP)
    local by = k.Label(parent, "By " .. e.author .. (e.pn ~= "" and (" · patient " .. e.pn) or "") .. " · " .. when(e.t), 13, 400, k.C.textDim)
    by:Dock(TOP)
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

local function banList(parent)
    local k = K()
    local s = k.S
    local h = k.Heading(parent, "Banned from uploading")
    h:Dock(TOP)
    local sp = k.Scroll(parent)
    sp:Dock(FILL)
    if #term.bans == 0 then
        local l = k.Label(sp, "Nobody is banned.", 13, 400, k.C.textDim)
        l:Dock(TOP)
    end
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

function build()
    local k = K()
    if not IsValid(panel) or not term then return end
    local s = k.S
    panel.body:Clear()
    local body = panel.body

    -- Top bar.
    local top = vgui.Create("DPanel", body)
    top:Dock(TOP)
    top:SetTall(s(32))
    top:DockMargin(0, 0, 0, s(10))
    top.Paint = nil
    local function topButton(text, fn, opts)
        local b = k.Button(top, text, fn, opts)
        b:Dock(LEFT)
        surface.SetFont(k.Font(13, 700))
        b:SetWide(surface.GetTextSize(string.upper(text)) + s(34))
        b:DockMargin(0, 0, s(6), 0)
        return b
    end
    local n = term.upload
    topButton(n > 0 and ("Upload " .. n .. " note" .. (n == 1 and "" or "s")) or "Nothing to upload", function()
        send("dp.tup")
    end, { accent = true, enabled = n > 0 and not term.banned })
    if term.mod then
        topButton(showBans and "Show entries" or ("Ban list (" .. #term.bans .. ")"), function()
            showBans = not showBans
            build()
        end)
    end
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
        l:SetWide(s(300))
    end

    if not term.med and term.bn == "" then
        local l = k.Label(body, "This computer has no battalion yet. An admin sets it with Set battalion.", 14, 400, k.C.warn)
        l:Dock(TOP)
        return
    end
    if not term.view then
        local l = k.Label(body, term.med and "Medical records are for medics only." or
            ("This is the " .. term.bn .. " battalion's computer. Only its members and military police can read it."), 14, 400, k.C.textDim)
        l:Dock(TOP)
        return
    end
    if showBans and term.mod then
        banList(body)
        return
    end

    -- Entries on the left, the reader on the right.
    local left = vgui.Create("DPanel", body)
    left:Dock(LEFT)
    left:SetWide(s(420))
    left.Paint = nil
    local h = k.Heading(left, (term.med and "Medical records" or "Logs") .. " (" .. #term.entries .. ")")
    h:Dock(TOP)
    local sp = k.Scroll(left)
    sp:Dock(FILL)
    if #term.entries == 0 then
        local l = k.Label(sp, "Nothing uploaded yet.", 13, 400, k.C.textDim)
        l:Dock(TOP)
    end
    for _, e in ipairs(term.entries) do
        local b = k.Button(sp, "", function()
            selected = e.id
            build()
        end, { small = true, align = "left", selected = function() return selected == e.id end })
        b:SetTall(s(44))
        b:Dock(TOP)
        b:DockMargin(0, 0, s(8), s(3))
        local sub = e.author .. (e.pn ~= "" and (" → " .. e.pn) or "") .. "  ·  " .. when(e.t)
        local paint = b.Paint
        -- Title on top, author and date under it.
        function b:Paint(w, hh)
            paint(self, w, hh)
            draw.SimpleText(k.Fit(e.title, k.Font(14, 600), w - s(26)), k.Font(14, 600), s(14), s(6), k.C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            draw.SimpleText(k.Fit(sub, k.Font(11), w - s(26)), k.Font(11), s(14), hh - s(6), k.C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
            return true
        end
    end
    local right = vgui.Create("DPanel", body)
    right:Dock(FILL)
    right:DockMargin(s(16), 0, 0, 0)
    right.Paint = nil
    readerPanel(right)
end

local function open()
    local k = K()
    if not k then return end
    local s = k.S
    if not IsValid(panel) then
        panel = vgui.Create("EditablePanel")
        panel:SetSize(s(1000), s(620))
        panel:Center()
        panel:MakePopup()
        panel:DockPadding(s(14), s(52), s(14), s(14))
        function panel:Paint(w, h)
            if not term then return end
            local title = term.med and "Medical holotable" or (term.bn ~= "" and (term.bn .. " computer") or "Battalion computer")
            k.Plate(0, 0, w, h, { title = title, sub = term.med and "Medical records" or "Battalion logs", ticks = "all", header = s(38) })
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
        t.entries[i] = { id = net.ReadUInt(20), author = net.ReadString(), title = net.ReadString(), pn = net.ReadString(), t = net.ReadUInt(32) }
    end
    for i = 1, net.ReadUInt(8) do
        t.bans[i] = { sid = net.ReadString(), name = net.ReadString() }
    end
    if not IsValid(t.ent) then return end
    t.med = t.ent:GetClass() == "rhylib_med_holotable"
    -- A different computer: start fresh.
    if not term or term.ent ~= t.ent then
        selected, showBans, bodies = nil, false, {}
    end
    term = t
    if selected and not entryById(selected) then selected = nil end
    open()
end)

Rhylib.Net.Receive("dp.tbody", function()
    local id = net.ReadUInt(20)
    bodies[id] = net.ReadString()
    if IsValid(panel) and selected == id then build() end
end)
