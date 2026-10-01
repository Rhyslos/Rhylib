--[[
    Commands page (admins). Two halves:
      Players: pick a player, then an action. Actions run the admin mod's
               own commands (ULX or SAM, whichever is installed), which
               check your rights on the server.
      Server:  Rhylib's console commands, which check rights themselves.
    Add more with:
        Rhylib.Menus.AddCommand("Server", {
            id = "x", title = "Do X", desc = "...", order = 50,
            run = function() RunConsoleCommand("x") end,
            -- or choices = { { "arg", "Label" }, ... }, run = function(arg) end
        })
]]

local Menus = Rhylib.Menus
local K = Menus.Kit
local C = K.C

--------------------------------------------------------------------------
-- Admin mods
--------------------------------------------------------------------------

local MODS = {
    { id = "ulx", name = "ULX",
      detect = function() return ulx ~= nil and ULib ~= nil end,
      target = function(p) return "$" .. p:SteamID() end,
      run = function(...) RunConsoleCommand("ulx", ...) end },
    { id = "sam", name = "SAM",
      detect = function() return sam ~= nil end,
      target = function(p) return p:SteamID() end,
      run = function(...) RunConsoleCommand("sam", ...) end },
}

function Menus.AdminMod()
    for _, m in ipairs(MODS) do
        if m.detect() then return m end
    end
end

-- Player actions. verb: the command (same name in ULX and SAM).
-- ask: prompts before running; the answers are added as arguments.
local ACTIONS = {
    { "Go to", "goto" }, { "Bring", "bring" }, { "Return", "return" },
    { "Spectate", "spectate" },
    { "Freeze", "freeze" }, { "Unfreeze", "unfreeze" },
    { "Jail", "jail" }, { "Unjail", "unjail" },
    { "God", "god" }, { "Ungod", "ungod" },
    { "Noclip", "noclip" }, { "Strip weapons", "strip" },
    { "Slay", "slay", danger = true },
    { "Mute chat", "mute" }, { "Unmute chat", "unmute" },
    { "Gag voice", "gag" }, { "Ungag voice", "ungag" },
    { "Kick", "kick", danger = true, ask = { { "Kick", "Reason", "" } } },
    { "Ban", "ban", danger = true, ask = { { "Ban", "Length in minutes (0 = forever)", "60" }, { "Ban", "Reason", "" } } },
}

-- Asks each question in turn, then calls done(answers).
local function askAll(questions, i, answers, done)
    local q = questions[i]
    if not q then done(answers) return end
    K.Prompt(q[1], q[2], q[3], function(text)
        answers[#answers + 1] = text
        askAll(questions, i + 1, answers, done)
    end)
end

local function runAction(mod, act, ply)
    if not IsValid(ply) then return end
    local target = mod.target(ply)
    if act.ask then
        askAll(act.ask, 1, {}, function(answers)
            if not IsValid(ply) then return end
            mod.run(act[2], target, unpack(answers))
        end)
    else
        mod.run(act[2], target)
    end
end
Menus.RunPlayerAction = function(verb, ply)
    local mod = Menus.AdminMod()
    if not mod then return end
    for _, act in ipairs(ACTIONS) do
        if act[2] == verb then runAction(mod, act, ply) return end
    end
end

--------------------------------------------------------------------------
-- Server commands
--------------------------------------------------------------------------

Menus.commands = Menus.commands or {}
function Menus.AddCommand(group, cmd)
    local list = Menus.commands[group]
    if not list then
        list = {}
        Menus.commands[group] = list
    end
    for i, c in ipairs(list) do
        if c.id == cmd.id then list[i] = cmd return end
    end
    list[#list + 1] = cmd
end

Menus.AddCommand("Server", {
    id = "hud.layout", order = 10,
    title = "Default first-person HUD", desc = "For players who haven't picked their own",
    choices = { { "f5", "F5" }, { "f4", "F4" }, { "console", "Console" }, { "thirdperson", "3rd person" } },
    current = function() return Rhylib.HUD and Rhylib.HUD.ServerLayout and Rhylib.HUD.ServerLayout() end,
    run = function(arg) RunConsoleCommand("rhylib_hud_layout", arg) end,
})
Menus.AddCommand("Server", {
    id = "armoury.save", order = 20,
    title = "Save armoury placements", desc = "Armouries, cabinets, lockers and crates on this map",
    run = function() RunConsoleCommand("rhylib_armoury_save") end,
})
Menus.AddCommand("Server", {
    id = "crate.refill", order = 30,
    title = "Refill supply crates", desc = "The crate you're looking at, or all of them",
    choices = { { "", "Looked at" }, { "all", "All" } },
    run = function(arg) if arg == "" then RunConsoleCommand("rhylib_crate_refill") else RunConsoleCommand("rhylib_crate_refill", arg) end end,
})
Menus.AddCommand("Server", {
    id = "locker.unclaim", order = 40,
    title = "Unclaim locker", desc = "The locker you're looking at (the owner keeps their items)",
    run = function() RunConsoleCommand("rhylib_locker_unclaim") end,
})
Menus.AddCommand("Server", {
    id = "jetpack.give", order = 50,
    title = "Give yourself a jetpack",
    run = function() RunConsoleCommand("rhylib_jetpack_give") end,
})
Menus.AddCommand("Server", {
    id = "clean.hotbar", order = 60,
    title = "Clean your hotbar", desc = "Remove held weapons that aren't in your inventory",
    run = function() RunConsoleCommand("rhylib_cleanhotbar") end,
})
Menus.AddCommand("Server", {
    id = "status", order = 70,
    title = "Rhylib status / profiler report", desc = "Superadmin; the report prints in the console",
    choices = { { "status", "Status" }, { "report", "Report" }, { "reset", "Reset" } },
    run = function(arg)
        if arg == "status" then RunConsoleCommand("rhylib_status")
        elseif arg == "report" then RunConsoleCommand("rhylib_profile_report")
        else RunConsoleCommand("rhylib_profile_reset") end
    end,
})

--------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------

local function isStaff()
    local ply = LocalPlayer()
    if not IsValid(ply) then return false end
    if ply:IsAdmin() then return true end
    if ULib and ULib.ucl and ULib.ucl.query then return ULib.ucl.query(ply, "ulx kick") and true or false end
    if sam and ply.HasPermission then return ply:HasPermission("kick") and true or false end
    return false
end
Menus.IsStaff = isStaff

local function buildPlayers(parent)
    local s = K.S
    local mod = Menus.AdminMod()
    local box = vgui.Create("DPanel", parent)
    box.Paint = nil

    local left = vgui.Create("DPanel", box)
    left:Dock(LEFT)
    left:SetWide(s(280))
    left.Paint = nil
    local search = K.TextEntry(left, "Search players")
    search:Dock(TOP)
    search:DockMargin(0, 0, 0, s(6))
    local list = K.Scroll(left)
    list:Dock(FILL)

    local right = vgui.Create("DPanel", box)
    right:Dock(FILL)
    right:DockMargin(s(12), 0, 0, 0)
    right:DockPadding(s(12), s(12), s(12), s(12))
    function right:Paint(w, h)
        K.SetCol(C.row)
        surface.DrawRect(0, 0, w, h)
        K.SetCol(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        local p = box.selected
        if not mod then
            draw.SimpleText("No admin mod found (ULX or SAM).", K.Font(14), w * 0.5, h * 0.5, C.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        elseif not IsValid(p) then
            draw.SimpleText("Pick a player on the left.", K.Font(14), w * 0.5, h * 0.5, C.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end

    local info = vgui.Create("DPanel", right)
    info:Dock(TOP)
    info:SetTall(s(54))
    function info:Paint(w, h)
        local p = box.selected
        if not IsValid(p) then return end
        draw.SimpleText(p:Nick(), K.Font(18, 700), 0, s(14), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(p:SteamID() .. "  ·  " .. p:GetUserGroup() .. "  ·  " .. team.GetName(p:Team()) .. "  ·  " .. p:Ping() .. " ms",
            K.Font(12), 0, s(36), C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local grid = vgui.Create("DIconLayout", right)
    grid:Dock(FILL)
    grid:SetSpaceX(s(6))
    grid:SetSpaceY(s(6))
    grid:SetVisible(false)
    local function fillGrid()
        grid:Clear()
        if not mod then return end
        local extra = {
            { "Copy SteamID", function(p) SetClipboardText(p:SteamID()) end },
            { "Steam profile", function(p) p:ShowProfile() end },
        }
        for _, act in ipairs(ACTIONS) do
            local b = K.Button(grid, act[1], function() runAction(mod, act, box.selected) end, { small = true, danger = act.danger })
            b:SetSize(s(150), s(30))
        end
        for _, e in ipairs(extra) do
            local b = K.Button(grid, e[1], function() if IsValid(box.selected) then e[2](box.selected) end end, { small = true })
            b:SetSize(s(150), s(30))
        end
    end
    fillGrid()

    local function rebuild()
        list:Clear()
        local q = string.lower(search:GetText() or "")
        local players = player.GetAll()
        table.sort(players, function(a, b) return string.lower(a:Nick()) < string.lower(b:Nick()) end)
        for _, p in ipairs(players) do
            if q == "" or string.find(string.lower(p:Nick()), q, 1, true) or string.find(string.lower(p:SteamID()), q, 1, true) then
                local b = vgui.Create("DButton", list)
                b:SetText("")
                b:Dock(TOP)
                b:SetTall(s(34))
                b:DockMargin(0, 0, s(8), s(2))
                local av = vgui.Create("AvatarImage", b)
                av:SetSize(s(26), s(26))
                av:SetPos(s(4), s(4))
                av:SetPlayer(p, 32)
                av:SetMouseInputEnabled(false)
                function b:Paint(w, h)
                    local sel = box.selected == p
                    K.SetCol(sel and C.buttonDown or (self:IsHovered() and C.rowHover or C.row))
                    surface.DrawRect(0, 0, w, h)
                    if not IsValid(p) then return true end
                    K.SetCol(team.GetColor(p:Team()))
                    surface.DrawRect(w - 3, 0, 3, h)
                    draw.SimpleText(K.Fit(p:Nick(), K.Font(13, 500), w - s(46)), K.Font(13, 500), s(38), h * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                    return true
                end
                function b:DoClick()
                    box.selected = p
                    grid:SetVisible(mod ~= nil)
                end
            end
        end
    end
    search.OnChange = rebuild
    rebuild()
    box.rebuild = rebuild
    return box
end

-- Rows straight into a scroll panel.
local function buildServer(sp)
    local groups = {}
    for g in pairs(Menus.commands) do groups[#groups + 1] = g end
    table.sort(groups)
    for _, g in ipairs(groups) do
        local list = table.Copy(Menus.commands[g])
        table.sort(list, function(a, b) return (a.order or 50) < (b.order or 50) end)
        for _, cmd in ipairs(list) do
            local row = K.Row(sp, cmd.title, cmd.desc)
            row:Dock(TOP)
            row:DockMargin(0, 0, K.S(10), K.S(4))
            if cmd.choices then
                row.right:SetWide(K.S(420))
                local cur = cmd.current or function() return nil end
                local c = K.Choices(row.right, cmd.choices, function() return cur() end, function(v) cmd.run(v) end)
                c:Dock(FILL)
            else
                local b = K.Button(row.right, "Run", function() cmd.run() end, { small = true, accent = true })
                b:Dock(RIGHT)
                b:SetWide(K.S(90))
            end
        end
    end
end

Menus.AddPage("commands", {
    title = "Commands",
    order = 20,
    visible = isStaff,
    build = function(page)
        local mod = Menus.AdminMod()
        Menus.pages.commands.sub = mod and ("Admin mod: " .. mod.name) or "No admin mod found"

        local tabs = vgui.Create("DPanel", page)
        tabs:Dock(TOP)
        tabs:SetTall(K.S(30))
        tabs:DockMargin(0, 0, 0, K.S(10))
        tabs.Paint = nil
        local body = vgui.Create("DPanel", page)
        body:Dock(FILL)
        body.Paint = nil

        local current
        local function show(which)
            current = which
            body:Clear()
            if which == "players" then
                buildPlayers(body):Dock(FILL)
            else
                local sp = K.Scroll(body)
                sp:Dock(FILL)
                buildServer(sp)
            end
        end
        for _, t in ipairs({ { "players", "Players" }, { "server", "Server" } }) do
            local b = K.Button(tabs, t[2], function() show(t[1]) end, { small = true, selected = function() return current == t[1] end })
            b:Dock(LEFT)
            b:SetWide(K.S(140))
            b:DockMargin(0, 0, K.S(6), 0)
        end
        show("players")
    end,
})
