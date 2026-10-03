--[[
    Skills page in the pause menu (rhylib_menus). One tab per category;
    the tree is drawn tier by tier, top to bottom: shared skills across the
    full width, each specialisation in its own column, and end branches
    side by side inside it. Click a skill to learn it (skills.learn);
    "Reset" clears everything (skills.reset). Learned = accent, can learn
    now = bright, locked = dim, with the reason on hover.
]]

local K = Rhylib.Skills

Rhylib.Net.Receive("skills.note", function()
    local bad = net.ReadBool()
    local text = net.ReadString()
    chat.AddText(bad and Color(235, 90, 80) or Color(133, 183, 235), "[Skills] ", Color(225, 225, 225), text)
    surface.PlaySound(bad and "buttons/button10.wav" or "buttons/button14.wav")
end)

local function learn(n)
    Rhylib.Net.Start("skills.learn")
    net.WriteUInt(n.index, 8)
    net.SendToServer()
end

-- Columns of a category: { x0, x1 } shares of the width for shared nodes,
-- each spec and each of its branches.
local function columns(cat)
    local specs = cat.specs or {}
    local cols = { shared = { 0, 1 }, spec = {}, branch = {} }
    local n = #specs
    for i, s in ipairs(specs) do
        local a, b = (i - 1) / math.max(n, 1), i / math.max(n, 1)
        cols.spec[s.id] = { a, b }
        local br = s.branches or {}
        for j, x in ipairs(br) do
            cols.branch[x.id] = { a + (b - a) * (j - 1) / #br, a + (b - a) * j / #br }
        end
    end
    return cols
end

local function build(page)
    local Menus = Rhylib.Menus
    local Kit = Menus.Kit
    local C, S = Kit.C, Kit.S
    local me = LocalPlayer()

    local cur = K.CATEGORIES[1].id
    for c in pairs(K.Commitments(K.Set(me))) do cur = c end

    -- Top bar: category tabs, points, reset.
    local bar = vgui.Create("DPanel", page)
    bar:Dock(TOP)
    bar:SetTall(S(30))
    bar:DockMargin(0, 0, 0, S(10))
    bar.Paint = nil
    local reset = Kit.Button(bar, "Reset skills", function()
        Rhylib.Net.Start("skills.reset")
        net.SendToServer()
    end, { small = true, danger = true })
    reset:Dock(RIGHT)
    reset:SetWide(S(130))
    local pts = vgui.Create("DPanel", bar)
    pts:Dock(RIGHT)
    pts:SetWide(S(260))
    pts:DockMargin(0, 0, S(10), 0)
    function pts:Paint(w, h)
        local set = K.Set(me)
        local spent = K.Spent(set)
        local text = K.Cfg("freePoints") and ("Spent " .. spent .. " points  ·  free (testing)")
            or ("Points: " .. (K.Points(me) - spent) .. " left of " .. K.Points(me))
        draw.SimpleText(text, Kit.Font(13, 700), w, h * 0.5, C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    local tree = vgui.Create("DPanel", page)
    tree:Dock(FILL)
    local info = vgui.Create("DPanel", page)
    info:Dock(BOTTOM)
    info:SetTall(S(64))
    info:DockMargin(0, S(10), 0, 0)
    local hovered

    function info:Paint(w, h)
        local hp = vgui.GetHoveredPanel()
        if not (IsValid(hp) and hp.node) then hovered = nil end
        Kit.SetCol(C.row)
        surface.DrawRect(0, 0, w, h)
        Kit.SetCol(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        local n = hovered
        if not n then
            draw.SimpleText("Hover a skill to read it. Click to learn. One path, one specialisation and one end branch.",
                Kit.Font(13), S(12), h * 0.5, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            return
        end
        local set = K.Set(me)
        local ok, why = K.CanLearn(me, set, n.id)
        local state = set[n.id] and "Learned" or (ok and "Click to learn" or why)
        draw.SimpleText(n.name .. "  ·  " .. n.cost .. " pt" .. (n.cost == 1 and "" or "s"), Kit.Font(15, 700), S(12), S(18), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(state, Kit.Font(12, 700), w - S(12), S(18), set[n.id] and C.accent or (ok and C.good or C.warn), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        draw.SimpleText(n.desc, Kit.Font(13), S(12), S(44), C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local function fill()
        tree:Clear()
        hovered = nil
        local cat = K.catById[cur]
        local cols = columns(cat)
        local nodes, maxTier = {}, 1
        for _, n in ipairs(K.NODES) do
            if n.cat == cur then
                nodes[#nodes + 1] = n
                maxTier = math.max(maxTier, n.tier)
            end
        end
        local headH = S(46)

        function tree:Paint(w, h)
            Kit.SetCol(C.row)
            surface.DrawRect(0, 0, w, h)
            Kit.SetCol(C.edgeDark)
            surface.DrawOutlinedRect(0, 0, w, h)
            draw.SimpleText(string.upper(cat.name), Kit.Font(15, 700), S(12), S(14), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(cat.desc or "", Kit.Font(12), S(12), S(32), C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            -- Spec headings and dividers.
            local inner = w - S(24)
            for _, s in ipairs(cat.specs or {}) do
                local c = cols.spec[s.id]
                local x = S(12) + inner * c[1]
                if c[1] > 0 then
                    Kit.SetCol(C.edgeLight)
                    surface.DrawRect(x - S(6), headH, 1, h - headH - S(8))
                end
                draw.SimpleText(string.upper(s.name), Kit.Font(13, 700), x + inner * (c[2] - c[1]) * 0.5, headH + S(4), C.accent, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
            end
            -- End branch names, over the first row of each branch.
            if self.rowH then
                for _, s in ipairs(cat.specs or {}) do
                    for _, br in ipairs(s.branches or {}) do
                        local tier
                        for _, n in ipairs(nodes) do
                            if n.branch == br.id and (not tier or n.tier < tier) then tier = n.tier end
                        end
                        local c = cols.branch[br.id]
                        if tier and c then
                            draw.SimpleText(string.upper(br.name), Kit.Font(11, 700), S(12) + inner * (c[1] + c[2]) * 0.5,
                                self.rowTop + (tier - 1) * self.rowH - S(8), C.warn, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                        end
                    end
                end
            end
            -- Lines from each node to what it needs.
            Kit.SetCol(C.edgeLight)
            for _, b in ipairs(self:GetChildren()) do
                local n = b.node
                if n then
                    local reqs = {}
                    for _, r in ipairs(n.needs or {}) do reqs[#reqs + 1] = r end
                    for _, g in ipairs(n.needsGroups or {}) do for _, r in ipairs(g) do reqs[#reqs + 1] = r end end
                    for _, r in ipairs(reqs) do
                        local o = self.byNode and self.byNode[r]
                        if IsValid(o) then
                            local ax, ay = o:GetX() + o:GetWide() * 0.5, o:GetY() + o:GetTall()
                            local bx, by = b:GetX() + b:GetWide() * 0.5, b:GetY()
                            surface.DrawLine(ax, ay, bx, by)
                        end
                    end
                end
            end
        end

        tree.byNode = {}
        for _, n in ipairs(nodes) do
            local b = vgui.Create("DButton", tree)
            b:SetText("")
            b.node = n
            tree.byNode[n.id] = b
            function b:Paint(w, h)
                local set = K.Set(me)
                local has = set[n.id]
                local ok = not has and K.CanLearn(me, set, n.id)
                local bg = has and C.buttonDown or (self:IsHovered() and C.buttonHover or C.button)
                Kit.SetCol(bg)
                surface.DrawRect(0, 0, w, h)
                Kit.SetCol(has and C.accent or (ok and C.good or C.edgeDark), (has or ok) and 255 or 200)
                surface.DrawOutlinedRect(0, 0, w, h, has and 2 or 1)
                local col = (has or ok) and C.text or C.textDim
                draw.SimpleText(Kit.Fit(n.name, Kit.Font(13, 700), w - S(34)), Kit.Font(13, 700), S(8), h * 0.5, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText(has and "✓" or tostring(n.cost), Kit.Font(12, 700), w - S(8), h * 0.5, has and C.accent or C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                if self:IsHovered() then hovered = n end
                return true
            end
            function b:DoClick()
                local set = K.Set(me)
                if set[n.id] then return end
                local ok, why = K.CanLearn(me, set, n.id)
                if not ok then
                    surface.PlaySound("buttons/button10.wav")
                    chat.AddText(Color(235, 90, 80), "[Skills] ", Color(225, 225, 225), why)
                    return
                end
                learn(n)
            end
        end

        -- Place the nodes: tier rows; shared ones across the middle.
        function tree:PerformLayout(w, h)
            local inner = w - S(24)
            local top = headH + S(26)
            local rowH = math.min(S(56), math.floor((h - top - S(10)) / maxTier))
            local bh = math.min(S(34), rowH - S(10))
            local bw = math.min(S(220), inner * 0.3)
            self.rowTop, self.rowH = top, rowH
            -- Nodes sharing a tier and a column sit side by side.
            local groups = {}
            for _, n in ipairs(nodes) do
                local col = n.branch and cols.branch[n.branch] or (n.spec and cols.spec[n.spec]) or cols.shared
                local key = n.tier .. "|" .. col[1] .. "|" .. col[2]
                groups[key] = groups[key] or { col = col, list = {} }
                table.insert(groups[key].list, n)
            end
            for _, g in pairs(groups) do
                local x0, x1 = S(12) + inner * g.col[1], S(12) + inner * g.col[2]
                local cnt = #g.list
                local each = math.min(bw, (x1 - x0 - S(8) * (cnt + 1)) / cnt)
                local total = each * cnt + S(8) * (cnt - 1)
                local x = x0 + (x1 - x0 - total) * 0.5
                for _, n in ipairs(g.list) do
                    local b = self.byNode[n.id]
                    b:SetPos(math.floor(x), math.floor(top + (n.tier - 1) * rowH))
                    b:SetSize(math.floor(each), bh)
                    x = x + each + S(8)
                end
            end
        end
        tree:InvalidateLayout(true)
    end

    for _, c in ipairs(K.CATEGORIES) do
        local b = Kit.Button(bar, c.name, function()
            cur = c.id
            fill()
        end, { small = true, selected = function() return cur == c.id end })
        b:Dock(LEFT)
        b:SetWide(S(130))
        b:DockMargin(0, 0, S(6), 0)
    end
    fill()
end

local function addPage()
    local Menus = Rhylib.Menus
    if not (Menus and Menus.AddPage and Menus.Kit) then return end
    Menus.AddPage("skills", {
        title = "Skills",
        order = 7,
        build = build,
    })
end
addPage()
Rhylib.Hook.Add("InitPostEntity", "skills.page", addPage)
