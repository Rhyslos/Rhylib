--[[
    Stamina bar (needs rhylib_stamina). A thin bar on top of the hotbar,
    as wide as the hotbar. It shrinks toward the middle from both ends as
    stamina runs down, blinks gently at 20% or less, turns red while
    you're exhausted, and fades out after 2 seconds at full.
]]

local HUD = Rhylib.HUD

local COL_TRACK = Color(255, 255, 255, 22)
local COL_FILL = Color(210, 214, 206)
local COL_LOW = Color(239, 159, 39)
local COL_EXHAUSTED = Color(226, 75, 74)

local fullSince = 0

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

    local exhausted = S.Exhausted(ply)
    local low = frac <= 0.2
    local col = exhausted and COL_EXHAUSTED or (low and COL_LOW or COL_FILL)
    local a = alpha
    if low then a = a * (0.65 + 0.35 * math.cos(now * 7)) end  -- gentle blink

    surface.SetDrawColor(COL_TRACK.r, COL_TRACK.g, COL_TRACK.b, COL_TRACK.a * alpha / 255)
    surface.DrawRect(x, y, w, barH)

    local fw = math.floor(w * frac + 0.5)
    if fw > 0 then
        surface.SetDrawColor(col.r, col.g, col.b, a)
        surface.DrawRect(x + math.floor((w - fw) * 0.5), y, fw, barH)
    end
end)
