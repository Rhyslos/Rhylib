--[[
    The three-arc recoil crosshair.

    Drawn from the weapon's real spread (Rhylib.Weapons.Spread), converted
    from degrees to pixels using the current field of view, so every shot
    lands inside the circle you see. Arcs keep their size and only move
    outward; aiming shrinks the whole crosshair.
]]

local W = Rhylib.Weapons
W.Crosshair = W.Crosshair or {}
local X = W.Crosshair

X.hitTime = X.hitTime or 0
X.hitKind = 0   -- 0 body, 1 head, 2 down/kill

local HIT_SHOW = 0.25             -- seconds a hit marker shows (fading)
local KILL_SHOW = 0.6
local hitSound = CreateClientConVar("rhylib_hitsound", "1", true, false, "Play a sound when your bolt hits someone", 0, 1)
local SOUNDS = {
    [0] = { "buttons/lightswitch2.wav", 150, 0.45 },     -- body
    [1] = { "buttons/lightswitch2.wav", 210, 0.6 },      -- head
    [2] = { "buttons/blip1.wav", 120, 0.6 },             -- down / kill
}

local GAP = math.rad(14)          -- slit width
local SIXTY = math.rad(60)
local SEGMENTS = 12
local MIN_RADIUS = 10             -- px at 1080p, so tiny cones stay readable
local LINE, OUTLINE = 2, 4        -- px at 1080p

local colLine = Color(244, 244, 240)
local colOutline = Color(0, 0, 0, 128)
local colHead = Color(255, 90, 80)
local colMark = Color(0, 0, 0)

local verts = { { x = 0, y = 0 }, { x = 0, y = 0 }, { x = 0, y = 0 }, { x = 0, y = 0 } }

-- Draws one convex quad. surface.DrawPoly needs clockwise order, so flip if needed.
local function quad(x1, y1, x2, y2, x3, y3, x4, y4)
    local area = (x1 * y2 - x2 * y1) + (x2 * y3 - x3 * y2) + (x3 * y4 - x4 * y3) + (x4 * y1 - x1 * y4)
    if area < 0 then
        x2, y2, x4, y4 = x4, y4, x2, y2
    end
    verts[1].x, verts[1].y = x1, y1
    verts[2].x, verts[2].y = x2, y2
    verts[3].x, verts[3].y = x3, y3
    verts[4].x, verts[4].y = x4, y4
    surface.DrawPoly(verts)
end

local function arc(cx, cy, r, a0, a1, w)
    local ri, ro = r - w * 0.5, r + w * 0.5
    local step = (a1 - a0) / SEGMENTS
    for i = 0, SEGMENTS - 1 do
        local t0, t1 = a0 + step * i, a0 + step * (i + 1)
        local c0, s0, c1, s1 = math.cos(t0), math.sin(t0), math.cos(t1), math.sin(t1)
        quad(cx + c0 * ro, cy + s0 * ro, cx + c1 * ro, cy + s1 * ro,
             cx + c1 * ri, cy + s1 * ri, cx + c0 * ri, cy + s0 * ri)
    end
end

local function line(x1, y1, x2, y2, w)
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len == 0 then return end
    local nx, ny = -dy / len * w * 0.5, dx / len * w * 0.5
    quad(x1 + nx, y1 + ny, x2 + nx, y2 + ny, x2 - nx, y2 - ny, x1 - nx, y1 - ny)
end

-- Cone angle (degrees) to screen pixels. Source FOV is horizontal at 4:3.
local function degToPx(deg, fov)
    return math.tan(math.rad(deg)) / (math.tan(math.rad(fov * 0.5)) * 0.75) * ScrH() * 0.5
end

local function drawShape(x, y, r, offsets, s, w)
    local centres = W.Spread.ARC_CENTRES
    for i = 1, 3 do
        local c = centres[i]
        local cx, cy = x + math.cos(c) * offsets[i], y + math.sin(c) * offsets[i]
        arc(cx, cy, r, c - SIXTY + GAP * 0.5, c + SIXTY - GAP * 0.5, w)
    end
    -- Centre chevron, never moves or scales.
    line(x - 6 * s, y + 3 * s, x, y - 4 * s, w)
    line(x, y - 4 * s, x + 6 * s, y + 3 * s, w)
end

local offsets = { 0, 0, 0 }

function X.Draw(wep, x, y)
    -- Grapple mode: the hook's landing marker instead (cl_40_grapple.lua).
    if wep.InGrappleMode and wep:InGrappleMode() and X.DrawGrapple then
        X.DrawGrapple(wep, x, y)
        return
    end
    local ply = LocalPlayer()
    local fov = wep:TranslateFOV(ply:GetFOV())
    local s = ScrH() / 1080
    local t = CurTime()

    local r = math.max(degToPx(W.Spread.BaseCone(wep), fov), MIN_RADIUS * s)
    local o1, o2, o3 = W.Spread.Offsets(wep, t)
    offsets[1], offsets[2], offsets[3] = degToPx(o1, fov), degToPx(o2, fov), degToPx(o3, fov)

    draw.NoTexture()
    surface.SetDrawColor(colOutline)
    drawShape(x, y, r, offsets, s, OUTLINE * s)
    surface.SetDrawColor(colLine)
    drawShape(x, y, r, offsets, s, LINE * s)

    -- Hit marker: four diagonal ticks around the ring, fading out. Head
    -- hits are red; dropping someone shows a larger, longer red X.
    local kill = X.hitKind == 2
    local show = kill and KILL_SHOW or HIT_SHOW
    local age = t - X.hitTime
    if age < show then
        local f = 1 - age / show
        local base = X.hitKind == 0 and colLine or colHead
        colMark.r, colMark.g, colMark.b, colMark.a = base.r, base.g, base.b, 255 * f
        local grow = kill and (1 + 0.4 * (1 - f)) or 1
        local r0 = (r + 5 * s) * grow
        local r1 = r0 + (kill and 16 or 10) * s
        local w = (kill and 3 or LINE) * s
        for k = 0, 3 do
            local a = math.rad(45 + 90 * k)
            local c, sn = math.cos(a), math.sin(a)
            surface.SetDrawColor(0, 0, 0, 128 * f)
            line(x + c * r0, y + sn * r0, x + c * r1, y + sn * r1, w + 2 * s)
            surface.SetDrawColor(colMark)
            line(x + c * r0, y + sn * r0, x + c * r1, y + sn * r1, w)
        end
    end
end

Rhylib.Net.ReceiveBatch("wep.hit", function()
    return net.ReadUInt(2)
end, function(kind)
    -- A kill marker isn't cut short by the next body hit.
    if X.hitKind == 2 and CurTime() - X.hitTime < KILL_SHOW * 0.5 and kind < 2 then return end
    X.hitTime = CurTime()
    X.hitKind = kind
    local snd = hitSound:GetBool() and SOUNDS[kind]
    local me = LocalPlayer()
    if snd and IsValid(me) then me:EmitSound(snd[1], 0, snd[2], snd[3], CHAN_STATIC) end  -- level 0: not positional
end)

-- In the settings menu (rhylib_menus).
Rhylib.Hook.Add("InitPostEntity", "weapons.hitsound.setting", function()
    local Menus = Rhylib.Menus
    if Menus and Menus.AddSetting then
        Menus.AddSetting("Weapons", { id = "wep.hitsound", order = 10, title = "Hit sounds",
            desc = "A click when your bolt hits someone", kind = "toggle", convar = "rhylib_hitsound" })
    end
end)
