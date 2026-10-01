--[[
    Jail (server). Cells and terminals are entities placed by admins and
    saved per map (rhylib_mp_save). An MP at a terminal jails a cuffed
    prisoner who is near it (or whom they're escorting):
      - their items go to evidence (issued gear goes back to the armoury)
      - they're uncuffed and put in the emptiest cell
      - the sentence counts down only while they're online, and survives
        reconnects and map changes (Data "mp_jail" / SteamID64)
      - a prisoner who leaves the cell area is put back
      - on release (time up, or an MP at a terminal) they respawn and get
        their evidence back, minus anything an MP destroyed

    Messages (all checked: MP, near the terminal):
      mp.term     server -> MP  the terminal's lists
      mp.jail     MP -> server  terminal, prisoner, minutes, reason
      mp.release  MP -> server  terminal, prisoner
      mp.destroy  MP -> server  terminal, prisoner, evidence index
]]

local MP = Rhylib.MP
local Data = Rhylib.Data

MP.jailed = MP.jailed or {}   -- [ply] = record { ends, why, by, cell, evidence = { {id,count,data} } }
local jailed = MP.jailed

Rhylib.Net.Register("mp.term")
Rhylib.Perms.Register("rhylib.mp.admin", "admin", "Save jail cell and terminal placements")

local function inv() return Rhylib.Inventory and Rhylib.Inventory.Get and Rhylib.Inventory or nil end
local function sid(ply) return ply:SteamID64() or "0" end

local function save(ply)
    local rec = jailed[ply]
    if not rec then return end
    -- Stored as seconds left, so time only passes while they're online.
    Data.Set("mp_jail", sid(ply), {
        left = math.max(0, rec.ends - CurTime()), why = rec.why, by = rec.by, evidence = rec.evidence,
    })
end

local function cells()
    return ents.FindByClass("rhylib_jail_cell")
end

-- The cell with the fewest prisoners in it.
local function freeCell()
    local list = cells()
    if #list == 0 then return nil end
    local best, bestN
    for _, c in ipairs(list) do
        local n = 0
        for _, rec in pairs(jailed) do
            if rec.cell == c then n = n + 1 end
        end
        if not best or n < bestN then best, bestN = c, n end
    end
    return best
end

local function stripToStowed(ply)
    ply:StripWeapons()
    if weapons.GetStored("rhylib_stowed") then
        ply:Give("rhylib_stowed")
        ply:SelectWeapon("rhylib_stowed")
    end
end

local function putInCell(ply)
    local rec = jailed[ply]
    if not rec then return end
    if not IsValid(rec.cell) then rec.cell = freeCell() end
    if not IsValid(rec.cell) then return end
    ply:SetPos(rec.cell:GetPos() + Vector(0, 0, 4))
    ply:SetEyeAngles(Angle(0, rec.cell:GetAngles().y, 0))
    ply:SetVelocity(-ply:GetVelocity())
end

local function setState(ply)
    local rec = jailed[ply]
    ply:SetNW2Float("rhylib_jailEnd", rec and rec.ends or 0)
    ply:SetNW2String("rhylib_jailWhy", rec and rec.why or "")
end

-- Everything the prisoner carries becomes evidence; issued gear is just removed.
local function confiscate(ply)
    local I = inv()
    if not I then return {} end
    local st = I.Get(ply)
    local list = {}
    for _, o in pairs(st.byUid) do list[#list + 1] = o end
    -- Contents before the backpack itself.
    table.sort(list, function(a, b) return (a.c == 3 and 1 or 0) < (b.c == 3 and 1 or 0) end)
    local evidence = {}
    for _, o in ipairs(list) do
        I.Internal.captureWeapon(ply, o)
        if not (o.data and o.data.issued) then
            evidence[#evidence + 1] = { id = o.id, count = o.count or 1, data = table.Copy(o.data or {}), c = o.c }
        end
        I.Internal.removeInst(ply, st, o.uid)
    end
    return evidence
end

function MP.Jail(ply, by, minutes, why)
    if not IsValid(ply) or jailed[ply] then return false end
    local cell = freeCell()
    if not IsValid(cell) then return false, "No jail cells on this map" end
    minutes = math.Clamp(math.floor(minutes), 1, MP.Cfg("maxSentence"))
    local rec = {
        ends = CurTime() + minutes * 60,
        why = string.sub(why ~= "" and why or "No reason given", 1, 80),
        by = IsValid(by) and by:Nick() or "?",
        cell = cell,
        evidence = confiscate(ply),
    }
    jailed[ply] = rec
    if MP.IsCuffed(ply) then MP.Uncuff(ply) end
    stripToStowed(ply)
    putInCell(ply)
    setState(ply)
    save(ply)
    ply:ChatPrint(string.format("Jailed by %s for %d min: %s", rec.by, minutes, rec.why))
    hook.Run("Rhylib.PlayerJailed", ply, by, minutes, rec.why)
    return true
end

function MP.Release(ply, by)
    local rec = jailed[ply]
    if not rec then return end
    jailed[ply] = nil
    -- Evidence back first (backpack before its contents), so the spawn hands out the guns.
    local I = inv()
    if I then
        local ev = rec.evidence or {}
        local order = {}
        for i = 1, #ev do order[i] = ev[i] end
        table.sort(order, function(a, b) return (a.c == 3 and 0 or 1) < (b.c == 3 and 0 or 1) end)
        for _, e in ipairs(order) do I.AddOrDrop(ply, e.id, e.count, e.data) end
        if I.Save then I.Save(ply) end
    end
    Data.Delete("mp_jail", sid(ply))
    setState(ply)
    ply:Spawn()
    ply:ChatPrint(IsValid(by) and ("Released by " .. by:Nick()) or "Your sentence is over")
    hook.Run("Rhylib.PlayerReleased", ply, by)
end

-- Time up, or wandered off.
timer.Create("Rhylib.MP.Jail", 1, 0, function()
    if next(jailed) == nil then return end
    local now = CurTime()
    local r = MP.Cfg("jailRadius")
    for ply, rec in pairs(jailed) do
        if not IsValid(ply) then
            jailed[ply] = nil
        elseif now >= rec.ends then
            MP.Release(ply)
        elseif ply:Alive() and IsValid(rec.cell) and ply:GetPos():DistToSqr(rec.cell:GetPos()) > r * r then
            putInCell(ply)
        end
    end
end)

-- Respawning while jailed: back in the cell, no weapons.
Rhylib.Hook.Add("PlayerSpawn", "mp.jail", function(ply)
    if not jailed[ply] then return end
    timer.Simple(0, function()
        if IsValid(ply) and jailed[ply] then
            stripToStowed(ply)
            putInCell(ply)
        end
    end)
end, 50)

Rhylib.Hook.Add("PlayerLoadout", "mp.jail", function(ply)
    if jailed[ply] then return true end  -- no job weapons in jail
end)

-- Rejoining: pick the sentence back up (or hand back evidence if it's over).
Rhylib.Hook.Add("PlayerInitialSpawn", "mp.jail", function(ply)
    local rec = Data.Get("mp_jail", sid(ply))
    if not istable(rec) then return end
    if (rec.left or 0) > 0 then
        jailed[ply] = { ends = CurTime() + rec.left, why = rec.why or "", by = rec.by or "?", evidence = rec.evidence or {} }
        setState(ply)
    else
        Data.Delete("mp_jail", sid(ply))
    end
end)

Rhylib.Hook.Add("PlayerDisconnected", "mp.jail", function(ply)
    if jailed[ply] then
        save(ply)
        jailed[ply] = nil
    end
end)

Rhylib.Hook.Add("ShutDown", "mp.jail", function()
    for ply in pairs(jailed) do
        if IsValid(ply) then save(ply) end
    end
end, -10)  -- before Data flushes at 0

Rhylib.Hook.Add("playerCanChangeTeam", "mp.jailjob", function(ply)
    if jailed[ply] then return false, "You can't change job in jail" end
end)

--------------------------------------------------------------------------
-- Terminal
--------------------------------------------------------------------------

local function nearTerminal(ply, term)
    return IsValid(term) and term:GetClass() == "rhylib_jail_terminal" and ply:GetPos():DistToSqr(term:GetPos()) <= MP.TERM_USE * MP.TERM_USE
end

-- Cuffed players near the terminal, or escorted by this MP.
local function candidates(mp, term)
    local out = {}
    local r = MP.Cfg("terminalRange")
    for _, p in ipairs(player.GetAll()) do
        if p ~= mp and MP.IsCuffed(p) and not jailed[p]
            and (MP.EscortedBy(p) == mp or p:GetPos():DistToSqr(term:GetPos()) <= r * r) then
            out[#out + 1] = p
        end
    end
    return out
end

function MP.OpenTerminal(mp, term)
    if not MP.IsMP(mp) then
        mp:PrintMessage(HUD_PRINTCENTER, "Military police only")
        return
    end
    local Items = Rhylib.Items
    local cand = candidates(mp, term)
    Rhylib.Net.Start("mp.term")
    net.WriteEntity(term)
    net.WriteUInt(math.min(#cand, 31), 5)
    for i = 1, math.min(#cand, 31) do net.WriteEntity(cand[i]) end
    local list = {}
    for p in pairs(jailed) do if IsValid(p) then list[#list + 1] = p end end
    net.WriteUInt(math.min(#list, 63), 6)
    for i = 1, math.min(#list, 63) do
        local p = list[i]
        local rec = jailed[p]
        net.WriteEntity(p)
        net.WriteString(rec.why)
        local ev = rec.evidence or {}
        net.WriteUInt(math.min(#ev, 63), 6)
        for j = 1, math.min(#ev, 63) do
            net.WriteUInt(Items and Items.NetId(ev[j].id) or 0, Items and Items.NET_BITS or 10)
            net.WriteUInt(math.Clamp(ev[j].count or 1, 0, 255), 8)
        end
    end
    net.Send(mp)
end

Rhylib.Net.Receive("mp.jail", function(mp)
    local term, p = net.ReadEntity(), net.ReadEntity()
    local minutes = net.ReadUInt(7)
    local why = string.Trim(net.ReadString())
    if not MP.IsMP(mp) or not nearTerminal(mp, term) or not IsValid(p) or not p:IsPlayer() then return end
    local ok = false
    for _, c in ipairs(candidates(mp, term)) do
        if c == p then ok = true break end
    end
    if not ok then
        mp:ChatPrint("They need to be cuffed and at the terminal")
        return
    end
    local done, err = MP.Jail(p, mp, minutes, why)
    if not done and err then mp:ChatPrint(err) end
    MP.OpenTerminal(mp, term)
end, { rate = 2, burst = 3 })

Rhylib.Net.Receive("mp.release", function(mp)
    local term, p = net.ReadEntity(), net.ReadEntity()
    if not MP.IsMP(mp) or not nearTerminal(mp, term) or not IsValid(p) or not jailed[p] then return end
    MP.Release(p, mp)
    MP.OpenTerminal(mp, term)
end, { rate = 2, burst = 3 })

Rhylib.Net.Receive("mp.destroy", function(mp)
    local term, p = net.ReadEntity(), net.ReadEntity()
    local i = net.ReadUInt(6)
    local netId = net.ReadUInt(Rhylib.Items and Rhylib.Items.NET_BITS or 10)
    local count = net.ReadUInt(8)
    if not MP.IsMP(mp) or not nearTerminal(mp, term) or not IsValid(p) then return end
    local rec = jailed[p]
    local e = rec and rec.evidence and rec.evidence[i]
    if not e then return end
    -- The list may have changed since the MP's window was filled.
    local Items = Rhylib.Items
    if (Items and Items.NetId(e.id) or 0) ~= netId or math.min(e.count or 1, 255) ~= count then
        MP.OpenTerminal(mp, term)
        return
    end
    table.remove(rec.evidence, i)
    save(p)
    MP.OpenTerminal(mp, term)
end, { rate = 6, burst = 6 })

--------------------------------------------------------------------------
-- Placements
--------------------------------------------------------------------------

local CLASSES = { "rhylib_jail_cell", "rhylib_jail_terminal" }

concommand.Add("rhylib_mp_save", function(ply)
    Rhylib.Perms.Check(ply, "rhylib.mp.admin", function(ok)
        if not ok then
            if IsValid(ply) then ply:ChatPrint("You don't have permission for rhylib_mp_save") end
            return
        end
        local list = {}
        for _, class in ipairs(CLASSES) do
            for _, e in ipairs(ents.FindByClass(class)) do
                local pos, ang = e:GetPos(), e:GetAngles()
                list[#list + 1] = { class = class, pos = { pos.x, pos.y, pos.z }, ang = { ang.p, ang.y, ang.r } }
            end
        end
        Data.Set("mp_places", game.GetMap(), list)
        local msg = "Saved " .. #list .. " jail cells and terminals for " .. game.GetMap()
        if IsValid(ply) then ply:ChatPrint(msg) else print(msg) end
    end)
end)

local function loadPlaces()
    local list = Data.Get("mp_places", game.GetMap())
    if not istable(list) then return end
    for _, class in ipairs(CLASSES) do
        for _, e in ipairs(ents.FindByClass(class)) do e:Remove() end
    end
    for _, it in ipairs(list) do
        local e = ents.Create(it.class)
        if IsValid(e) then
            e:SetPos(Vector(it.pos[1], it.pos[2], it.pos[3]))
            e:SetAngles(Angle(it.ang[1], it.ang[2], it.ang[3]))
            e:Spawn()
            local phys = e:GetPhysicsObject()
            if IsValid(phys) then phys:EnableMotion(false) end
        end
    end
end
Rhylib.Hook.Add("InitPostEntity", "mp.places", loadPlaces)
Rhylib.Hook.Add("PostCleanupMap", "mp.places", loadPlaces)
