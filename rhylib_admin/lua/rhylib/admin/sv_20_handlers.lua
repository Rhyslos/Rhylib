--[[
    What each admin command does (Admin.handlers[id]), plus the powers
    behind them:
      noclip      the noclip key works for staff with "noclip" / "noclip.self"
      god         FL_GODMODE (ply:GodEnable)
      cloak       invisible: no model, weapon, shadow; NW2Bool rhylib_cloak
                  (the HUD hides the name); also no target
      notarget    FL_NOTARGET (NPCs and Rhylib droids ignore them; rhylib_medical
                  keeps it while downed, see ply.rhylibAdminNoTarget)
      spawn       spawn menu rights (props, entities, NPCs, weapons, vehicles,
                  ragdolls, effects, tools) whatever DarkRP / sandbox say
      freeze, mute (text), gag (voice): session only
    Spawned things are remembered per player (ent.rhylibSpawner) for cleanup.
    Handlers return the text to echo and log, or nil, "error for the caller".
]]

local Admin = Rhylib.Admin
local H = Admin.handlers

Admin.muted = Admin.muted or {}    -- [ply] = true
Admin.gagged = Admin.gagged or {}  -- [ply] = true
Admin.returnPos = Admin.returnPos or {}   -- [ply] = Vector

local function name(p) return IsValid(p) and p:Nick() or "Console" end
local function you(caller, t) return caller == t and "themselves" or name(t) end

--------------------------------------------------------------------------
-- Powers
--------------------------------------------------------------------------

function Admin.SetCloak(ply, on)
    ply.rhylibCloak = on or nil
    ply:SetNW2Bool("rhylib_cloak", on)
    -- A lying player (rhylib_core) is already hidden under their body; leave that be.
    if not ply.rhylibLieHidden then
        ply:SetNoDraw(on)
        ply:DrawShadow(not on)
        ply:DrawWorldModel(not on)
    end
    ply:SetRenderMode(on and RENDERMODE_TRANSALPHA or RENDERMODE_NORMAL)
    Admin.SetNoTarget(ply, on or ply.rhylibAdminNoTargetOwn)
end

function Admin.SetNoTarget(ply, on)
    ply.rhylibAdminNoTarget = on or nil
    if on then
        ply:AddFlags(FL_NOTARGET)
    elseif not (Rhylib.Medical and Rhylib.Medical.IsDown(ply) and Rhylib.Medical.Cfg("noTarget")) then
        ply:RemoveFlags(FL_NOTARGET)   -- (downed players keep it, rhylib_medical)
    end
end

-- Spawn menu rights for staff with "spawn" (others: sandbox / DarkRP rules).
local function canSpawn(ply)
    if Admin.Has(ply, "spawn") then return true end
end
for _, h in ipairs({ "PlayerSpawnProp", "PlayerSpawnSENT", "PlayerSpawnNPC", "PlayerSpawnSWEP", "PlayerGiveSWEP",
    "PlayerSpawnVehicle", "PlayerSpawnRagdoll", "PlayerSpawnEffect", "PlayerSpawnObject" }) do
    Rhylib.Hook.Add(h, "admin.spawn", canSpawn, -50)
end
-- Tools on the world only; on entities prop protection decides.
Rhylib.Hook.Add("CanTool", "admin.spawn", function(ply, tr, tool)
    if IsValid(tr.Entity) then return end
    if Admin.Has(ply, "spawn") then return true end
end, -40)

-- Remember who spawned what (cleanup).
local function remember(ply, ent)
    if IsValid(ent) then ent.rhylibSpawner = ply end
end
Rhylib.Hook.Add("PlayerSpawnedProp", "admin.track", function(ply, _, ent) remember(ply, ent) end)
Rhylib.Hook.Add("PlayerSpawnedSENT", "admin.track", remember)
Rhylib.Hook.Add("PlayerSpawnedNPC", "admin.track", remember)
Rhylib.Hook.Add("PlayerSpawnedVehicle", "admin.track", remember)
Rhylib.Hook.Add("PlayerSpawnedRagdoll", "admin.track", function(ply, _, ent) remember(ply, ent) end)
Rhylib.Hook.Add("PlayerSpawnedEffect", "admin.track", function(ply, _, ent) remember(ply, ent) end)
Rhylib.Hook.Add("PlayerSpawnedSWEP", "admin.track", remember)

-- Voice and frozen players.
Rhylib.Hook.Add("PlayerCanHearPlayersVoice", "admin.gag", function(listener, talker)
    if Admin.gagged[talker] then return false, false end
end, -50)

-- The Rhylib chat box asks this before sending (rhylib_chat).
Rhylib.Hook.Add("Rhylib.CanChat", "admin.mute", function(ply)
    if Admin.muted[ply] then return false, "You are muted" end
end)

-- Spawning again keeps powers that should last (cloak, god, notarget).
Rhylib.Hook.Add("PlayerSpawn", "admin.powers", function(ply)
    timer.Simple(0, function()
        if not IsValid(ply) then return end
        if ply.rhylibCloak then Admin.SetCloak(ply, true) end
        if ply.rhylibGod then ply:GodEnable() end
        if ply.rhylibAdminNoTarget then ply:AddFlags(FL_NOTARGET) end
        if ply.rhylibFrozen then ply:Freeze(true) end
    end)
end)

Rhylib.Hook.Add("PlayerDisconnected", "admin.clear", function(ply)
    Admin.muted[ply], Admin.gagged[ply], Admin.returnPos[ply] = nil, nil, nil
end)

--------------------------------------------------------------------------
-- Teleport helpers
--------------------------------------------------------------------------

-- A free standing spot near pos (tries a ring around it).
local function freeSpot(pos, who)
    local mins, maxs = Vector(-16, -16, 0), Vector(16, 16, 72)
    local tries = { Vector(0, 0, 0) }
    for i = 0, 7 do
        local a = i * math.pi / 4
        tries[#tries + 1] = Vector(math.cos(a) * 48, math.sin(a) * 48, 0)
        tries[#tries + 1] = Vector(math.cos(a) * 90, math.sin(a) * 90, 0)
    end
    for _, off in ipairs(tries) do
        local p = pos + off + Vector(0, 0, 4)
        local tr = util.TraceHull({ start = p, endpos = p, mins = mins, maxs = maxs, filter = who, mask = MASK_PLAYERSOLID })
        if not tr.StartSolid then return p end
    end
    return pos + Vector(0, 0, 8)
end

local function moveTo(ply, pos)
    Admin.returnPos[ply] = ply:GetPos()
    if ply:InVehicle() then ply:ExitVehicle() end
    ply:SetPos(pos)
    ply:SetLocalVelocity(Vector(0, 0, 0))
end

--------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------

H.kick = function(caller, t, a)
    local reason = a.reason ~= "" and a.reason or "Kicked by staff"
    local text = name(caller) .. " kicked " .. name(t) .. " (" .. reason .. ")"
    t:Kick(reason)
    return text
end

H.ban = function(caller, t, a, ctx)
    local minutes = a.time
    local max = Admin.Cfg("banMaxMinutes")
    if not IsValid(t) and not Admin.Has(caller, "banid") then return nil, "Banning someone who isn't online needs the banid permission" end
    if (minutes == 0 or minutes > max) and not Admin.Has(caller, "permaban") then
        return nil, "You can ban for at most " .. Admin.FormatMinutes(max)
    end
    local who = IsValid(t) and t:Nick() or ctx.sid
    Admin.Ban(ctx.sid, minutes, a.reason, caller, who)
    return name(caller) .. " banned " .. who .. " " .. Admin.FormatMinutes(minutes) .. " (" .. (a.reason ~= "" and a.reason or "no reason given") .. ")"
end

H.unban = function(caller, t, a, ctx)
    if not Admin.Unban(ctx.sid) then return nil, ctx.sid .. " isn't banned" end
    return name(caller) .. " unbanned " .. ctx.sid
end

H.warn = function(caller, t, a)
    if a.reason == "" then return nil, "Give a reason" end
    local n = Admin.Warn(t:SteamID64(), a.reason, name(caller))
    Admin.Tell(t, "Warning from " .. name(caller) .. ": " .. a.reason, true)
    return name(caller) .. " warned " .. name(t) .. " (" .. a.reason .. "); " .. n .. " warning" .. (n == 1 and "" or "s") .. " total"
end

H.mute = function(caller, t)
    Admin.muted[t] = true
    return name(caller) .. " muted " .. name(t)
end
H.unmute = function(caller, t)
    Admin.muted[t] = nil
    return name(caller) .. " unmuted " .. name(t)
end
H.gag = function(caller, t)
    Admin.gagged[t] = true
    return name(caller) .. " gagged " .. name(t)
end
H.ungag = function(caller, t)
    Admin.gagged[t] = nil
    return name(caller) .. " ungagged " .. name(t)
end

H.freeze = function(caller, t)
    t.rhylibFrozen = true
    t:Freeze(true)
    return name(caller) .. " froze " .. you(caller, t)
end
H.unfreeze = function(caller, t)
    t.rhylibFrozen = nil
    t:Freeze(false)
    return name(caller) .. " unfroze " .. you(caller, t)
end

H.slay = function(caller, t)
    if not t:Alive() then return nil, name(t) .. " is already dead" end
    t:Kill()
    return name(caller) .. " slew " .. you(caller, t)
end

H.respawn = function(caller, t)
    t:Spawn()
    return name(caller) .. " respawned " .. you(caller, t)
end

H["goto"] = function(caller, t)
    if not IsValid(caller) then return nil, "The console can't go anywhere" end
    if caller == t then return nil, "That's you" end
    moveTo(caller, freeSpot(t:GetPos() - t:GetForward() * 48, { caller, t }))
    return name(caller) .. " went to " .. name(t)
end

H.bring = function(caller, t)
    if not IsValid(caller) then return nil, "The console has nowhere to bring them" end
    if caller == t then return nil, "That's you" end
    moveTo(t, freeSpot(caller:GetPos() + caller:GetForward() * 64, { caller, t }))
    return name(caller) .. " brought " .. name(t)
end

H["return"] = function(caller, t)
    local pos = Admin.returnPos[t]
    if not pos then return nil, name(t) .. " has nowhere to return to" end
    t:SetPos(pos)
    Admin.returnPos[t] = nil
    return name(caller) .. " returned " .. you(caller, t)
end

H.teleport = function(caller, t)
    if not IsValid(caller) then return nil, "The console can't aim" end
    local tr = util.TraceLine({ start = caller:EyePos(), endpos = caller:EyePos() + caller:GetAimVector() * 32768, filter = { caller, t }, mask = MASK_PLAYERSOLID })
    if not tr.Hit then return nil, "Aim at something" end
    moveTo(t, freeSpot(tr.HitPos + tr.HitNormal * 16, { caller, t }))
    return name(caller) .. " teleported " .. you(caller, t)
end

-- Toggles: on yourself only needs .self-style rights through the command perm.
H.noclip = function(caller, t)
    local on = t:GetMoveType() ~= MOVETYPE_NOCLIP
    t:SetMoveType(on and MOVETYPE_NOCLIP or MOVETYPE_WALK)
    return name(caller) .. (on and " gave noclip to " or " took noclip from ") .. you(caller, t)
end

H.god = function(caller, t)
    local on = not t.rhylibGod
    t.rhylibGod = on or nil
    if on then t:GodEnable() else t:GodDisable() end
    return name(caller) .. (on and " enabled" or " disabled") .. " god mode for " .. you(caller, t)
end

H.cloak = function(caller, t)
    local on = not t.rhylibCloak
    Admin.SetCloak(t, on)
    return name(caller) .. (on and " made " or " unhid ") .. you(caller, t) .. (on and " invisible" or "")
end

H.notarget = function(caller, t)
    local on = not t.rhylibAdminNoTargetOwn
    t.rhylibAdminNoTargetOwn = on or nil
    Admin.SetNoTarget(t, on or t.rhylibCloak)
    return name(caller) .. (on and " turned on" or " turned off") .. " no target for " .. you(caller, t)
end

H.hp = function(caller, t, a)
    local n = math.Clamp(math.floor(a.amount), 1, 100000)
    if not t:Alive() then return nil, name(t) .. " is dead" end
    if n > t:GetMaxHealth() then t:SetMaxHealth(n) end
    t:SetHealth(n)
    return name(caller) .. " set the health of " .. you(caller, t) .. " to " .. n
end

H.armor = function(caller, t, a)
    local n = math.Clamp(math.floor(a.amount), 0, 100000)
    if n > t:GetMaxArmor() then t:SetMaxArmor(n) end
    t:SetArmor(n)
    return name(caller) .. " set the armour of " .. you(caller, t) .. " to " .. n
end

H.give = function(caller, t, a)
    local class = string.lower(a.class or "")
    if not weapons.GetStored(class) and not list.Get("Weapon")[class] then return nil, "No weapon called " .. class end
    t:Give(class)
    return name(caller) .. " gave " .. class .. " to " .. you(caller, t)
end

-- Staff ranks: only below your own, and only on people below you.
H.rank = function(caller, t, a, ctx)
    local r = Admin.RankById(string.lower(a.rank or ""))
    if not r then
        local ids = {}
        for _, x in ipairs(Admin.Ranks()) do ids[#ids + 1] = x.id end
        return nil, "No rank " .. tostring(a.rank) .. " (" .. table.concat(ids, ", ") .. ")"
    end
    if IsValid(caller) and (r.level or 0) >= Admin.Level(caller) then return nil, "You can only give ranks below your own" end
    Admin.SetRank(ctx.sid, r.id, name(caller))
    return name(caller) .. " set the staff rank of " .. (IsValid(t) and t:Nick() or ctx.sid) .. " to " .. r.name
end

-- Roster (rhylib_roster).
local function roster() return Rhylib.Roster end
local function who(t, ctx) return IsValid(t) and t:Nick() or ctx.sid end

H.rrank = function(caller, t, a, ctx)
    local R = roster()
    if not (R and R.SetRank) then return nil, "rhylib_roster isn't installed" end
    local want = tostring(a.rank or "")
    local idx = tonumber(want)
    if idx and (idx ~= math.floor(idx) or idx < 1 or idx > #R.Ranks()) then return nil, "Roster rank 1 to " .. #R.Ranks() end
    idx = idx or R.RankIndex(string.upper(want))
    if not idx then
        for i, x in ipairs(R.Ranks()) do
            if string.lower(x[2]) == string.lower(want) then idx = i end
        end
    end
    if not idx then return nil, "No roster rank " .. want end
    local c = R.Char(ctx.sid)
    if not c or (c.bn or "") == "" then return nil, who(t, ctx) .. " isn't in a battalion" end
    if not R.SetRank(ctx.sid, idx, name(caller)) then return nil, "Nothing changed" end
    return name(caller) .. " set the roster rank of " .. who(t, ctx) .. " to " .. R.RankName(idx)
end

H.battalion = function(caller, t, a, ctx)
    local R = roster()
    if not (R and R.AddMember) then return nil, "rhylib_roster isn't installed" end
    -- A battalion is a DarkRP job category.
    local bn
    for _, job in pairs(RPExtraTeams or {}) do
        if job.category and string.lower(job.category) == string.lower(a.bn or "") then bn = job.category end
    end
    if not bn and RPExtraTeams then return nil, "No battalion " .. tostring(a.bn) end
    a.bn = bn or a.bn
    local c = R.Char(ctx.sid)
    if not c then return nil, who(t, ctx) .. " has no character yet" end
    if not c.trained then R.Train(ctx.sid, name(caller)) end
    if not R.AddMember(ctx.sid, a.bn, name(caller) .. " added") then return nil, "Nothing changed (already in the " .. tostring(a.bn) .. "?)" end
    return name(caller) .. " put " .. who(t, ctx) .. " in the " .. a.bn
end

H.unbattalion = function(caller, t, a, ctx)
    local R = roster()
    if not (R and R.RemoveMember) then return nil, "rhylib_roster isn't installed" end
    if not R.RemoveMember(ctx.sid, name(caller)) then return nil, who(t, ctx) .. " isn't in a battalion" end
    return name(caller) .. " removed " .. who(t, ctx) .. " from their battalion"
end

H.train = function(caller, t, a, ctx)
    local R = roster()
    if not (R and R.Train) then return nil, "rhylib_roster isn't installed" end
    if not R.Train(ctx.sid, name(caller)) then return nil, who(t, ctx) .. " is already trained (or has no character)" end
    return name(caller) .. " passed " .. who(t, ctx) .. " through basic training"
end

H.qual = function(caller, t, a, ctx)
    local R = roster()
    if not (R and R.SetQual) then return nil, "rhylib_roster isn't installed" end
    local q = string.lower(a.qual or "")
    local known = false
    for _, x in ipairs(R.Quals()) do if x[1] == q then known = true end end
    if not known then return nil, "No qualification " .. q end
    if not R.SetQual(ctx.sid, q, a.on, name(caller)) then return nil, "Nothing changed" end
    return name(caller) .. (a.on and " qualified " or " removed a qualification from ") .. who(t, ctx) .. ": " .. R.QualName(q)
end

H.charreset = function(caller, t)
    local R = roster()
    if not (R and R.ResetChar) then return nil, "rhylib_roster isn't installed" end
    if not R.ResetChar(t:SteamID64()) then return nil, name(t) .. " has no character" end
    return name(caller) .. " reset the character of " .. name(t)
end

-- Server / events.
local changing
H.map = function(caller, t, a)
    local m = string.lower(string.Trim(a.map or ""))
    if m == "" or not string.match(m, "^[%w_%-]+$") or not file.Exists("maps/" .. m .. ".bsp", "GAME") then return nil, "No map called " .. m end
    if changing then return nil, "A map change is already counting down (!cancelmap)" end
    changing = m
    Rhylib.Net.Start("admin.countdown")
    net.WriteString(m)
    net.WriteUInt(10, 6)
    net.Broadcast()
    timer.Create("rhylib_admin_map", 10, 1, function()
        changing = nil
        RunConsoleCommand("changelevel", m)
    end)
    return name(caller) .. " is changing the map to " .. m .. " in 10 seconds"
end

H.cancelmap = function(caller)
    if not changing then return nil, "No map change is counting down" end
    timer.Remove("rhylib_admin_map")
    changing = nil
    Rhylib.Net.Start("admin.countdown")
    net.WriteString("")
    net.WriteUInt(0, 6)
    net.Broadcast()
    return name(caller) .. " cancelled the map change"
end

-- Saved placements (armoury, jail, datapad terminals) stay.
local function isPlacement(e)
    if e.placeIndex then return true end
    local c = e:GetClass()
    local A = Rhylib.Armoury
    if A and A.CLASSES and A.CLASSES[c] then return true end
    return c == "rhylib_jail_cell" or c == "rhylib_jail_terminal" or c == "rhylib_bn_computer" or c == "rhylib_med_holotable"
end

H.cleanup = function(caller, t)
    local only = IsValid(t) and t or nil
    local n = 0
    for _, e in ipairs(ents.GetAll()) do
        local sp = e.rhylibSpawner
        if sp ~= nil and (not only or sp == only) and not e:IsWeapon() and not isPlacement(e) then
            e:Remove()
            n = n + 1
        end
    end
    return name(caller) .. " cleaned up " .. n .. " spawned thing" .. (n == 1 and "" or "s") .. (only and (" of " .. you(caller, only)) or "")
end

H.announce = function(caller, t, a)
    if a.text == "" then return nil, "Say something" end
    Rhylib.Net.Start("admin.announce")
    net.WriteString(name(caller))
    net.WriteString(a.text)
    net.Broadcast()
    Admin.Log(name(caller) .. " announced: " .. a.text)
    return nil   -- (the banner is the message)
end

H.warnings = function(caller, t, a, ctx)
    local list = Admin.Warnings(ctx.sid)
    local who = IsValid(t) and t:Nick() or ctx.sid
    if #list == 0 then Admin.Tell(caller, who .. " has no warnings") return end
    Admin.Tell(caller, who .. " has " .. #list .. " warning" .. (#list == 1 and "" or "s") .. ":")
    for i = math.max(1, #list - 9), #list do
        local w = list[i]
        Admin.Tell(caller, os.date("%d %b %Y", w.at or 0) .. " by " .. (w.byName or "?") .. ": " .. (w.reason or ""))
    end
end

-- DarkRP job by command (/job name) or name.
H.setjob = function(caller, t, a)
    if not RPExtraTeams then return nil, "DarkRP isn't running" end
    local want = string.lower(a.job or "")
    local idx
    for i, job in pairs(RPExtraTeams) do
        if string.lower(job.command or "") == want or string.lower(job.name or "") == want then idx = i end
    end
    if not idx then
        for i, job in pairs(RPExtraTeams) do
            if string.find(string.lower(job.name or ""), want, 1, true) then idx = i end
        end
    end
    if not idx then return nil, "No job " .. want end
    t:changeTeam(idx, true, true)
    return name(caller) .. " set the job of " .. you(caller, t) .. " to " .. team.GetName(idx)
end

-- Watching someone: back where you were after. Hidden while watching.
local function stopSpec(ply, move)
    local s = ply.rhylibSpec
    if not s then return end
    ply.rhylibSpec = nil
    ply:UnSpectate()
    if not ply.rhylibCloak and not ply.rhylibLieHidden then
        ply:SetNoDraw(false)
        ply:DrawShadow(true)
        ply:DrawWorldModel(true)
    end
    if not s.noTarget and not ply.rhylibAdminNoTarget then ply:RemoveFlags(FL_NOTARGET) end
    if move and ply:Alive() then
        ply:SetMoveType(MOVETYPE_WALK)
        ply:SetPos(s.pos)
        ply:SetEyeAngles(s.ang)
        ply:SetLocalVelocity(Vector(0, 0, 0))
    end
end
Admin.StopSpectate = stopSpec

H.spectate = function(caller, t)
    if not IsValid(caller) then return nil, "The console can't watch" end
    if caller == t then return nil, "That's you" end
    if caller.rhylibSpec then return H.unspectate(caller) end
    if not caller:Alive() then return nil, "You're dead" end
    caller.rhylibSpec = { pos = caller:GetPos(), ang = caller:EyeAngles(), target = t, noTarget = caller:IsFlagSet(FL_NOTARGET) }
    caller:SetNoDraw(true)
    caller:DrawShadow(false)
    caller:DrawWorldModel(false)
    caller:AddFlags(FL_NOTARGET)
    caller:Spectate(OBS_MODE_CHASE)
    caller:SpectateEntity(t)
    Admin.Tell(caller, "Watching " .. t:Nick() .. "; !unspectate to stop")
    Admin.Log(name(caller) .. " spectated " .. t:Nick())
end

H.unspectate = function(caller)
    if not (IsValid(caller) and caller.rhylibSpec) then return nil, "You aren't spectating" end
    stopSpec(caller, true)
end

-- Respawning ends it; so does the watched player leaving or dying.
Rhylib.Hook.Add("PlayerSpawn", "admin.spec", function(ply)
    if ply.rhylibSpec then stopSpec(ply, false) end
end, -60)
local function targetGone(t)
    for _, p in ipairs(player.GetHumans()) do
        if p.rhylibSpec and p.rhylibSpec.target == t then
            stopSpec(p, true)
            Admin.Tell(p, "Stopped watching " .. (IsValid(t) and t:Nick() or "them"))
        end
    end
end
Rhylib.Hook.Add("PlayerDisconnected", "admin.spec", targetGone)
Rhylib.Hook.Add("PostPlayerDeath", "admin.spec", targetGone)

H.who = function(caller)
    local any = false
    for _, p in ipairs(player.GetHumans()) do
        local r = Admin.Rank(p)
        if (r.level or 0) > 0 then
            any = true
            Admin.Tell(caller, p:Nick() .. ": " .. r.name)
        end
    end
    if not any then Admin.Tell(caller, "No staff online") end
end
