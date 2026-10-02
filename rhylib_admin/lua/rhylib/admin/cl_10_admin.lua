--[[
    Client side of the admin suite: replies and action notices in chat,
    announcements (the event banner), the map change countdown, and the
    helpers the staff menu uses (rhylib_menus cl_30_commands.lua):
        Admin.Run(id, words)               send a command
        Admin.AskArgs(cmd, done(words))    ask for its arguments (menus / text boxes)
        Admin.RequestList(which, arg, cb)  1 bans, 2 log, 3 warnings (SteamID64)
]]

local Admin = Rhylib.Admin

local ACCENT = Color(230, 170, 70)
local BAD = Color(235, 90, 80)
local TEXT = Color(225, 225, 225)

Rhylib.Net.Receive("admin.msg", function()
    local bad = net.ReadBool()
    local text = net.ReadString()
    chat.AddText(bad and BAD or ACCENT, "[Admin] ", TEXT, text)
end)

Rhylib.Net.Receive("admin.announce", function()
    local by = net.ReadString()
    local text = net.ReadString()
    local Chat = Rhylib.Chat
    if Chat and Chat.ShowEvent then Chat.ShowEvent(by, text) end
    chat.AddText(ACCENT, "[Announcement] ", TEXT, text)
    surface.PlaySound("buttons/blip1.wav")
end)

-- Map change countdown at the top of the screen.
local countdown
Rhylib.Net.Receive("admin.countdown", function()
    local m, secs = net.ReadString(), net.ReadUInt(6)
    if m == "" then countdown = nil return end   -- cancelled
    countdown = { map = m, at = CurTime() + secs }
    chat.AddText(ACCENT, "[Admin] ", TEXT, "Changing map to " .. m .. " in " .. secs .. " seconds")
end)
Rhylib.Hook.Add("HUDPaint", "admin.countdown", function()
    if not countdown then return end
    local left = math.ceil(countdown.at - CurTime())
    if left < 0 then countdown = nil return end
    local font = Rhylib.UI and Rhylib.UI.Font and Rhylib.UI.Font(math.floor(ScrH() / 40), 700) or "DermaLarge"
    draw.SimpleTextOutlined("Map change: " .. countdown.map .. " in " .. left, font, ScrW() * 0.5, ScrH() * 0.12, ACCENT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 200))
end)

function Admin.Run(id, words)
    words = words or {}
    Rhylib.Net.Start("admin.run")
    net.WriteString(id)
    net.WriteUInt(math.min(#words, 15), 4)
    for i = 1, math.min(#words, 15) do net.WriteString(tostring(words[i])) end
    net.SendToServer()
end

-- How the menu names a player for a command.
function Admin.TargetWord(p)
    if not IsValid(p) then return "^" end
    if p:IsBot() then return p:Nick() end
    return p:SteamID64() or p:Nick()
end

-- Choices for an argument kind, or nil (= type it).
local function choices(kind)
    if kind == "rank" then
        local out = {}
        local mine = Admin.Level(LocalPlayer())
        for _, r in ipairs(Admin.Ranks()) do
            if (r.level or 0) < mine then out[#out + 1] = { r.id, r.name } end
        end
        return out
    elseif kind == "rosterrank" and Rhylib.Roster then
        local out = {}
        for i, r in ipairs(Rhylib.Roster.Ranks()) do out[#out + 1] = { tostring(i), r[1] .. " · " .. r[2] } end
        return out
    elseif kind == "qual" and Rhylib.Roster then
        local out = {}
        for _, q in ipairs(Rhylib.Roster.Quals()) do out[#out + 1] = { q[1], q[2] } end
        return out
    elseif kind == "onoff" then
        return { { "on", "On" }, { "off", "Off" } }
    elseif kind == "battalion" then
        local out, seen = {}, {}
        for _, job in pairs(RPExtraTeams or {}) do
            local c = job.category
            if c and not seen[c] then
                seen[c] = true
                out[#out + 1] = { c, c }
            end
        end
        table.sort(out, function(a, b) return a[1] < b[1] end)
        return #out > 0 and out or nil
    elseif kind == "job" then
        local out = {}
        for _, job in pairs(RPExtraTeams or {}) do out[#out + 1] = { job.command or job.name, job.name } end
        table.sort(out, function(a, b) return a[2] < b[2] end)
        return #out > 0 and out or nil
    elseif kind == "duration" then
        return { { "30m", "30 minutes" }, { "2h", "2 hours" }, { "1d", "1 day" }, { "3d", "3 days" }, { "1w", "1 week" },
            { "perm", "Permanent" }, { "?", "Other..." } }
    end
end

local HINT = {
    number = "A number", text = "", word = "", class = "Weapon class, e.g. rhylib_dc15a",
    map = "Map name, e.g. rp_venator", duration = "30m, 2h, 1d, 1w or perm",
}

-- Asks for each argument in turn; done(words).
function Admin.AskArgs(cmd, done)
    local K = Rhylib.Menus and Rhylib.Menus.Kit
    local words = {}
    local function step(i)
        local a = cmd.args[i]
        if not a then done(words) return end
        local function typed()
            if not K then return end
            K.Prompt(cmd.name, a[2] .. (HINT[a[3]] and HINT[a[3]] ~= "" and (" (" .. HINT[a[3]] .. ")") or ""), "", function(text)
                words[#words + 1] = text
                step(i + 1)
            end)
        end
        local list = choices(a[3])
        if list and K then
            local m = K.Menu()
            for _, c in ipairs(list) do
                m:AddOption(c[2], function()
                    if c[1] == "?" then typed() return end
                    words[#words + 1] = c[1]
                    step(i + 1)
                end)
            end
            m:Open()
        else
            typed()
        end
    end
    step(1)
end

Admin.listCb = Admin.listCb or {}
function Admin.RequestList(which, arg, cb)
    Admin.listCb[which] = cb
    Rhylib.Net.Start("admin.listget")
    net.WriteUInt(which, 2)
    net.WriteString(arg or "")
    net.SendToServer()
end

Rhylib.Net.Receive("admin.list", function()
    local which = net.ReadUInt(2)
    local rows = {}
    for i = 1, net.ReadUInt(8) do
        local r = {}
        for k = 1, net.ReadUInt(3) do r[k] = net.ReadString() end
        rows[i] = r
    end
    local cb = Admin.listCb[which]
    if cb then cb(rows) end
end)
