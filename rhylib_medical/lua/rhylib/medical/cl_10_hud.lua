--[[
    Medical HUD and the E menu (client).

    - Downed: dark screen, bleed-out time, who is helping, give-up bar.
    - Helping: what you're doing, a progress bar, how to stop.
    - Looking at a downed player: "E  Medical", "Hold LMB  Drag".
    - Markers over downed players in range (through walls).
    - E on a downed player opens a small menu: Stabilise, and for medics
      Revive with a revive kit or a first aid kit (the medic picks).

    The downed list is rebuilt four times a second, not every frame.
]]

local Med = Rhylib.Medical
local UI = Rhylib.UI
local C = UI.Colors

local COL_DOWN = Color(214, 70, 60)
local COL_DIM = Color(0, 0, 0, 150)
local COL_MARK = Color(230, 70, 60, 230)
local COL_TRACK = Color(255, 255, 255, 28)
local COL_BG = Color(14, 16, 15, 225)
local COL_EDGE = Color(0, 0, 0, 230)

Med.clientDown = Med.clientDown or {}

timer.Create("Rhylib.Medical.List", 0.25, 0, function()
    local list = {}
    for _, p in ipairs(player.GetAll()) do
        if p:Alive() and Med.IsDown(p) then list[#list + 1] = p end
    end
    Med.clientDown = list
end)

local note, noteTime = nil, 0
Rhylib.Net.Receive("med.note", function()
    note, noteTime = net.ReadString(), RealTime()
end)

--------------------------------------------------------------------------
-- Drawing helpers (house style when rhylib_hud is installed)
--------------------------------------------------------------------------

local function S(n) return math.floor(n * ScrH() / 1080 + 0.5) end

local function plate(x, y, w, h, title, rule)
    local HUD = Rhylib.HUD
    if HUD and HUD.Frame then
        HUD.Frame(x, y, w, h, { title = title, rule = rule })
        return
    end
    surface.SetDrawColor(COL_BG)
    surface.DrawRect(x, y, w, h)
    surface.SetDrawColor(COL_EDGE)
    surface.DrawOutlinedRect(x, y, w, h)
    if title then draw.SimpleText(string.upper(title), UI.Font(12, 700), x + S(7), y + S(9), C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
end

local function bar(x, y, w, h, frac, col)
    surface.SetDrawColor(COL_TRACK)
    surface.DrawRect(x, y, w, h)
    local fw = math.floor(w * math.Clamp(frac, 0, 1) + 0.5)
    if fw > 0 then
        surface.SetDrawColor(col)
        surface.DrawRect(x, y, fw, h)
    end
end

local function clock(t)
    t = math.max(0, math.ceil(t))
    return string.format("%d:%02d", math.floor(t / 60), t % 60)
end

local function text(str, size, x, y, col, ax, weight)
    draw.SimpleText(str, UI.Font(size, weight or 500), x, y, col, ax or TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

-- The player helping `target`, and what they're doing.
local function helperOf(target)
    for _, p in ipairs(player.GetAll()) do
        local a, t, st, en = Med.Action(p)
        if a ~= 0 and t == target then return p, a, st, en end
    end
end

--------------------------------------------------------------------------
-- Parts
--------------------------------------------------------------------------

local function drawDowned(ply)
    local W, H = ScrW(), ScrH()
    surface.SetDrawColor(COL_DIM)
    surface.DrawRect(0, 0, W, H)

    local w, h = S(360), S(150)
    local x, y = math.floor((W - w) / 2), math.floor(H * 0.62)
    plate(x, y, w, h, "Downed", COL_DOWN)

    local stab = Med.StabilisedBy(ply)
    local left = Med.TimeLeft(ply)
    text(clock(left), 34, W / 2, y + S(52), stab and C.text or COL_DOWN, nil, 700)

    local helper, a, st, en = helperOf(ply)
    local line
    if helper and a ~= Med.A_STAB then
        line = (Med.ActName[a] or "Treating") .. " · " .. helper:Nick()
        bar(x + S(20), y + S(96), w - S(40), S(4), (CurTime() - st) / math.max(0.01, en - st), C.good)
    elseif stab then
        line = "Stabilised by " .. stab:Nick() .. " · timer paused"
    elseif Med.DraggedBy(ply) then
        line = "Being dragged by " .. Med.DraggedBy(ply):Nick()
    else
        line = "Bleeding out · wait for a medic"
    end
    text(line, 15, W / 2, y + S(82), C.textDim)

    local hold = ply.rhylibGiveUp
    local need = Med.Cfg("giveUpTime")
    if hold then
        bar(x + S(20), y + S(126), w - S(40), S(4), (CurTime() - hold) / need, COL_DOWN)
        text("Giving up...", 13, W / 2, y + S(114), C.text)
    else
        text("Hold " .. string.upper(input.LookupBinding("+jump") or "SPACE") .. " to give up", 13, W / 2, y + S(120), C.textDim)
    end
end

local function drawAction(ply, a, t, st, en)
    local W, H = ScrW(), ScrH()
    local w, h = S(320), S(70)
    local x, y = math.floor((W - w) / 2), math.floor(H * 0.58)
    local name = IsValid(t) and (t == ply and "yourself" or t:Nick()) or ""
    plate(x, y, w, h, Med.ActName[a] or "Treating")
    if a == Med.A_STAB then
        local left = IsValid(t) and Med.TimeLeft(t) or 0
        text(name .. " · " .. clock(left) .. " left, paused", 15, W / 2, y + S(34), C.text)
    else
        text(name, 15, W / 2, y + S(32), C.text)
        bar(x + S(16), y + S(44), w - S(32), S(4), (CurTime() - st) / math.max(0.01, en - st), C.good)
    end
    text("Move or press E to stop", 12, W / 2, y + S(60), C.textDim)
end

local function drawPrompt(ply)
    local t = Med.FindDowned(ply, Med.clientDown)
    if not t then return end
    local W, H = ScrW(), ScrH()
    local use = string.upper(input.LookupBinding("+use") or "E")
    local str = use .. "  Medical"
    if Med.HoldingHands(ply) then str = str .. "      Hold LMB  Drag" end
    text(t:Nick() .. " · down", 15, W / 2, H * 0.5 + S(40), COL_DOWN, nil, 600)
    text(str, 14, W / 2, H * 0.5 + S(60), C.text)
end

local function drawMarkers(ply)
    local range = Med.Cfg("markerRange")
    local eye = ply:EyePos()
    local s = S(1)
    for _, t in ipairs(Med.clientDown) do
        if t ~= ply and IsValid(t) then
            local pos = t:GetPos() + Vector(0, 0, 24)
            local dist = eye:Distance(pos)
            if dist <= range then
                local sp = pos:ToScreen()
                if sp.visible then
                    local x, y = math.floor(sp.x), math.floor(sp.y)
                    local r, th = 7 * s, 2 * s
                    surface.SetDrawColor(COL_MARK)
                    surface.DrawRect(x - r, y - th, r * 2, th * 2)
                    surface.DrawRect(x - th, y - r, th * 2, r * 2)
                    local status = Med.StabilisedBy(t) and "stabilised" or clock(Med.TimeLeft(t))
                    text(math.floor(dist * 0.019) .. " m · " .. status, 12, x, y + 14 * s, C.text)
                end
            end
        end
    end
end

Rhylib.Hook.Add("HUDPaint", "medical.hud", function()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end

    if Med.IsDown(ply) then
        drawMarkers(ply)
        drawDowned(ply)
    else
        drawMarkers(ply)
        local a, t, st, en = Med.Action(ply)
        if a ~= 0 then
            drawAction(ply, a, t, st, en)
        elseif Med.Dragging(ply) then
            text("Dragging " .. Med.Dragging(ply):Nick() .. " · release to drop", 15, ScrW() / 2, ScrH() * 0.5 + S(50), C.text)
        else
            drawPrompt(ply)
        end
    end

    if note and RealTime() - noteTime < 2.5 then
        text(note, 15, ScrW() / 2, ScrH() * 0.5 + S(90), C.warn)
    end
end)

--------------------------------------------------------------------------
-- E menu on a downed player
--------------------------------------------------------------------------

local function send(kind, target)
    Rhylib.Net.Start("med.act")
    net.WriteUInt(kind, Med.ACT_BITS)
    net.WriteUInt(target:EntIndex(), 8)
    net.SendToServer()
end

local openM

local function openMenu(ply, t)
    local Menus = Rhylib.Menus
    if Menus and Menus.RegisterCloser and not Med.closerAdded then
        Med.closerAdded = true
        Menus.RegisterCloser("medical", function()
            if IsValid(openM) then openM:Remove() return true end
            return false
        end)
    end
    if IsValid(openM) then openM:Remove() end
    local K = Menus and Menus.Kit
    local m = K and K.Menu() or DermaMenu()
    openM = m
    local any = false
    local stab = Med.StabilisedBy(t)
    if not stab then
        m:AddOption("Stabilise " .. t:Nick(), function() if IsValid(t) then send(Med.A_STAB, t) end end)
        any = true
    end
    if Med.IsMedic(ply) then
        if ply:HasWeapon(Med.REVIVE_KIT) then
            m:AddOption("Revive · revive kit", function() if IsValid(t) then send(Med.A_REVIVE, t) end end)
            any = true
        end
        if ply:HasWeapon(Med.FIRST_AID) then
            m:AddOption("Revive · first aid kit (slow)", function() if IsValid(t) then send(Med.A_FA_REVIVE, t) end end)
            any = true
        end
        if not ply:HasWeapon(Med.REVIVE_KIT) and not ply:HasWeapon(Med.FIRST_AID) then
            m:AddOption("No revive kit or first aid kit", function() end)
            any = true
        end
    end
    if not any then
        m:AddOption("Already stabilised by " .. stab:Nick(), function() end)
    end
    m:Open(ScrW() * 0.5 + S(24), ScrH() * 0.5)
end

Rhylib.Hook.Add("PlayerBindPress", "medical.menu", function(ply, bind, pressed)
    if not pressed or not string.find(bind, "+use", 1, true) then return end
    if Med.IsDown(ply) or Med.Action(ply) ~= 0 or Med.Dragging(ply) then return end
    local t = Med.FindDowned(ply, Med.clientDown)
    if not t then return end
    openMenu(ply, t)
    return true
end)
