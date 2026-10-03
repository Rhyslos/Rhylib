--[[
    What the skills do (shared, so firing and movement stay predicted).
    Other addons ask these when rhylib_skills is installed; without it
    nothing is gated (every fire mode, scope and item works).

        K.ModeAllowed(ply, wep, mode)    skill-gated fire modes (SWEP.SkillModes)
        K.ScopeAllowed(ply, wep)         SWEP.ScopeSkill
        K.RunAndGun(ply, wep)            fire while sprinting
        K.SpreadMult(ply, wep)           cone multiplier (sprinting, Z-6, pistols)
        K.RecoilMult(ply, wep)           view kick multiplier
        K.FireRateMult(ply, wep, mode)
        K.ReloadMult(ply, wep, cell)     reload time multiplier (server)
        K.MagBonus(ply, magId)           extra rounds per magazine
        K.CellMult(ply)                  power cell shots multiplier
        K.SpinMoveMult(ply, wep, base)   walk speed while the barrels spin
        K.WeightPenaltyMult(ply)         rhylib_stamina weight penalty
        K.AdjustWeight(ply, state, weight, cap)  rhylib_inventory carry
        K.FreeSprint(ply)                Momentum: sprinting costs nothing
        K.JetCfg(ply, key, value)        rhylib_jetpack settings per player (Airborne)
        K.Airborne(ply)                  has any Airborne skill
    Numbers are config "skills" values so they can be tuned without code.
]]

local K = Rhylib.Skills
local Config = Rhylib.Config

local function reg(key, val, desc) Config.Register("skills", key, val, desc) end
reg("quickHandsMult", 0.9, "Quick hands: magazine reload time multiplier")
reg("runGunSpread", 1.6, "Run and gun: spread multiplier while sprinting and firing")
reg("pointBlankMult", 1.25, "Point blank: damage multiplier up close")
reg("pointBlankNear", 420, "Point blank: full bonus within this many units (420 = 8 m)")
reg("pointBlankFar", 790, "Point blank: no bonus beyond this many units (790 = 15 m)")
reg("lightKitSpeed", 1.05, "Light kit: speed multiplier")
reg("lightKitLoad", 0.6, "Light kit: only under this share of your carry limit")
reg("momentumTime", 4, "Momentum: seconds of free sprinting after a kill")
reg("momentumReload", 0.75, "Momentum: next reload time multiplier")
reg("extMagBonus", 10, "Extended mags: extra rounds in a medium magazine")
reg("effCellsMult", 1.25, "Efficient cells: power cell shots multiplier")
reg("loadBearerCarry", 6, "Load bearer: extra carry limit (kg)")
reg("loadBearerPenalty", 0.75, "Load bearer: weight stamina penalty multiplier")
reg("cellRack", { 5, 2 }, "Load bearer: cell rack size in inventory cells (cells are 1x2, so 5x2 = 5 cells)")
reg("gunRunnerSpin", 0.9, "Gun runner: walk speed while the Z-6 spins (normally 0.6)")
reg("gunRunnerWeight", 0.5, "Gun runner: Z-6 weight multiplier")
reg("steadySpread", 0.45, "Steady barrels: Z-6 spread multiplier")
reg("steadyRecoil", 0.45, "Steady barrels: Z-6 view kick multiplier")
reg("rapidFireRPM", 600, "Rapid fire: DC-15S fire rate")
reg("pistolRate", 1.1, "Pistol proficiency: DC-17 fire rate multiplier")
reg("pistolSpread", 0.8, "Pistol proficiency: DC-17 spread multiplier")
reg("dualRate", 1.7, "Dual DC-17: fire rate multiplier")
reg("critChance", 0.1, "Critical hits: chance per hit")
reg("critMult", 1.5, "Critical hits: damage multiplier")
reg("airborneFuel", 15, "Airborne: jetpack seconds of thrust with any Airborne skill (others: jetpack fuelTime)")
reg("fallMult", 0.5, "Hard landings: fall damage multiplier")
reg("tankMult", 1.4, "Extended tanks: fuel time and refill speed multiplier")
reg("springJump", 1.2, "Spring legs: jump power multiplier")
reg("afterburnerMult", 1.25, "Afterburner: jetpack climb, steering and top speed multiplier")
reg("dodgeSpeed", 450, "Thruster dodge: dash speed (units/s)")
reg("dodgeCooldown", 2, "Thruster dodge: seconds between dashes")
reg("dodgeFuel", 0.15, "Thruster dodge: share of a full tank per dash")
reg("dodgeStamina", 20, "Thruster dodge: stamina per dash without a jetpack")
reg("blastMult", 0.7, "Blast hardened: explosion damage multiplier")
reg("airMult", 0.8, "Aerial stability: damage multiplier while off the ground")
reg("slamSpeed", 500, "Death from above: landing speed needed (units/s)")
reg("slamRadius", 220, "Death from above: radius (units)")
reg("slamDamage", 60, "Death from above: damage at the centre (more for faster landings)")
reg("underFireMult", 0.7, "Under fire: damage multiplier while reviving or treating")

local function cfg(k) return Config.Get("skills", k) end

K.Z6 = "rhylib_z6"
K.PISTOLS = { rhylib_dc17 = true, rhylib_dc17_stun = true }

local function isPly(p) return IsValid(p) and p:IsPlayer() end

function K.ModeAllowed(ply, wep, mode)
    local need = wep.SkillModes and wep.SkillModes[mode]
    if not need then return true end
    return isPly(ply) and K.Has(ply, need)
end

function K.ScopeAllowed(ply, wep)
    if not wep.ScopeSkill then return true end
    return isPly(ply) and K.Has(ply, wep.ScopeSkill)
end

function K.RunAndGun(ply, wep)
    return isPly(ply) and K.Has(ply, "run_gun")
end

local function sprinting(ply, wep)
    return wep.OwnerSprinting and wep:OwnerSprinting(ply) or false
end

function K.SpreadMult(ply, wep)
    if not isPly(ply) then return 1 end
    local set = K.Set(ply)
    if next(set) == nil then return 1 end
    local m = 1
    local class = wep:GetClass()
    local steady = class == K.Z6 and set.steady_barrels
    if steady then m = m * cfg("steadySpread") end
    if set.run_gun and not steady and sprinting(ply, wep) then m = m * cfg("runGunSpread") end
    if set.pistol_prof and K.PISTOLS[class] then m = m * cfg("pistolSpread") end
    return m
end

function K.RecoilMult(ply, wep)
    if isPly(ply) and wep:GetClass() == K.Z6 and K.Has(ply, "steady_barrels") then return cfg("steadyRecoil") end
    return 1
end

function K.FireRateMult(ply, wep, mode)
    if not isPly(ply) then return 1 end
    local m = 1
    if K.PISTOLS[wep:GetClass()] and K.Has(ply, "pistol_prof") then m = m * cfg("pistolRate") end
    if wep:GetClass() == "rhylib_dc15s" and wep.FireRate and K.Has(ply, "rapid_fire") then
        m = m * cfg("rapidFireRPM") / wep.FireRate
    end
    if mode == "dual" then m = m * cfg("dualRate") end
    return m
end

function K.ReloadMult(ply, wep, cell)
    if not isPly(ply) then return 1 end
    local m = 1
    if not cell and K.Has(ply, "quick_hands") then m = m * cfg("quickHandsMult") end
    if (ply.rhylibMomentumReload or 0) > CurTime() then
        m = m * cfg("momentumReload")
        ply.rhylibMomentumReload = nil   -- (one reload)
    end
    return m
end

function K.MagBonus(ply, magId)
    if magId == "mag_medium" and isPly(ply) and K.Has(ply, "ext_mags") then return cfg("extMagBonus") end
    return 0
end

function K.CellMult(ply)
    if isPly(ply) and K.Has(ply, "eff_cells") then return cfg("effCellsMult") end
    return 1
end

function K.SpinMoveMult(ply, wep, base)
    if wep:GetClass() == K.Z6 and isPly(ply) and K.Has(ply, "gun_runner") then
        return math.max(base, cfg("gunRunnerSpin"))
    end
    return base
end

function K.WeightPenaltyMult(ply)
    if isPly(ply) and K.Has(ply, "load_bearer") then return cfg("loadBearerPenalty") end
    return 1
end

-- Carry: Load bearer raises the limit; Gun runner halves the Z-6's weight.
-- state is the inventory state ({ cont = { [cid] = { items } } }).
function K.AdjustWeight(ply, state, weight, cap)
    if not isPly(ply) then return weight, cap end
    local set = K.Set(ply)
    if set.load_bearer then cap = cap + cfg("loadBearerCarry") end
    if set.gun_runner then
        local Items = Rhylib.Items
        local def = Items and Items.defs and Items.defs[K.Z6]
        if def and def.weight then
            for cid, c in pairs(state.cont or {}) do
                if cid ~= Items.EXT then
                    for _, o in pairs(c.items) do
                        if o.id == K.Z6 then weight = weight - def.weight * (1 - cfg("gunRunnerWeight")) * (o.count or 1) end
                    end
                end
            end
        end
    end
    return math.max(0, weight), cap
end

function K.FreeSprint(ply)
    return isPly(ply) and ply:GetNW2Float("rhylib_momentum", 0) > CurTime()
end

-- Light kit: a little faster while lightly loaded. Before every limiter
-- (medical legs -90, MP cuffs -95, stamina 0), which only ever lower it.
Rhylib.Hook.Add("SetupMove", "skills.move", function(ply, mv)
    if not K.Has(ply, "light_kit") then return end
    local w = ply:GetNW2Float("rhylib_weight", 0)
    local cap = ply:GetNW2Float("rhylib_carry", 20)
    if cap > 0 and w / cap >= cfg("lightKitLoad") then return end
    local m = cfg("lightKitSpeed")
    mv:SetMaxClientSpeed(mv:GetMaxClientSpeed() * m)
    mv:SetMaxSpeed(mv:GetMaxSpeed() * m)
end, -200)

--------------------------------------------------------------------------
-- Airborne
--------------------------------------------------------------------------

-- Every Airborne skill needs Hard landings, so it marks the path.
function K.Airborne(ply)
    return isPly(ply) and K.Has(ply, "hard_landings")
end

-- rhylib_jetpack asks for these per player and tick.
function K.JetCfg(ply, key, v)
    local set = K.Set(ply)
    if not set.hard_landings then return v end
    if key == "fuelTime" then
        v = math.max(v, cfg("airborneFuel"))
        if set.extended_tanks then v = v * cfg("tankMult") end
    elseif key == "rechargeTime" then
        if set.extended_tanks then v = v / cfg("tankMult") end
    elseif key == "climbSpeed" or key == "airAccel" or key == "maxAirSpeed" then
        if set.afterburner then v = v * cfg("afterburnerMult") end
    end
    return v
end

-- Thruster dodge: Alt + a direction. Predicted; cooldown in DTFloat 25.
local DT_DODGE = 25
Rhylib.Hook.Add("SetupMove", "skills.dodge", function(ply, mv)
    if not mv:KeyPressed(IN_WALK) or not K.Has(ply, "thruster_dodge") then return end
    if not ply:Alive() or ply:GetMoveType() ~= MOVETYPE_WALK or ply:WaterLevel() >= 2 then return end
    local Med = Rhylib.Medical
    if Med and Med.IsDown and (Med.IsDown(ply) or (Med.Dragging and Med.Dragging(ply))) then return end
    if Med and Med.InTank and (Med.InTank(ply) or ply:GetNW2Int("rhylib_medAct", 0) ~= 0) then return end
    if IsValid(ply:GetDTEntity(31)) then return end   -- (on a grapple rope)
    local MP = Rhylib.MP
    if MP and MP.IsCuffed and (MP.IsCuffed(ply) or MP.IsStunned(ply) or MP.EscortedBy(ply)) then return end
    local now = CurTime()
    if ply:GetDTFloat(DT_DODGE) > now then return end
    local f, s = mv:GetForwardSpeed(), mv:GetSideSpeed()
    if f * f + s * s < 1 then return end

    local J = Rhylib.Jetpack
    if J and J.Has and J.Has(ply) then
        local fuel = ply:GetDTFloat(J.DT_FUEL)
        if ply:GetDTBool(J.DT_LOCKED) or fuel < cfg("dodgeFuel") then return end
        ply:SetDTFloat(J.DT_FUEL, fuel - cfg("dodgeFuel"))
    else
        local St = Rhylib.Stamina
        if St and St.Get then
            if St.Get(ply) < cfg("dodgeStamina") then return end
            if SERVER then St.Drain(ply, cfg("dodgeStamina")) end
        end
    end

    local yaw = Angle(0, mv:GetMoveAngles().y, 0)
    local dir = yaw:Forward() * f + yaw:Right() * s
    dir.z = 0
    dir:Normalize()
    local vel = mv:GetVelocity()
    local speed = cfg("dodgeSpeed")
    vel.x, vel.y = dir.x * speed, dir.y * speed
    if ply:OnGround() then
        vel.z = math.max(vel.z, 160)   -- a hop (over 140 leaves the ground), so friction doesn't eat it
        ply:SetGroundEntity(NULL)
    end
    mv:SetVelocity(vel)
    ply:SetDTFloat(DT_DODGE, now + cfg("dodgeCooldown"))
    if SERVER then ply:EmitSound("ambient/machines/thumper_dust.wav", 60, 140, 0.5) end
end, -150)
