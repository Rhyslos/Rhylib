--[[
    Med bay, server: the bacta tank, the chemistry bench, and saving
    their placements per map (rhylib_medical_save).

    Bacta tank: Med.TankUse(tank, ply) from the entity. The occupant is
    held inside (MOVETYPE_NONE) and Med.TankTick heals them twice a
    second. Out on Jump / E, when fully healed, downed, dead or gone.

    Chemistry bench: Med.BenchUse(bench, ply) sends chem.open (the bench)
    to a Chemist; chem.make (bench, recipe index 5 bits) starts a batch
    of craftTime seconds. Supplies are taken at the end; walking away
    stops it. Batch brewing makes two. Items made from issued supplies
    are issued too.
]]

local Med = Rhylib.Medical
local function cfg(k) return Med.Cfg(k) end

Rhylib.Net.Register("chem.open")

--------------------------------------------------------------------------
-- Bacta tank
--------------------------------------------------------------------------

local function inside(tank)
    local mins, maxs = tank:OBBMins(), tank:OBBMaxs()
    return tank:LocalToWorld(Vector((mins.x + maxs.x) * 0.5, (mins.y + maxs.y) * 0.5, mins.z + 2))
end

-- A free spot next to the tank, front first.
local function outside(tank, ply)
    local mins, maxs = ply:GetHull()
    local r = math.max(tank:OBBMaxs().x - tank:OBBMins().x, tank:OBBMaxs().y - tank:OBBMins().y) * 0.5 + 24
    local base = tank:GetPos() + Vector(0, 0, 4)
    local dirs = { tank:GetForward(), tank:GetRight(), -tank:GetRight(), -tank:GetForward() }
    for _, d in ipairs(dirs) do
        local p = base + d * r
        local tr = util.TraceHull({ start = p, endpos = p, mins = mins, maxs = maxs, filter = { ply, tank }, mask = MASK_PLAYERSOLID })
        if not tr.StartSolid then return p end
    end
    return base + dirs[1] * r
end

function Med.TankExit(ply, why)
    if not IsValid(ply) then return end
    local tank = ply.rhylibTank
    ply.rhylibTank, ply.rhylibTankTime = nil, nil
    ply.rhylibTankLeft = CurTime()
    ply:SetNW2Entity("rhylib_tank", NULL)
    if IsValid(tank) and tank:GetOccupant() == ply then tank:SetOccupant(NULL) end
    if ply:Alive() and ply:GetMoveType() == MOVETYPE_NONE then
        ply:SetMoveType(MOVETYPE_WALK)
        if IsValid(tank) then ply:SetPos(outside(tank, ply)) end
    end
    if why then Med.Note(ply, why) end
end

function Med.TankEnter(tank, ply)
    if not ply:Alive() or ply.rhylibDown or Med.Dragging(ply) or Med.DraggedBy(ply) then return end
    local MP = Rhylib.MP
    if MP and MP.IsCuffed and (MP.IsCuffed(ply) or MP.IsStunned(ply)) then return end
    if ply:GetMoveType() ~= MOVETYPE_WALK then return end
    if ply:Health() >= ply:GetMaxHealth() and not (Med.inj and Med.inj[ply]) then
        return Med.Note(ply, "You don't need the tank")
    end
    Med.Cancel(ply)
    ply.rhylibTank = tank
    ply.rhylibTankIn = CurTime()
    ply.rhylibTankTime = 0
    ply:SetNW2Entity("rhylib_tank", tank)
    tank:SetOccupant(ply)
    ply:SetMoveType(MOVETYPE_NONE)
    ply:SetLocalVelocity(Vector(0, 0, 0))
    ply:SetPos(inside(tank))
    ply:SetEyeAngles(Angle(0, tank:GetAngles().y, 0))
    tank:EmitSound("ambient/water/water_splash" .. math.random(1, 3) .. ".wav", 65)
end

function Med.TankUse(tank, ply)
    if ply.rhylibTank == tank then return Med.TankExit(ply) end
    if CurTime() - (ply.rhylibTankLeft or 0) < 0.6 then return end   -- (the E that just let them out)
    local o = tank:GetOccupant()
    if IsValid(o) and o.rhylibTank == tank then
        return Med.Note(ply, o:Nick() .. " is in the tank")
    end
    Med.TankEnter(tank, ply)
end

-- A Chemist with Bacta specialist near the tank doubles the rate.
local function specialistNear(tank)
    local r = cfg("tankSpecialist")
    local pos = tank:GetPos()
    for _, p in ipairs(player.GetAll()) do
        if p:Alive() and not p.rhylibDown and p:GetPos():DistToSqr(pos) <= r * r and Med.Skill(p, "bacta_specialist") then
            return true
        end
    end
    return false
end

timer.Create("Rhylib.Medical.Tanks", 0.5, 0, function()
    for _, ply in ipairs(player.GetAll()) do
        local tank = ply.rhylibTank
        if tank then
            -- (moved out by something else, e.g. an admin teleport or noclip: let them go)
            if not IsValid(tank) or not ply:Alive() or ply.rhylibDown or tank:GetOccupant() ~= ply
                or ply:GetMoveType() ~= MOVETYPE_NONE or ply:GetPos():DistToSqr(inside(tank)) > 32 * 32 then
                Med.TankExit(ply)
            else
                if Med.TankTick(ply, 0.5, specialistNear(tank) and 2 or 1) then
                    Med.TankExit(ply, "Fully healed")
                    ply:EmitSound("items/medshot4.wav", 60)
                end
            end
        end
    end
end)

Rhylib.Hook.Add("KeyPress", "medical.tank", function(ply, key)
    if ply.rhylibTank and (key == IN_JUMP or key == IN_USE) and CurTime() - (ply.rhylibTankIn or 0) > 0.6 then
        Med.TankExit(ply)
    end
end)

local function clearTank(ply) if ply.rhylibTank then Med.TankExit(ply) end end
Rhylib.Hook.Add("PlayerDeath", "medical.tank", clearTank)
Rhylib.Hook.Add("PlayerSilentDeath", "medical.tank", clearTank)
Rhylib.Hook.Add("PlayerSpawn", "medical.tank", clearTank)
Rhylib.Hook.Add("PlayerDisconnected", "medical.tank", clearTank)
Rhylib.Hook.Add("Rhylib.PlayerDowned", "medical.tank", clearTank)

--------------------------------------------------------------------------
-- Chemistry bench
--------------------------------------------------------------------------

Med.crafting = Med.crafting or {}   -- [ply] = { bench, item, cost, endT }
local crafting = Med.crafting
local BENCH_RANGE = 150

local function setCraft(ply, c)
    ply:SetNW2Float("rhylib_craftS", c and CurTime() or 0)
    ply:SetNW2Float("rhylib_craftE", c and c.endT or 0)
    ply:SetNW2String("rhylib_craftN", c and c.name or "")
end

local function inventory()
    local Inv = Rhylib.Inventory
    return Inv and Inv.Count and Inv.Remove and Inv.AddOrDrop and Inv or nil
end

local function near(ply, bench)
    return IsValid(bench) and ply:GetPos():DistToSqr(bench:GetPos()) <= BENCH_RANGE * BENCH_RANGE
end

function Med.BenchUse(bench, ply)
    if not ply:Alive() or ply.rhylibDown then return end
    if not Med.Skill(ply, "chem_bench") then
        return Med.Note(ply, Med.IsMedic(ply) and "You need the Chemistry skill (Medic > Chemist)" or "Only a Chemist medic knows how to use this")
    end
    if not inventory() then return Med.Note(ply, "The bench needs rhylib_inventory") end
    if crafting[ply] then return Med.Note(ply, "Already mixing something") end
    Rhylib.Net.Start("chem.open")
    net.WriteEntity(bench)
    net.Send(ply)
end

-- Take n of id from the inventory, unissued stacks first. Returns
-- false (taking nothing) if short, else true and whether any was issued.
local function takeN(Inv, ply, id, n)
    if Inv.Count(ply, id) < n then return false end
    local list = {}
    for uid, o in pairs(Inv.Get(ply).byUid) do
        if o.id == id then list[#list + 1] = { uid, o.count, o.data and o.data.issued and true or false } end
    end
    table.sort(list, function(a, b) return (a[3] and 1 or 0) < (b[3] and 1 or 0) end)
    local issued = false
    for _, e in ipairs(list) do
        if n <= 0 then break end
        local take = math.min(n, e[2])
        Inv.Remove(ply, e[1], take)
        n = n - take
        if e[3] then issued = true end
    end
    return true, issued
end

Rhylib.Net.Receive("chem.make", function(ply)
    local bench = net.ReadEntity()
    local r = (cfg("chemRecipes") or {})[net.ReadUInt(5)]
    local Inv = inventory()
    if not (Inv and istable(r) and isstring(r[1]) and IsValid(bench) and bench:GetClass() == "rhylib_chem_bench") then return end
    if not ply:Alive() or ply.rhylibDown or crafting[ply] or not near(ply, bench) then return end
    if not Med.Skill(ply, "chem_bench") then return end
    local def = Rhylib.Items and Rhylib.Items.Get(r[1])
    if not def then return Med.Note(ply, "Unknown item " .. r[1]) end
    local cost = math.max(0, math.floor(tonumber(r[2]) or 1))
    if Inv.Count(ply, Med.SUPPLIES) < cost then
        return Med.Note(ply, "Needs " .. cost .. " medical suppl" .. (cost == 1 and "y" or "ies"))
    end
    local c = { bench = bench, item = r[1], cost = cost, name = def.name, endT = CurTime() + cfg("craftTime") }
    crafting[ply] = c
    setCraft(ply, c)
    bench:EmitSound("ambient/levels/canals/toxic_slime_gurgle" .. math.random(2, 4) .. ".wav", 60)
end, { rate = 2, burst = 3 })

local function stopCraft(ply, why)
    crafting[ply] = nil
    if IsValid(ply) then
        setCraft(ply, nil)
        if why then Med.Note(ply, why) end
    end
end

timer.Create("Rhylib.Medical.Craft", 0.2, 0, function()
    if next(crafting) == nil then return end
    local now = CurTime()
    for ply, c in pairs(crafting) do
        if not IsValid(ply) then
            crafting[ply] = nil
        elseif not ply:Alive() or ply.rhylibDown or not near(ply, c.bench) then
            stopCraft(ply, "Stopped mixing")
        elseif now >= c.endT then
            local Inv = inventory()
            local ok, issued = false, false
            if Inv then ok, issued = takeN(Inv, ply, Med.SUPPLIES, c.cost) end
            if not ok then
                stopCraft(ply, "Not enough medical supplies")
            else
                local n = Med.Skill(ply, "batch_brewing") and 2 or 1
                -- Made from issued supplies: issued too (hands back like other issued gear).
                Inv.AddOrDrop(ply, c.item, n, issued and { issued = true } or nil)
                stopCraft(ply, "Made " .. c.name .. (n > 1 and (" x" .. n) or ""))
                ply:EmitSound("items/smallmedkit1.wav", 60)
            end
        end
    end
end)

Rhylib.Hook.Add("PlayerDisconnected", "medical.craft", function(ply) crafting[ply] = nil end)

--------------------------------------------------------------------------
-- Placements (bacta tanks and benches stay on the map)
--------------------------------------------------------------------------

local CLASSES = { "rhylib_bacta_tank", "rhylib_chem_bench" }

local function savePlaces()
    local rows = {}
    for _, class in ipairs(CLASSES) do
        for _, e in ipairs(ents.FindByClass(class)) do
            local p, an = e:GetPos(), e:GetAngles()
            rows[#rows + 1] = { class = class, pos = { p.x, p.y, p.z }, ang = { an.p, an.y, an.r } }
        end
    end
    Rhylib.Data.Set("med_places", game.GetMap(), rows)
    return #rows
end

local function loadPlaces()
    local rows = Rhylib.Data.Get("med_places", game.GetMap())
    if not istable(rows) then return end
    for _, class in ipairs(CLASSES) do
        for _, e in ipairs(ents.FindByClass(class)) do e:Remove() end
    end
    for _, r in ipairs(rows) do
        local e = ents.Create(r.class)
        if IsValid(e) then
            e:SetPos(Vector(r.pos[1], r.pos[2], r.pos[3]))
            e:SetAngles(Angle(r.ang[1], r.ang[2], r.ang[3]))
            e:Spawn()
        end
    end
end
Rhylib.Hook.Add("InitPostEntity", "medical.places", function() timer.Simple(1, loadPlaces) end)
Rhylib.Hook.Add("PostCleanupMap", "medical.places", loadPlaces)

Rhylib.Perms.Register("rhylib.medical.admin", "admin", "Save bacta tank and chemistry bench placements")
concommand.Add("rhylib_medical_save", function(ply)
    Rhylib.Perms.Check(ply, "rhylib.medical.admin", function(ok)
        local function reply(m) if IsValid(ply) then ply:ChatPrint(m) else print(m) end end
        if not ok then return reply("You don't have permission for rhylib_medical_save") end
        reply("Saved " .. savePlaces() .. " bacta tanks and chemistry benches for " .. game.GetMap())
    end)
end)
