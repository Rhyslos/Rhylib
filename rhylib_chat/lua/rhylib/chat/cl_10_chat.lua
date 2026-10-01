--[[
    Chat, client side: replaces the default chat box.

    Closed: the last messages fade out after a while.
    Open (your chat key): a dark grey window with the history (scroll with
    the mouse wheel), the input line, and your current channel on the
    left. Click the channel name to pick another. Typing "/" shows
    matching commands (and player names after /pm); Tab or click fills
    one in, Up/Down picks.

    Where it sits:
      helmet visor (first person)  bottom-left, in the grey cheek area
      otherwise                    bottom-left, above the corner plate

    Everything other addons print with chat.AddText (DarkRP, admin mods,
    join messages) shows up here too.
]]

local Chat = Rhylib.Chat
local UI = Rhylib.UI

Chat.lines = Chat.lines or {}      -- { time, segs = { { col, text }, ... }, wrap = { w, lines } }
Chat.current = Chat.current or nil -- current channel
Chat.scroll = 0

local MAX_LINES = 150
local SHOW_TIME = 12               -- seconds a message stays when the chat is closed
local COL_BG = Color(30, 32, 30, 228)
local COL_BG_SOFT = Color(30, 32, 30, 120)
local COL_INPUT = Color(46, 49, 46, 255)
local COL_TEXT = Color(228, 227, 220)
local COL_DIM = Color(150, 150, 144)
local COL_SYSTEM = Color(170, 176, 180)
local COL_SUGGEST = Color(40, 43, 40, 245)
local COL_PICK = Color(62, 74, 90, 255)

local function currentChannel()
    if not Chat.current then Chat.current = Chat.byId[Rhylib.Config.Get("chat", "defaultChannel")] or Chat.CHANNELS[1] end
    return Chat.current
end

--------------------------------------------------------------------------
-- Messages
--------------------------------------------------------------------------

function Chat.Add(segs)
    local lines = Chat.lines
    lines[#lines + 1] = { time = RealTime(), segs = segs }
    if #lines > MAX_LINES then table.remove(lines, 1) end
    if Chat.scroll > 0 then Chat.scroll = Chat.scroll + 1 end  -- keep the view still while scrolled up
end

-- Everything chat.AddText receives (colours, strings, players) lands here too.
Chat.oldAddText = Chat.oldAddText or chat.AddText
function chat.AddText(...)
    local segs, col = {}, COL_TEXT
    for _, v in ipairs({ ... }) do
        if IsColor(v) or (istable(v) and v.r and v.g and v.b) then
            col = Color(v.r, v.g, v.b)
        elseif isentity(v) and IsValid(v) and v:IsPlayer() then
            segs[#segs + 1] = { team.GetColor(v:Team()), v:Nick() }
        else
            segs[#segs + 1] = { col, tostring(v) }
        end
    end
    Chat.Add(segs)
    Chat.oldAddText(...)  -- still prints to the console
end

-- Join/leave and other engine messages.
Rhylib.Hook.Add("ChatText", "chat.engine", function(_, _, text, kind)
    if kind == "chat" then return end  -- player chat arrives through chat.AddText
    Chat.Add({ { COL_SYSTEM, text } })
    return true
end)

net.Receive(Rhylib.Net.Name("chat.msg"), function()
    local ch = Chat.CHANNELS[net.ReadUInt(Chat.CHANNEL_BITS)]
    local sender = net.ReadEntity()
    local target = net.ReadEntity()
    local text = net.ReadString()
    if not ch then
        Chat.Add({ { COL_SYSTEM, text } })
        return
    end
    local name = IsValid(sender) and sender:Nick() or "?"
    local nameCol = IsValid(sender) and team.GetColor(sender:Team()) or COL_DIM
    local segs = { { ch.color, "[" .. ch.name .. "] " }, { nameCol, name } }
    if ch.private then
        local to = IsValid(target) and target:Nick() or "?"
        segs[#segs + 1] = { COL_DIM, (target == LocalPlayer() and " → you" or (" → " .. to)) }
    end
    segs[#segs + 1] = { COL_TEXT, ": " .. text }
    Chat.Add(segs)
    chat.PlaySound()
    MsgC(ch.color, "[" .. ch.name .. "] ", nameCol, name, COL_TEXT, ": " .. text .. "\n")
end)

--------------------------------------------------------------------------
-- Layout and drawing
--------------------------------------------------------------------------

-- x, y, w, h of the chat area, and whether it's the small visor version.
function Chat.Rect()
    local W, H = ScrW(), ScrH()
    local s = H / 1080
    local HUD = Rhylib.HUD
    if HUD and HUD.VisorActive and HUD.VisorActive() then
        local mx, my = HUD.Margins("ammo")  -- mirrors the ammo box on the other cheek
        local w, h = math.floor(W * 0.25), math.floor(H * 0.135)
        return mx, H - my - h, w, h, true
    end
    local w, h = math.floor(W * 0.3), math.floor(260 * s)
    return math.floor(24 * s), H - math.floor(210 * s) - h, w, h, false
end

-- Word-wraps a message into lines of { { col, text, x } } for width w.
-- Words of the same colour on a line are joined into one piece, so a line
-- is a handful of draw calls. Cached until the width or font changes.
local function wrap(msg, font, w)
    if msg.wrapW == w and msg.wrapFont == font then return msg.wrapLines end
    surface.SetFont(font)
    local spaceW = surface.GetTextSize(" ")
    local lines, line, x = {}, {}, 0
    for _, seg in ipairs(msg.segs) do
        local run = nil  -- the piece words of this segment are joining
        local pendingSpace = 0
        for word, space in string.gmatch(seg[2], "(%S*)(%s*)") do
            if word ~= "" then
                local ww = surface.GetTextSize(word)
                if x > 0 and x + pendingSpace * spaceW + ww > w then
                    lines[#lines + 1] = line
                    line, x, run, pendingSpace = {}, 0, nil, 0
                end
                x = x + pendingSpace * spaceW
                if run then
                    run[2] = run[2] .. string.rep(" ", pendingSpace) .. word
                else
                    run = { seg[1], word, x }
                    line[#line + 1] = run
                end
                x = x + ww
                pendingSpace = 0
            end
            pendingSpace = pendingSpace + #space
        end
        x = x + pendingSpace * spaceW  -- trailing space before the next segment
    end
    lines[#lines + 1] = line
    msg.wrapW, msg.wrapFont, msg.wrapLines = w, font, lines
    return lines
end

-- Two reused colours, so drawing allocates nothing.
local drawCol, shadowCol = Color(255, 255, 255), Color(0, 0, 0)

-- Draws messages bottom-up into the box; open = everything (scrollable).
local function drawMessages(x, y, w, h, font, lineH, open)
    local now = RealTime()
    local yy = y + h
    local skip = open and Chat.scroll or 0
    surface.SetFont(font)
    for i = #Chat.lines, 1, -1 do
        local msg = Chat.lines[i]
        local age = now - msg.time
        if not open and age > SHOW_TIME then break end
        local alpha = open and 255 or math.Clamp((SHOW_TIME - age) * 255, 0, 255)
        local lines = wrap(msg, font, w)
        for k = #lines, 1, -1 do
            if skip > 0 then
                skip = skip - 1
            else
                yy = yy - lineH
                if yy < y then return end
                for _, part in ipairs(lines[k]) do
                    local c = part[1]
                    shadowCol.a = alpha * 0.8
                    surface.SetTextColor(shadowCol)
                    surface.SetTextPos(x + part[3] + 1, yy + 1)
                    surface.DrawText(part[2])
                    drawCol.r, drawCol.g, drawCol.b, drawCol.a = c.r, c.g, c.b, alpha
                    surface.SetTextColor(drawCol)
                    surface.SetTextPos(x + part[3], yy)
                    surface.DrawText(part[2])
                end
            end
        end
    end
end

-- Closed chat: recent messages only, on a soft backing while any show.
Rhylib.Hook.Add("HUDPaint", "chat.feed", function()
    if IsValid(Chat.panel) then return end
    local last = Chat.lines[#Chat.lines]
    if not last or RealTime() - last.time > SHOW_TIME then return end
    local x, y, w, h, visor = Chat.Rect()
    local s = ScrH() / 1080
    local font = UI.Font(visor and 14 or 16)
    local lineH = math.floor((visor and 17 or 20) * s)
    local inputH = math.floor(30 * s)
    drawMessages(x + 8 * s, y, w - 16 * s, h - inputH, font, lineH, false)
end)

Rhylib.Hook.Add("HUDShouldDraw", "chat.hidedefault", function(name)
    if name == "CHudChat" then return false end
end)

--------------------------------------------------------------------------
-- Suggestions
--------------------------------------------------------------------------

local function suggestions(text)
    local out = {}
    local pmName = string.match(text, '^/[pP][mM]%s+"?([^"%s]*)$') or string.match(text, "^/[wW]%s+(%S*)$")
    if pmName then
        local cmd = string.match(text, "^(/%S+)")
        for _, p in ipairs(player.GetAll()) do
            if p ~= LocalPlayer() and string.find(string.lower(p:Nick()), string.lower(pmName), 1, true) then
                local nick = p:Nick()
                local fill = string.find(nick, " ", 1, true) and ('"' .. nick .. '" ') or (nick .. " ")
                out[#out + 1] = { label = nick, desc = "send a private message", fill = cmd .. " " .. fill }
            end
        end
        return out
    end
    local typed = string.match(text, "^/(%S*)$")
    if not typed then return out end
    typed = string.lower(typed)
    for _, ch in ipairs(Chat.CHANNELS) do
        for _, cmd in ipairs(ch.cmds) do
            if string.sub(cmd, 1, #typed) == typed then
                out[#out + 1] = { label = "/" .. cmd, desc = ch.desc, fill = "/" .. cmd .. " ", col = ch.color }
                break
            end
        end
    end
    return out
end

--------------------------------------------------------------------------
-- The open window
--------------------------------------------------------------------------

local function sendTyping(on)
    Rhylib.Net.Start("chat.typing")
    net.WriteBool(on)
    net.SendToServer()
end

local function submit(text)
    text = string.Trim(text)
    if text == "" then return end
    local kind, a, b, c = Chat.Parse(text, currentChannel())
    if kind == "pass" then
        RunConsoleCommand("say", text)  -- DarkRP and admin mod commands
    elseif kind == "switch" then
        if a.private then return end
        Chat.current = a
    elseif kind == "usage" then
        Chat.Add({ { COL_SYSTEM, a } })
    elseif kind == "send" then
        local target = NULL
        if a.private then
            target = Chat.FindPlayer(c)
            if not IsValid(target) then
                Chat.Add({ { COL_SYSTEM, "No player called \"" .. c .. "\"" } })
                return
            end
        end
        Rhylib.Net.Start("chat.send")
        net.WriteUInt(a.index, Chat.CHANNEL_BITS)
        net.WriteEntity(target)
        net.WriteString(b)
        net.SendToServer()
    end
end

local PANEL = {}

function PANEL:Init()
    self.s = ScrH() / 1080
    local s = self.s
    self.inputH = math.floor(30 * s)
    self.pick = 1
    self.suggest = {}

    local entry = vgui.Create("DTextEntry", self)
    entry:SetFont(UI.Font(16))
    entry:SetTextColor(COL_TEXT)
    entry:SetCursorColor(COL_TEXT)
    entry:SetHighlightColor(Color(90, 120, 160))
    entry:SetPaintBackground(false)
    entry.Paint = function(e, w, h)
        draw.RoundedBox(4, 0, 0, w, h, COL_INPUT)
        e:DrawTextEntryText(COL_TEXT, Color(90, 120, 160), COL_TEXT)
        if e:GetValue() == "" then
            draw.SimpleText("Say something in " .. currentChannel().name .. "…", UI.Font(15), 6, h * 0.5, COL_DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end
    entry.OnEnter = function(e)
        local pick = self.suggest[self.pick]
        local text = e:GetValue()
        -- Enter on a half-typed command fills it in first.
        if pick and #self.suggest > 0 and string.match(text, "^/%S*$") and text ~= string.Trim(pick.fill) then
            e:SetText(pick.fill)
            e:SetCaretPos(#pick.fill)
            e:RequestFocus()
            self:UpdateSuggest()
            return
        end
        submit(text)
        Chat.Close()
    end
    entry.OnChange = function(e)
        self:UpdateSuggest()
        hook.Run("ChatTextChanged", e:GetValue())
    end
    entry.OnKeyCodeTyped = function(e, code)
        if code == KEY_ESCAPE then
            Chat.Close()
            Chat.hideMenuUntil = RealTime() + 0.3
            return true
        elseif code == KEY_TAB then
            local pick = self.suggest[self.pick]
            if pick then
                e:SetText(pick.fill)
                e:SetCaretPos(#pick.fill)
                self:UpdateSuggest()
            end
            timer.Simple(0, function() if IsValid(e) then e:RequestFocus() end end)
            return true
        elseif code == KEY_UP and #self.suggest > 0 then
            self.pick = math.max(1, self.pick - 1)
            return true
        elseif code == KEY_DOWN and #self.suggest > 0 then
            self.pick = math.min(#self.suggest, self.pick + 1)
            return true
        elseif code == KEY_ENTER then
            e:OnEnter()
            return true
        end
    end
    self.entry = entry
    self:Layout()
end

function PANEL:Layout()
    local x, y, w, h, visor = Chat.Rect()
    self.visor = visor
    self:SetPos(x, y)
    self:SetSize(w, h)
    local s = self.s
    self.chanW = math.floor(84 * s)
    self.entry:SetPos(self.chanW + math.floor(6 * s), h - self.inputH)
    self.entry:SetSize(w - self.chanW - math.floor(6 * s), self.inputH)
end

function PANEL:UpdateSuggest()
    self.suggest = suggestions(self.entry:GetValue())
    self.pick = math.Clamp(self.pick, 1, math.max(1, #self.suggest))
end

function PANEL:Think()
    local _, _, _, _, visor = Chat.Rect()
    if visor ~= self.visor then self:Layout() end
end

function PANEL:ChannelButtonHit(mx, my)
    local h = self:GetTall()
    return mx >= 0 and mx <= self.chanW and my >= h - self.inputH and my <= h
end

function PANEL:OnMousePressed(code)
    if code ~= MOUSE_LEFT then return end
    local mx, my = self:CursorPos()
    if self:ChannelButtonHit(mx, my) then
        local menu = DermaMenu()
        for _, ch in ipairs(Chat.CHANNELS) do
            if ch.private then
                menu:AddOption("Private message…", function()
                    self.entry:SetText("/pm ")
                    self.entry:SetCaretPos(4)
                    self.entry:RequestFocus()
                    self:UpdateSuggest()
                end)
            else
                local opt = menu:AddOption(ch.name .. "  ·  " .. ch.desc, function()
                    Chat.current = ch
                    self.entry:RequestFocus()
                end)
                if ch == currentChannel() then opt:SetChecked(true) end
            end
        end
        menu:Open()
    end
end

function PANEL:OnMouseWheeled(delta)
    Chat.scroll = math.max(0, Chat.scroll + delta * 3)
    return true
end

function PANEL:Paint(w, h)
    local s = self.s
    draw.RoundedBox(math.floor(6 * s), 0, 0, w, h, COL_BG)

    local font = UI.Font(self.visor and 14 or 16)
    local lineH = math.floor((self.visor and 17 or 20) * s)
    local pad = math.floor(8 * s)
    drawMessages(pad, pad, w - pad * 2, h - self.inputH - pad * 2, font, lineH, true)
    if Chat.scroll > 0 then
        draw.SimpleText("▲ scrolled up (" .. Chat.scroll .. ")", UI.Font(12), w - pad, pad, COL_DIM, TEXT_ALIGN_RIGHT)
    end

    -- Channel button.
    local ch = currentChannel()
    local mx, my = self:CursorPos()
    local hover = self:ChannelButtonHit(mx, my)
    draw.RoundedBox(4, 0, h - self.inputH, self.chanW, self.inputH, hover and COL_PICK or COL_INPUT)
    draw.SimpleText(ch.name .. " ▾", UI.Font(15, 700), self.chanW * 0.5, h - self.inputH * 0.5, ch.color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

-- Suggestions above the box (drawn over everything).
function PANEL:PaintOver(w, h)
    local list = self.suggest
    if #list == 0 then return end
    local s = self.s
    local rowH = math.floor(22 * s)
    local n = math.min(#list, 8)
    local bx, bw = self.chanW + math.floor(6 * s), w - self.chanW - math.floor(6 * s)
    local by = h - self.inputH - rowH * n - math.floor(4 * s)
    DisableClipping(true)
    for i = 1, n do
        local it = list[i]
        local y = by + (i - 1) * rowH
        draw.RoundedBox(0, bx, y, bw, rowH, i == self.pick and COL_PICK or COL_SUGGEST)
        draw.SimpleText(it.label, UI.Font(15, 700), bx + 8 * s, y + rowH * 0.5, it.col or COL_TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(it.desc, UI.Font(13), bx + bw - 8 * s, y + rowH * 0.5, COL_DIM, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end
    DisableClipping(false)
end

vgui.Register("RhylibChat", PANEL, "EditablePanel")

function Chat.Open()
    if IsValid(Chat.panel) then return end
    Chat.scroll = 0
    local p = vgui.Create("RhylibChat")
    p:MakePopup()
    p.entry:RequestFocus()
    Chat.panel = p
    hook.Run("StartChat", false)
    sendTyping(true)
end

function Chat.Close()
    if not IsValid(Chat.panel) then return end
    Chat.panel:Remove()
    Chat.panel = nil
    hook.Run("FinishChat")
    hook.Run("ChatTextChanged", "")
    sendTyping(false)
end

-- Escape closes the chat; don't let it open the game menu too.
Rhylib.Hook.Add("Think", "chat.escape", function()
    if Chat.hideMenuUntil and RealTime() < Chat.hideMenuUntil and gui.IsGameUIVisible() then
        gui.HideGameUI()
    end
end)

-- The chat keys open ours instead of the default box.
Rhylib.Hook.Add("PlayerBindPress", "chat.open", function(_, bind, pressed)
    if not pressed then return end
    if string.find(bind, "messagemode", 1, true) then
        Chat.Open()
        return true
    end
end)
