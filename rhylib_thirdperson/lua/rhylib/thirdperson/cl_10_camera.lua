--[[
    Over-the-shoulder third person (client only, nothing is networked).

    P toggles it, N swaps shoulders, holding right mouse pulls the camera in.
    Console: rhylib_thirdperson 0/1, rhylib_thirdperson_side 1/-1,
             rhylib_thirdperson_key, rhylib_thirdperson_swapkey.

    How bolts land on the crosshair:
      The mouse turns the camera (camAng), not the player. Every frame we
      trace from the camera through the crosshair to find the aim point,
      then turn the player's real eye angles toward that point from the
      eyes and send them in the normal user command. The server just sees
      normal eye angles, so bolts, spread and lag compensation work
      exactly like first person. The trace starts level with the player,
      so walls behind your shoulder are ignored.

      If something is between your gun and the aim point (you can see
      past cover but your gun can't), a small marker shows where the bolt
      will actually hit.
]]

Rhylib.ThirdPerson = Rhylib.ThirdPerson or {}
local TP = Rhylib.ThirdPerson

local enabledVar = CreateClientConVar("rhylib_thirdperson", "0", true, false, "Over-the-shoulder third person (0/1)")
local keyVar = CreateClientConVar("rhylib_thirdperson_key", "p", true, false, "Key that toggles third person")
local swapVar = CreateClientConVar("rhylib_thirdperson_swapkey", "n", true, false, "Key that swaps the shoulder")
local sideVar = CreateClientConVar("rhylib_thirdperson_side", "1", true, false, "1 = right shoulder, -1 = left shoulder")
local crouchVar = CreateClientConVar("rhylib_thirdperson_crouchup", "14", true, false, "How far the camera rises while crouching, so it clears the arms")
local allowedVar = GetConVar("rhylib_thirdperson_allowed")

local sensitivity = GetConVar("sensitivity")
local mYaw = GetConVar("m_yaw")
local mPitch = GetConVar("m_pitch")

-- Camera offsets from the eyes: back, sideways (toward the shoulder), up.
local HIP = { back = 62, side = 20, up = 3 }
local AIM = { back = 30, side = 15, up = 1 }
local HULL = Vector(5, 5, 5)
local FAR = 32768
local MIN_AIM_DIST = 40      -- closer than this, just aim where the camera looks

TP.camAng = nil              -- where the camera looks (driven by the mouse)
TP.camPos = nil              -- last camera position
TP.aimPoint = nil            -- world point under the crosshair
TP.aimFrac = 0               -- 0 hip, 1 aiming (smoothed)
TP.side = sideVar:GetFloat() -- smoothed shoulder side
TP.crouchFrac = 0            -- 0 standing, 1 crouched (smoothed)

function TP.Active()
    local ply = LocalPlayer()
    return enabledVar:GetBool() and allowedVar:GetBool() and IsValid(ply) and ply:Alive()
        and not ply:InVehicle() and ply:GetObserverMode() == OBS_MODE_NONE
end

local function isAiming(ply)
    local wep = ply:GetActiveWeapon()
    return IsValid(wep) and wep.GetAiming and wep:GetAiming() or false
end

--------------------------------------------------------------------------
-- Mouse: turn the camera, not the player
--------------------------------------------------------------------------

-- Runs after the reload menu's handler (priority 10), which takes the
-- mouse while that menu is open.
Rhylib.Hook.Add("InputMouseApply", "thirdperson.mouse", function(cmd, x, y, ang)
    if not TP.Active() then return end
    if not TP.camAng then TP.camAng = Angle(ang.p, ang.y, 0) end

    local scale = sensitivity:GetFloat()
    local wep = LocalPlayer():GetActiveWeapon()
    if IsValid(wep) and wep.AdjustMouseSensitivity then
        scale = scale * (wep:AdjustMouseSensitivity() or 1)
    end

    local a = TP.camAng
    a.p = math.Clamp(a.p + y * scale * mPitch:GetFloat(), -89, 89)
    a.y = math.NormalizeAngle(a.y - x * scale * mYaw:GetFloat())
    return true
end, 10)

--------------------------------------------------------------------------
-- Aim correction
--------------------------------------------------------------------------

local traceResult = {}
local traceData = { mask = MASK_SHOT, output = traceResult }

local function updateAimPoint(ply)
    local eye = ply:EyePos()
    local camPos = TP.camPos or eye
    local dir = TP.camAng:Forward()

    -- Start the trace level with the player, not at the camera.
    local along = math.max((eye - camPos):Dot(dir), 0)
    traceData.start = camPos + dir * along
    traceData.endpos = traceData.start + dir * FAR
    traceData.filter = ply
    util.TraceLine(traceData)
    TP.aimPoint = traceResult.HitPos

    if TP.aimPoint:DistToSqr(eye) < MIN_AIM_DIST * MIN_AIM_DIST then
        return Angle(TP.camAng.p, TP.camAng.y, 0)
    end
    local ang = (TP.aimPoint - eye):Angle()
    ang:Normalize()
    return ang
end

Rhylib.Hook.Add("CreateMove", "thirdperson.aim", function(cmd)
    local ply = LocalPlayer()
    if not TP.Active() then
        -- Just switched off: face where the camera was looking.
        if TP.camAng then
            cmd:SetViewAngles(Angle(TP.camAng.p, TP.camAng.y, 0))
            TP.camAng, TP.camPos, TP.aimPoint = nil, nil, nil
        end
        return
    end
    if not TP.camAng then
        local va = cmd:GetViewAngles()
        TP.camAng = Angle(va.p, va.y, 0)
    end

    local aimAng = updateAimPoint(ply)

    -- Movement stays relative to the camera, not the corrected aim.
    local d = math.rad(TP.camAng.y - aimAng.y)
    local fm, sm = cmd:GetForwardMove(), cmd:GetSideMove()
    local c, s = math.cos(d), math.sin(d)
    cmd:SetForwardMove(fm * c + sm * s)
    cmd:SetSideMove(-fm * s + sm * c)

    cmd:SetViewAngles(aimAng)
end)

--------------------------------------------------------------------------
-- Camera
--------------------------------------------------------------------------

local hullResult = {}
local hullData = { mins = -HULL, maxs = HULL, mask = MASK_SOLID_BRUSHONLY, output = hullResult }

Rhylib.Hook.Add("CalcView", "thirdperson.camera", function(ply, pos, angles, fov)
    if ply ~= LocalPlayer() or not TP.Active() or not TP.camAng then return end

    local ft = FrameTime()
    TP.aimFrac = math.Approach(TP.aimFrac, isAiming(ply) and 1 or 0, ft * 6)
    TP.side = math.Approach(TP.side, sideVar:GetFloat() >= 0 and 1 or -1, ft * 5)

    local f = TP.aimFrac
    local back = Lerp(f, HIP.back, AIM.back)
    local side = Lerp(f, HIP.side, AIM.side) * TP.side
    TP.crouchFrac = math.Approach(TP.crouchFrac, ply:Crouching() and 1 or 0, ft * 5)
    local up = Lerp(f, HIP.up, AIM.up) + TP.crouchFrac * crouchVar:GetFloat()

    local ang = TP.camAng
    local eye = ply:EyePos()
    local want = eye - ang:Forward() * back + ang:Right() * side + ang:Up() * up

    -- Pull the camera in so it never goes through walls.
    hullData.start = eye
    hullData.endpos = want
    hullData.filter = ply
    util.TraceHull(hullData)
    TP.camPos = hullResult.HitPos

    return { origin = TP.camPos, angles = Angle(ang.p, ang.y, 0), fov = fov, drawviewer = true }
end)

-- No floating first-person gun in third person.
Rhylib.Hook.Add("PreDrawViewModel", "thirdperson.hidevm", function()
    if TP.Active() then return true end
end)

--------------------------------------------------------------------------
-- HUD: crosshair and the blocked-shot marker
--------------------------------------------------------------------------

local COL_BLOCK = Color(255, 90, 80)
local COL_BLOCK_OUT = Color(0, 0, 0, 160)

Rhylib.Hook.Add("HUDPaint", "thirdperson.hud", function()
    if not TP.Active() or not TP.aimPoint then return end
    local ply = LocalPlayer()
    local wep = ply:GetActiveWeapon()

    -- Rhylib weapons draw their crosshair here in third person.
    if IsValid(wep) and wep.IsRhylib and Rhylib.Weapons and Rhylib.Weapons.Crosshair
        and not (wep.GetSafety and wep:GetSafety()) then
        Rhylib.Weapons.Crosshair.Draw(wep, ScrW() * 0.5, ScrH() * 0.5)
    end

    -- Is the path from the gun to the aim point blocked?
    local eye = ply:EyePos()
    traceData.start = eye
    traceData.endpos = TP.aimPoint
    traceData.filter = ply
    util.TraceLine(traceData)
    if not traceResult.Hit or traceResult.HitPos:DistToSqr(TP.aimPoint) < 24 * 24 then return end

    local scr = traceResult.HitPos:ToScreen()
    if not scr.visible then return end
    local s = ScrH() / 1080
    local r = 6 * s
    for _, col in ipairs({ COL_BLOCK_OUT, COL_BLOCK }) do
        local w = col == COL_BLOCK_OUT and 3 or 1
        surface.SetDrawColor(col)
        for o = -w + 1, w - 1 do
            surface.DrawLine(scr.x - r, scr.y - r + o, scr.x + r, scr.y + r + o)
            surface.DrawLine(scr.x - r, scr.y + r + o, scr.x + r, scr.y - r + o)
        end
    end
end)

--------------------------------------------------------------------------
-- Keys
--------------------------------------------------------------------------

function TP.Toggle()
    if not allowedVar:GetBool() then
        chat.AddText(Color(255, 190, 80), "Third person is disabled on this server.")
        return
    end
    RunConsoleCommand("rhylib_thirdperson", enabledVar:GetBool() and "0" or "1")
end

function TP.SwapShoulder()
    RunConsoleCommand("rhylib_thirdperson_side", sideVar:GetFloat() >= 0 and "-1" or "1")
end

concommand.Add("rhylib_thirdperson_toggle", TP.Toggle)
concommand.Add("rhylib_thirdperson_swap", TP.SwapShoulder)

local wasDown = {}
local function pressed(var)
    local code = input.GetKeyCode(var:GetString())
    local down = code and code > 0 and input.IsKeyDown(code)
    local edge = down and not wasDown[var]
    wasDown[var] = down
    return edge
end

Rhylib.Hook.Add("Think", "thirdperson.keys", function()
    local toggle, swap = pressed(keyVar), pressed(swapVar)
    if not (toggle or swap) then return end
    if gui.IsGameUIVisible() or gui.IsConsoleVisible() or LocalPlayer():IsTyping() or IsValid(vgui.GetKeyboardFocus()) then return end
    if toggle then TP.Toggle() end
    if swap and TP.Active() then TP.SwapShoulder() end
end)
