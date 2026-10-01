--[[
    Armoury, server side: the storage behind each armoury entity, locker
    claiming and locking, crate filling, and saving where admins placed
    everything on each map.

    Admin commands (permission rhylib.armoury.admin):
      rhylib_armoury_save        keep every armoury, cabinet, locker and
                                 crate on this map where they are now
      rhylib_crate_refill [all]  refill the crate you're looking at (or all)
      rhylib_locker_unclaim      free the locker you're looking at
]]

local A = Rhylib.Armoury
local Config = Rhylib.Config

Rhylib.Perms.Register("rhylib.armoury.admin", "admin", "Save armoury placements, refill supply crates, unclaim lockers")
Rhylib.Net.Register("armoury.prompt")

local function Inv() return Rhylib.Inventory end

--------------------------------------------------------------------------
-- Storage for each kind
--------------------------------------------------------------------------

-- Every Rhylib gun, biggest first so the shelf packs neatly (or the config list).
local function weaponStock()
    local list = Config.Get("armoury", "weapons")
    if istable(list) and #list > 0 then return list end
    local Items = Rhylib.Items
    Items.EnsureReady()
    local out = {}
    for id, def in pairs(Items.defs) do
        if def.weapon then
            local swep = weapons.Get(def.weapon)
            if swep and swep.IsRhylib and swep.Spawnable then out[#out + 1] = id end
        end
    end
    table.sort(out, function(a, b)
        local da, db = Items.defs[a], Items.defs[b]
        if da.w * da.h ~= db.w * db.h then return da.w * da.h > db.w * db.h end
        return da.name < db.name
    end)
    return out
end

local function ammoStock()
    local out = {}
    for _, id in ipairs(A.AMMO_STOCK) do
        if Rhylib.Items.defs[id] then out[#out + 1] = id end
    end
    return out
end

function A.FillCrate(ent, storage)
    storage.items = {}
    Inv().StorageAdd(storage, ent.CrateMag, 999, { fill = 1 })
end

local function lockerTitle(ent)
    local name = ent:GetOwnerName()
    return name ~= "" and ("Locker: " .. name) or "Personal locker"
end

function A.LoadLocker(ent, storage)
    local sid = ent:GetOwnerSid()
    Inv().StorageLoad(storage, sid ~= "" and Rhylib.Data.Get("locker", sid) or nil)
    storage.title = lockerTitle(ent)
end

function A.SaveLocker(ent)
    local storage = Inv().GetStorage(ent)
    local sid = ent:GetOwnerSid()
    if not storage or sid == "" then return end
    Rhylib.Data.Set("locker", sid, Inv().StorageSerialize(storage))
end

-- The storage for an armoury entity, made the first time someone uses it.
function A.Setup(ent)
    local I = Inv()
    if not I or not I.CreateStorage then return nil end
    local storage = I.GetStorage(ent)
    if storage then return storage end

    local kind = ent.ArmouryKind
    if kind == "armoury" then
        return I.CreateStorage(ent, { kind = "depot", w = 6, title = "Weapons armoury", stock = weaponStock() })
    elseif kind == "ammo" then
        return I.CreateStorage(ent, { kind = "depot", w = 6, title = "Ammo cabinet", stock = ammoStock() })
    elseif kind == "crate" then
        storage = I.CreateStorage(ent, {
            kind = "grid", title = ent.PrintName,
            w = Config.Get("armoury", "crateW"), h = Config.Get("armoury", "crateH"),
        })
        A.FillCrate(ent, storage)
        return storage
    elseif kind == "locker" then
        storage = I.CreateStorage(ent, {
            kind = "grid", title = lockerTitle(ent),
            w = Config.Get("armoury", "lockerW"), h = Config.Get("armoury", "lockerH"),
            onChanged = function() A.SaveLocker(ent) end,
            controls = function(_, ply)
                return { canLock = ply:SteamID64() == ent:GetOwnerSid(), locked = ent:GetLocked() }
            end,
        })
        A.LoadLocker(ent, storage)
        return storage
    end
end

--------------------------------------------------------------------------
-- Using
--------------------------------------------------------------------------

function A.Use(ent, ply)
    if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return end
    local storage = A.Setup(ent)
    if not storage then
        ply:PrintMessage(HUD_PRINTCENTER, "Needs rhylib_inventory")
        return
    end

    if ent.ArmouryKind == "locker" then
        local sid = ent:GetOwnerSid()
        if sid == "" then
            Rhylib.Net.Start("armoury.prompt")
            net.WriteEntity(ent)
            net.Send(ply)
            return
        end
        if sid ~= ply:SteamID64() and ent:GetLocked() then
            ply:PrintMessage(HUD_PRINTCENTER, "Locked. This is " .. ent:GetOwnerName() .. "'s locker")
            return
        end
    end
    Inv().OpenStorage(ply, ent)
end

--------------------------------------------------------------------------
-- Lockers: claim, lock, unclaim
--------------------------------------------------------------------------

local function ownsLocker(sid)
    for _, e in ipairs(ents.FindByClass("rhylib_locker")) do
        if e:GetOwnerSid() == sid then return e end
    end
end

function A.Claim(ply, ent)
    if not IsValid(ent) or ent:GetClass() ~= "rhylib_locker" or ent:GetOwnerSid() ~= "" then return end
    local dist = Inv() and Inv().STORAGE_DIST or 160
    if ply:GetPos():DistToSqr(ent:GetPos()) > dist * dist then return end
    local sid = ply:SteamID64()
    if not sid then return end
    if ownsLocker(sid) then
        ply:PrintMessage(HUD_PRINTCENTER, "You already have a locker")
        return
    end
    ent:SetOwnerSid(sid)
    ent:SetOwnerName(ply:Nick())
    ent:SetLocked(true)
    local storage = A.Setup(ent)
    if storage then A.LoadLocker(ent, storage) end
    A.UpdatePlacement(ent)
    Inv().OpenStorage(ply, ent)
end

function A.ToggleLock(ent)
    ent:SetLocked(not ent:GetLocked())
    local storage = Inv().GetStorage(ent)
    if storage and ent:GetLocked() then
        for p in pairs(storage.viewers) do
            if IsValid(p) and p:SteamID64() ~= ent:GetOwnerSid() then Inv().CloseStorage(p) end
        end
    end
    Inv().RefreshStorage(ent)
    A.UpdatePlacement(ent)
end

-- The contents stay saved under the old owner; they get them back in
-- whichever locker they claim next.
function A.Unclaim(ent)
    A.SaveLocker(ent)
    Inv().RemoveStorage(ent)
    ent:SetOwnerSid("")
    ent:SetOwnerName("")
    ent:SetLocked(false)
    A.UpdatePlacement(ent)
end

Rhylib.Net.Receive("armoury.claim", function(ply)
    A.Claim(ply, net.ReadEntity())
end, { rate = 2, burst = 2 })

-- Owner buttons in the locker window: 0 = lock/unlock, 1 = unclaim.
Rhylib.Net.Receive("armoury.control", function(ply)
    local action = net.ReadUInt(1)
    local storage = Inv().Get(ply).ext
    local ent = storage and storage.ent
    if not IsValid(ent) or ent:GetClass() ~= "rhylib_locker" or ent:GetOwnerSid() ~= ply:SteamID64() then return end
    if action == 0 then A.ToggleLock(ent) else A.Unclaim(ent) end
end, { rate = 3, burst = 3 })

--------------------------------------------------------------------------
-- Placements per map
--------------------------------------------------------------------------

A.placements = A.placements or {}

local function rowFor(ent)
    local p, a = ent:GetPos(), ent:GetAngles()
    local row = { class = ent:GetClass(), pos = { p.x, p.y, p.z }, ang = { a.p, a.y, a.r } }
    if ent:GetClass() == "rhylib_locker" then
        row.owner, row.ownerName, row.locked = ent:GetOwnerSid(), ent:GetOwnerName(), ent:GetLocked()
    end
    return row
end

function A.SavePlacements()
    local rows = {}
    for class in pairs(A.CLASSES) do
        for _, ent in ipairs(ents.FindByClass(class)) do
            rows[#rows + 1] = rowFor(ent)
            ent.placeIndex = #rows
        end
    end
    A.placements = rows
    Rhylib.Data.Set("armoury", game.GetMap(), rows)
    return #rows
end

-- Keep a saved locker's claim when it changes.
function A.UpdatePlacement(ent)
    local i = ent.placeIndex
    if not i or not A.placements[i] then return end
    A.placements[i] = rowFor(ent)
    Rhylib.Data.Set("armoury", game.GetMap(), A.placements)
end

function A.SpawnPlacements()
    local rows = Rhylib.Data.Get("armoury", game.GetMap())
    if not istable(rows) then return end
    A.placements = rows
    for i, row in ipairs(rows) do
        if A.CLASSES[row.class] then
            local ent = ents.Create(row.class)
            if IsValid(ent) then
                ent:SetPos(Vector(row.pos[1], row.pos[2], row.pos[3]))
                ent:SetAngles(Angle(row.ang[1], row.ang[2], row.ang[3]))
                ent:Spawn()
                if row.class == "rhylib_locker" and row.owner and row.owner ~= "" then
                    ent:SetOwnerSid(row.owner)
                    ent:SetOwnerName(row.ownerName or "")
                    ent:SetLocked(row.locked and true or false)
                end
                ent.placeIndex = i
            end
        end
    end
    Rhylib.Print("armoury", "Placed %d armoury entities on %s", #rows, game.GetMap())
end

Rhylib.Hook.Add("InitPostEntity", "armoury.spawn", function()
    timer.Simple(1, A.SpawnPlacements)
end)

Rhylib.Hook.Add("PostCleanupMap", "armoury.spawn", function()
    A.SpawnPlacements()
end)

--------------------------------------------------------------------------
-- Admin commands
--------------------------------------------------------------------------

local function reply(ply, msg)
    if IsValid(ply) then ply:ChatPrint(msg) else print(msg) end
end

local function adminCommand(name, fn)
    concommand.Add(name, function(ply, _, args)
        Rhylib.Perms.Check(ply, "rhylib.armoury.admin", function(ok)
            if not ok then
                reply(ply, "You don't have permission for " .. name)
                return
            end
            fn(ply, args)
        end)
    end)
end

local function lookedAt(ply, class)
    if not IsValid(ply) then return nil end
    local ent = ply:GetEyeTrace().Entity
    if IsValid(ent) and (not class or ent:GetClass():find(class, 1, true)) then return ent end
end

adminCommand("rhylib_armoury_save", function(ply)
    reply(ply, "Saved " .. A.SavePlacements() .. " armoury entities for " .. game.GetMap())
end)

adminCommand("rhylib_crate_refill", function(ply, args)
    local list = {}
    if args[1] == "all" then
        for _, class in ipairs({ "rhylib_crate_small", "rhylib_crate_medium", "rhylib_crate_large" }) do
            for _, e in ipairs(ents.FindByClass(class)) do list[#list + 1] = e end
        end
    else
        list[1] = lookedAt(ply, "rhylib_crate_")
    end
    local n = 0
    for _, ent in ipairs(list) do
        local storage = A.Setup(ent)
        if storage then
            A.FillCrate(ent, storage)
            Inv().RefreshStorage(ent)
            n = n + 1
        end
    end
    reply(ply, "Refilled " .. n .. " supply crate" .. (n == 1 and "" or "s"))
end)

adminCommand("rhylib_locker_unclaim", function(ply)
    local ent = lookedAt(ply, "rhylib_locker")
    if not ent or ent:GetOwnerSid() == "" then
        reply(ply, "Look at a claimed locker")
        return
    end
    local name = ent:GetOwnerName()
    A.Unclaim(ent)
    reply(ply, "Unclaimed " .. name .. "'s locker (their items are kept for their next locker)")
end)
