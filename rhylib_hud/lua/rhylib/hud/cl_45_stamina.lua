--[[
    Stamina bar (needs rhylib_stamina). It shrinks toward the middle from
    both ends as stamina runs down, blinks gently at 20% or less, turns
    red while you're exhausted, and fades out after 2 seconds at full.

      Third person: a thin bar on top of the hotbar, as wide as it.
      Helmet visor: two mirrored strips along the cheek edges, in the
                    stretch between the armour/health bars and the chin.
                    Together they're one bar whose middle is the chin, so
                    each half shrinks toward the chin.
]]

local HUD = Rhylib.HUD

local COL_TRACK = Color(255, 255, 255, 22)
local COL_FILL = Color(210, 214, 206)
local COL_LOW = Color(239, 159, 39)
local COL_EXHAUSTED = Color(226, 75, 74)

local fullSince = 0

-- Visor strips: from just past the armour/health bars to near the chin.
local STRIP_GAP = 0.006     -- after the last armour/health bar (share of the width)
local STRIP_END = 0.392     -- the chin edge is at 0.4
local STRIP_THICK = 0.006
local STRIP_STEPS = 24

local function drawVisor(frac, col, a, alpha)
    local from = (HUD.VISOR_BAR_TO or 0.3) + STRIP_GAP
    local off = HUD.VISOR_BAR_OFFSET or 0.005
    draw.NoTexture()
    for _, side in ipairs({ -1, 1 }) do
        local strip = HUD.VisorStrip(side, from, STRIP_END, off, STRIP_THICK, STRIP_STEPS)
        -- Track, then the filled part at the chin end.
        surface.SetDrawColor(COL_TRACK.r, COL_TRACK.g, COL_TRACK.b, COL_TRACK.a * alpha / 255)
        for _, q in ipairs(strip.quads) do surface.DrawPoly(q) end
        local n = math.floor(frac * STRIP_STEPS + 0.5)
        if n > 0 then
            surface.SetDrawColor(col.r, col.g, col.b, a)
            for i = STRIP_STEPS - n + 1, STRIP_STEPS do surface.DrawPoly(strip.quads[i]) end
        end
        -- End ticks across the strip.
        local tick = HUD.Style and HUD.Style.tick
        if tick then
            surface.SetDrawColor(tick.r, tick.g, tick.b, tick.a * alpha / 255)
            for _, i in ipairs({ 1, #strip.outer }) do
                surface.DrawLine(strip.outer[i][1], strip.outer[i][2], strip.inner[i][1], strip.inner[i][2])
            end
        end
    end
end

Rhylib.Hook.Add("HUDPaint", "hud.stamina", function()
    local S = Rhylib.Stamina
    if not S or HUD.Hidden() then return end
    local ply = LocalPlayer()
    local frac = S.Frac(ply)
    local now = RealTime()

    -- Fade out after 2 s at full, fade straight back in when used.
    local alpha = 255
    if frac >= 1 then
        if fullSince == 0 then fullSince = now end
        alpha = math.Clamp(255 - (now - fullSince - 2) * 510, 0, 255)
    else
        fullSince = 0
    end
    if alpha <= 0 then return end

    local exhausted = S.Exhausted(ply)
    local low = frac <= 0.2
    local col = exhausted and COL_EXHAUSTED or (low and COL_LOW or COL_FILL)
    local a = alpha
    if low then a = a * (0.65 + 0.35 * math.cos(now * 7)) end  -- gentle blink

    if HUD.VisorActive and HUD.VisorActive() and HUD.VisorStrip then
        drawVisor(frac, col, a, alpha)
        return
    end

    local s = HUD.Scale()
    local r = HUD.HotbarRect
    local w, x, y
    local barH = math.max(2, math.floor(6 * s))
    local gap = math.floor(6 * s)
    if r and r.w > 0 and FrameNumber() - r.frame <= 1 then
        w, x, y = r.w, r.x, r.y - gap - barH
    else
        -- No hotbar (no weapons): same place, a fixed width.
        w = math.floor(ScrW() * 0.25)
        x = math.floor((ScrW() - w) * 0.5)
        local _, my = HUD.Margins("hotbar")
        y = ScrH() - my - math.floor(76 * s) - gap - barH
    end

    surface.SetDrawColor(COL_TRACK.r, COL_TRACK.g, COL_TRACK.b, COL_TRACK.a * alpha / 255)
    surface.DrawRect(x, y, w, barH)

    local fw = math.floor(w * frac + 0.5)
    if fw > 0 then
        surface.SetDrawColor(col.r, col.g, col.b, a)
        surface.DrawRect(x + math.floor((w - fw) * 0.5), y, fw, barH)
    end

    -- End ticks, in the HUD's style.
    local tick = HUD.Style and HUD.Style.tick
    if tick then
        surface.SetDrawColor(tick.r, tick.g, tick.b, tick.a * alpha / 255)
        surface.DrawRect(x - 2, y - 2, 2, barH + 4)
        surface.DrawRect(x + w, y - 2, 2, barH + 4)
    end
end)
