--[[
    Client bolt visuals. Purely cosmetic: damage is decided on the server.

    Bolts come from two places:
      - your own shots, spawned instantly by the weapon's predicted PrimaryAttack
      - other players' shots, from the batched "wep.shot" message
    Each bolt starts at the muzzle and blends onto its true path within a
    few frames, so it looks right and still ends where the server's bolt does.
]]

local W = Rhylib.Weapons
W.Bolts = W.Bolts or {}
local Bolts = W.Bolts
Bolts.visual = Bolts.visual or {}

-- Looks, by the weapon's BoltColor: colour, trail length, beam width,
-- glow size and how long the visual can live.
local STYLES = {
    [1] = { color = Color(90, 150, 255), length = 70, width = 5, glow = 14, life = 1.2 },   -- Republic blue
    [2] = { color = Color(255, 70, 60), length = 70, width = 5, glow = 14, life = 1.2 },    -- CIS red
    [3] = { color = Color(80, 255, 120), length = 70, width = 5, glow = 14, life = 1.2 },   -- green
    [4] = { color = Color(255, 170, 80), length = 140, width = 9, glow = 40, life = 6, rocket = true },  -- rocket
}

local BLEND_TIME = 0.08

local matBeam = Material("trails/laser")
local matGlow = Material("sprites/light_glow02_add")

local function muzzlePos(shooter, fallback)
    if not IsValid(shooter) then return fallback end

    local firstPerson = shooter == LocalPlayer() and not shooter:ShouldDrawLocalPlayer()
    local active = shooter.GetActiveWeapon and shooter:GetActiveWeapon()
    if IsValid(active) and active.GetPropMuzzle then
        local p = active:GetPropMuzzle(firstPerson)
        if p then return p end
    end

    if firstPerson then
        local vm = shooter:GetViewModel()
        local att = IsValid(vm) and vm:GetAttachment(1)
        return att and att.Pos or fallback
    end

    local wep = shooter.GetActiveWeapon and shooter:GetActiveWeapon()
    if IsValid(wep) then
        local id = wep:LookupAttachment("muzzle")
        local att = id and id > 0 and wep:GetAttachment(id)
        if att then return att.Pos end
    end
    return fallback
end

function Bolts.Spawn(shooter, origin, dir, speed, colorIndex)
    local muzzle = muzzlePos(shooter, origin)
    Bolts.visual[#Bolts.visual + 1] = {
        shooter = shooter,
        pos = origin,
        dir = dir,
        speed = speed,
        style = STYLES[colorIndex] or STYLES[1],
        offset = muzzle - origin,
        born = CurTime(),
        travelled = 0,
    }
end

-- Called by the weapon on the shooter's own client (first prediction only).
function Bolts.FireLocal(owner, weapon, origin, dir)
    Bolts.Spawn(owner, origin, dir, weapon.BoltSpeed, weapon.BoltColor or 1)
end

Rhylib.Net.ReceiveBatch("wep.shot", function()
    return {
        shooter = net.ReadUInt(13),
        origin = net.ReadVector(),
        dir = net.ReadNormal(),
        speed = net.ReadUInt(14),
        color = net.ReadUInt(4),
    }
end, function(s)
    local shooter = Entity(s.shooter)
    -- Your own shots were already drawn by prediction (except in singleplayer).
    if shooter == LocalPlayer() and not game.SinglePlayer() then return end
    Bolts.Spawn(shooter, s.origin, s.dir, s.speed, s.color)
end)

local traceResult = {}
local traceData = { mask = MASK_SHOT, output = traceResult }

local function impact(tr, style)
    if style.rocket then return end  -- the server sends the explosion
    local ed = EffectData()
    ed:SetOrigin(tr.HitPos)
    ed:SetNormal(tr.HitNormal)
    util.Effect("AR2Impact", ed)

    local ent = tr.Entity
    if not (IsValid(ent) and (ent:IsPlayer() or ent:IsNPC())) then
        util.Decal("FadingScorch", tr.HitPos + tr.HitNormal, tr.HitPos - tr.HitNormal)
    end
end

Rhylib.Hook.Add("Think", "weapons.bolts", function()
    local list = Bolts.visual
    if #list == 0 then return end

    local dt = FrameTime()
    local now = CurTime()
    local i = 1
    while i <= #list do
        local b = list[i]
        local remove = not b.style or now - b.born > b.style.life  -- (no style: from before an autorefresh)

        if not remove then
            local step = b.speed * dt
            traceData.start = b.pos
            traceData.endpos = b.pos + b.dir * step
            traceData.filter = IsValid(b.shooter) and b.shooter or nil
            local tr = util.TraceLine(traceData)
            if tr.Hit then
                impact(tr, b.style)
                remove = true
            else
                b.pos = traceData.endpos
                b.travelled = b.travelled + step
            end
        end

        if remove then
            list[i] = list[#list]
            list[#list] = nil
        else
            i = i + 1
        end
    end
end)

Rhylib.Hook.Add("PostDrawTranslucentRenderables", "weapons.bolts", function(depth, skybox)
    if depth or skybox then return end
    local list = Bolts.visual
    if #list == 0 then return end

    local now = CurTime()
    for i = 1, #list do
        local b = list[i]
        local st = b.style
        if st then
            local blend = math.max(0, 1 - (now - b.born) / BLEND_TIME)
            local head = b.pos + b.offset * blend
            local tail = head - b.dir * math.min(st.length, b.travelled + 1)

            render.SetMaterial(matBeam)
            render.DrawBeam(tail, head, st.width, 0, 1, st.color)
            render.SetMaterial(matGlow)
            render.DrawSprite(head, st.glow, st.glow, st.color)
        end
    end
end)
