--[[
    Reload input and the radial reload menu (client only).

    Tap R:  magazine reload.
    E + R:  next fire mode.   Shift + E + R: safety on/off.
    Hold R: the radial menu opens and the view stops turning. Move the
            mouse toward an option and let go of R to pick it.
            Let go in the middle to cancel.

    The client only asks; the server checks the pouch and runs the reload.
]]

local W = Rhylib.Weapons
local UI = Rhylib.UI

local R = {
    down = false,
    downTime = 0,
    open = false,
    cx = 0,              -- virtual cursor, moved by the mouse while open
    cy = 0,
    selected = nil,
}
W.Radial = R

local DEADZONE = 40      -- px at 1080p; inside this, release cancels
local CURSOR_MAX = 140
local RING = 150         -- distance of the options from the centre

local function activeRhylibWeapon()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return nil end
    local wep = ply:GetActiveWeapon()
    if IsValid(wep) and wep.IsRhylib then return wep end
    return nil
end

-- Options for the current weapon, laid out around the ring.
-- Angles are screen space: 180 = left, 0 = right.
local function options(wep)
    local ply = LocalPlayer()
    local list = {
        { kind = 1, label = "Magazine", count = ply:GetAmmoCount("rhylib_blaster"), angle = 180 },
    }
    if wep.UsesCell then
        list[#list + 1] = { kind = 2, label = "Power cell", count = ply:GetAmmoCount("rhylib_cell"), angle = 0 }
    end
    return list
end

local function sendReload(kind)
    Rhylib.Net.Start("wep.reload")
    net.WriteUInt(kind, 2)
    net.SendToServer()
end

local function reset()
    R.down = false
    R.open = false
    R.selected = nil
    R.cx, R.cy = 0, 0
end

local function reloadKeyHeld()
    local key = input.LookupBinding("+reload")
    local code = key and input.GetKeyCode(key)
    return code and code > 0 and input.IsKeyDown(code)
end

-- Catch R before the default reload runs.
Rhylib.Hook.Add("PlayerBindPress", "weapons.reload", function(ply, bind, pressed)
    if not pressed or not string.find(bind, "+reload", 1, true) then return end
    -- R rotates items while the inventory is open.
    if Rhylib.Inventory and IsValid(Rhylib.Inventory.panel) then return true end
    if not activeRhylibWeapon() then return end

    -- E + R: fire mode. Shift + E + R: safety.
    if ply:KeyDown(IN_USE) then
        Rhylib.Net.Start("wep.mode")
        net.WriteBool(ply:KeyDown(IN_SPEED))
        net.SendToServer()
        return true
    end
    R.down = true
    R.downTime = RealTime()
    return true
end)

Rhylib.Hook.Add("Think", "weapons.reload", function()
    if not R.down then return end

    local wep = activeRhylibWeapon()
    if not wep then
        reset()
        return
    end

    if not reloadKeyHeld() then
        if R.open then
            if R.selected then sendReload(R.selected) end
        else
            sendReload(1)  -- a tap is a magazine reload
        end
        reset()
        return
    end

    if not R.open and RealTime() - R.downTime >= Rhylib.Config.Get("weapons", "reloadHoldTime") then
        R.open = true
        R.cx, R.cy = 0, 0
    end
end)

-- While the menu is open, the mouse moves the menu cursor instead of the view.
Rhylib.Hook.Add("InputMouseApply", "weapons.reload", function(cmd, x, y)
    if not R.open then return end
    local s = ScrH() / 1080
    R.cx = R.cx + x * 0.6
    R.cy = R.cy + y * 0.6
    local len = math.sqrt(R.cx * R.cx + R.cy * R.cy)
    local max = CURSOR_MAX * s
    if len > max then
        R.cx, R.cy = R.cx / len * max, R.cy / len * max
    end
    return true
end)

local function pickOption(list, s)
    local len = math.sqrt(R.cx * R.cx + R.cy * R.cy)
    if len < DEADZONE * s then return nil end
    local ang = math.deg(math.atan2(R.cy, R.cx))
    local best, bestD = nil, math.huge
    for _, opt in ipairs(list) do
        local d = math.abs(math.NormalizeAngle(ang - opt.angle))
        if d < bestD then
            best, bestD = opt, d
        end
    end
    return best
end

local COL_DEADZONE = Color(0, 0, 0, 120)
local COL_PICK = Color(60, 72, 88, 235)

Rhylib.Hook.Add("HUDPaint", "weapons.reload", function()
    if not R.open then return end
    local wep = activeRhylibWeapon()
    if not wep then return end

    local s = ScrH() / 1080
    local cx, cy = ScrW() * 0.5, ScrH() * 0.5
    local list = options(wep)
    local pick = pickOption(list, s)
    R.selected = pick and pick.count > 0 and pick.kind or nil

    -- Centre: cancel zone.
    local dz = DEADZONE * s
    draw.RoundedBox(dz, cx - dz, cy - dz, dz * 2, dz * 2, COL_DEADZONE)
    draw.SimpleText(pick and "" or "Cancel", UI.Font(15), cx, cy, UI.Colors.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    local w, h = 200 * s, 64 * s
    for _, opt in ipairs(list) do
        local a = math.rad(opt.angle)
        local ox, oy = cx + math.cos(a) * RING * s, cy + math.sin(a) * RING * s
        local isPick = pick == opt
        local empty = opt.count <= 0

        local bg = isPick and COL_PICK or UI.Colors.bg
        draw.RoundedBox(8 * s, ox - w * 0.5, oy - h * 0.5, w, h, bg)
        if isPick then
            surface.SetDrawColor(empty and UI.Colors.bad or UI.Colors.accent)
            surface.DrawOutlinedRect(ox - w * 0.5, oy - h * 0.5, w, h, math.max(1, math.floor(2 * s)))
        end

        local textCol = empty and UI.Colors.textDim or UI.Colors.text
        draw.SimpleText(opt.label, UI.Font(20), ox, oy - 10 * s, textCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(empty and "None left" or (opt.count .. " spare"), UI.Font(15), ox, oy + 13 * s, UI.Colors.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    -- Menu cursor.
    draw.RoundedBox(4 * s, cx + R.cx - 4 * s, cy + R.cy - 4 * s, 8 * s, 8 * s, UI.Colors.text)
end)
