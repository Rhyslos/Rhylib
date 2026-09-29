--[[
    Server inventory. The server owns every container; clients only ask.

    Networking (to the owner only):
      - "inv.full"  whole inventory, sent once when the client asks after joining
      - "inv.upd"   batched per tick: only the items that changed or were removed
    Client requests (rate limited): inv.req, inv.move, inv.drop, inv.use

    Saving: changed inventories are marked dirty and written to SQLite
    every few seconds (Rhylib.Data batches the writes further).

    Weapons: an item with a `weapon` class gives that weapon while it's in
    the inventory, and strips it when the item leaves. The weapon's clip
    and power cell are stored in the item's data via the weapon's
    GetInventoryData / SetInventoryData.

    Other modules can listen to:
      Rhylib.InventoryChanged(ply)
      Rhylib.InventoryWeaponPickup(ply, class)   -- a new weapon was picked up
]]

Rhylib.Inventory = Rhylib.Inventory or {}
local Inv = Rhylib.Inventory
local Items = Rhylib.Items
local Config = Rhylib.Config

Config.Register("inventory", "width", 5, "Personal inventory width in cells")
Config.Register("inventory", "height", 3, "Personal inventory height in cells")
Config.Register("inventory", "saveInterval", 2, "Seconds between saves of changed inventories")

Inv.containers = Inv.containers or {}  -- [ply] = container
Inv.dirty = Inv.dirty or {}            -- [ply] = true

Rhylib.Net.Register("inv.full")

local updBatch = Rhylib.Net.CreateBatch("inv.upd", function(ch)
    net.WriteBool(ch.set)
    if ch.set then
        Items.WriteInstance(ch.inst)
    else
        net.WriteUInt(ch.uid, Items.UID_BITS)
    end
end)

--------------------------------------------------------------------------
-- Weapons
--------------------------------------------------------------------------

local function captureWeapon(ply, inst)
    local def = Items.defs[inst.id]
    if not def or not def.weapon then return end
    local wep = ply:GetWeapon(def.weapon)
    if IsValid(wep) and wep.GetInventoryData then
        inst.data = wep:GetInventoryData() or inst.data
    end
end

local function giveWeapon(ply, inst)
    local def = Items.defs[inst.id]
    if not def or not def.weapon or not ply:Alive() or ply:HasWeapon(def.weapon) then return end
    ply.rhylibGiving = true
    local wep = ply:Give(def.weapon, true)
    ply.rhylibGiving = false
    if IsValid(wep) and wep.SetInventoryData then
        wep:SetInventoryData(inst.data)
    end
end

local function stripWeapon(ply, inst)
    local def = Items.defs[inst.id]
    if not def or not def.weapon then return end
    captureWeapon(ply, inst)
    if ply:HasWeapon(def.weapon) then ply:StripWeapon(def.weapon) end
end

function Inv.CaptureWeapons(ply)
    local c = Inv.containers[ply]
    if not c then return end
    for _, inst in pairs(c.items) do captureWeapon(ply, inst) end
end

function Inv.GiveAllWeapons(ply)
    for _, inst in pairs(Inv.Get(ply).items) do giveWeapon(ply, inst) end
end

--------------------------------------------------------------------------
-- Containers
--------------------------------------------------------------------------

local function serialize(c)
    local out = {}
    for _, o in pairs(c.items) do
        out[#out + 1] = { o.id, o.x, o.y, o.rot and 1 or 0, o.count, o.data }
    end
    return out
end

local function nextUid(c)
    for _ = 1, 65535 do
        local uid = c.nextUid
        c.nextUid = uid % 65535 + 1
        if not c.items[uid] then return uid end
    end
end

local function load(ply, c)
    local saved = Rhylib.Data.Get("inventory", ply:SteamID64())
    if not istable(saved) then return end
    for _, row in ipairs(saved) do
        local id, x, y, rot, count = row[1], row[2], row[3], row[4] == 1, row[5]
        if Items.defs[id] and Items.Fits(c.w, c.h, c.items, id, x, y, rot) then
            local uid = nextUid(c)
            c.items[uid] = { uid = uid, id = id, x = x, y = y, rot = rot, count = count, data = istable(row[6]) and row[6] or {} }
        end
    end
end

function Inv.Get(ply)
    local c = Inv.containers[ply]
    if c then return c end
    Items.EnsureReady()
    c = {
        w = Config.Get("inventory", "width"),
        h = Config.Get("inventory", "height"),
        items = {},
        nextUid = 1,
        ready = false,  -- true once the client has its full copy
    }
    Inv.containers[ply] = c
    if ply:SteamID64() then load(ply, c) end
    return c
end

local function changed(ply)
    Inv.dirty[ply] = true
    hook.Run("Rhylib.InventoryChanged", ply)
end

local function sendSet(ply, c, inst)
    if c.ready then updBatch:Send(ply, { set = true, inst = inst }) end
end

local function setInst(ply, c, inst)
    c.items[inst.uid] = inst
    sendSet(ply, c, inst)
    changed(ply)
end

local function removeInst(ply, c, uid)
    local inst = c.items[uid]
    if not inst then return end
    stripWeapon(ply, inst)
    c.items[uid] = nil
    if c.ready then updBatch:Send(ply, { set = false, uid = uid }) end
    changed(ply)
    return inst
end

local function findSpot(c, id)
    local def = Items.defs[id]
    local rots = def.w == def.h and { false } or { false, true }
    for y = 0, c.h - 1 do
        for x = 0, c.w - 1 do
            for _, rot in ipairs(rots) do
                if Items.Fits(c.w, c.h, c.items, id, x, y, rot) then return x, y, rot end
            end
        end
    end
end

--------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------

function Inv.Count(ply, id)
    local n = 0
    for _, o in pairs(Inv.Get(ply).items) do
        if o.id == id then n = n + o.count end
    end
    return n
end

function Inv.Has(ply, id)
    return Inv.Count(ply, id) > 0
end

-- Would one item of this type fit right now?
function Inv.CanAdd(ply, id)
    local c = Inv.Get(ply)
    local def = Items.defs[id]
    if not def then return false end
    if def.weapon and Inv.Has(ply, id) then return false end
    if def.stack > 1 then
        for _, o in pairs(c.items) do
            if o.id == id and o.count < def.stack and Items.IsFull(o) then return true end
        end
    end
    return findSpot(c, id) ~= nil
end

-- Adds items, stacking where possible. Returns how many didn't fit.
function Inv.AddItem(ply, id, count, data)
    local c = Inv.Get(ply)
    local def = Items.defs[id]
    count = count or 1
    if not def then return count end
    data = data or {}
    if def.weapon and Inv.Has(ply, id) then return count end

    local stackable = def.stack > 1 and (not def.fill or (data.fill or 1) >= 1)
    if stackable then
        for _, o in pairs(c.items) do
            if count <= 0 then break end
            if o.id == id and o.count < def.stack and Items.IsFull(o) then
                local add = math.min(def.stack - o.count, count)
                o.count = o.count + add
                count = count - add
                setInst(ply, c, o)
            end
        end
    end

    while count > 0 do
        local x, y, rot = findSpot(c, id)
        if not x then break end
        local n = stackable and math.min(def.stack, count) or 1
        local inst = { uid = nextUid(c), id = id, x = x, y = y, rot = rot, count = n, data = table.Copy(data) }
        setInst(ply, c, inst)
        count = count - n
        giveWeapon(ply, inst)
    end
    return count
end

-- Removes `amount` (default all) from one item.
function Inv.Remove(ply, uid, amount)
    local c = Inv.Get(ply)
    local inst = c.items[uid]
    if not inst then return end
    amount = amount or inst.count
    if amount >= inst.count then
        return removeInst(ply, c, uid)
    end
    inst.count = inst.count - amount
    setInst(ply, c, inst)
    return inst
end

-- Takes one of the fullest item of this type (for reloads). Returns its fill (0-1) or nil.
function Inv.TakeBest(ply, id)
    local best, bestFill
    for _, o in pairs(Inv.Get(ply).items) do
        if o.id == id then
            local f = o.data and o.data.fill or 1
            if not best or f > bestFill then best, bestFill = o, f end
        end
    end
    if not best then return nil end
    Inv.Remove(ply, best.uid, 1)
    return bestFill
end

function Inv.SpawnWorldItem(ply, id, count, data)
    local ent = ents.Create("rhylib_world_item")
    if not IsValid(ent) then return end
    local start = ply:GetShootPos()
    local tr = util.TraceLine({ start = start, endpos = start + ply:GetAimVector() * 50, filter = ply })
    ent:SetItem(id, count, data)
    ent:SetPos(tr.HitPos + tr.HitNormal * 8)
    ent:SetAngles(Angle(0, ply:EyeAngles().y, 0))
    ent:Spawn()
    return ent
end

-- Adds an item, and drops whatever doesn't fit at the player's feet.
function Inv.AddOrDrop(ply, id, count, data)
    local left = Inv.AddItem(ply, id, count, data)
    if left > 0 then Inv.SpawnWorldItem(ply, id, left, data) end
end

function Inv.Drop(ply, uid)
    local c = Inv.Get(ply)
    local inst = c.items[uid]
    if not inst then return end
    captureWeapon(ply, inst)
    local ent = Inv.SpawnWorldItem(ply, inst.id, inst.count, inst.data)
    if IsValid(ent) then removeInst(ply, c, uid) end
end

function Inv.Move(ply, uid, x, y, rot)
    local c = Inv.Get(ply)
    local inst = c.items[uid]
    if not inst then return end

    local target = Items.MergeTarget(c.items, inst, x, y)
    if target then
        local def = Items.defs[inst.id]
        local add = math.min(def.stack - target.count, inst.count)
        target.count = target.count + add
        inst.count = inst.count - add
        setInst(ply, c, target)
        if inst.count <= 0 then removeInst(ply, c, uid) else setInst(ply, c, inst) end
        return
    end

    if Items.Fits(c.w, c.h, c.items, inst.id, x, y, rot, uid) then
        inst.x, inst.y, inst.rot = x, y, rot
        setInst(ply, c, inst)
    else
        sendSet(ply, c, inst)  -- rejected: put the client's copy back
    end
end

function Inv.SendFull(ply)
    local c = Inv.Get(ply)
    c.ready = true
    local list = {}
    for _, o in pairs(c.items) do list[#list + 1] = o end

    Rhylib.Net.Start("inv.full")
    net.WriteUInt(c.w, 5)
    net.WriteUInt(c.h, 5)
    net.WriteUInt(#list, 8)
    for _, o in ipairs(list) do Items.WriteInstance(o) end
    Rhylib.Profiler.AddNet("inv.full", net.BytesWritten() or 0)
    net.Send(ply)
end

function Inv.Save(ply)
    local c = Inv.containers[ply]
    if not c or not ply:SteamID64() then return end
    Inv.CaptureWeapons(ply)
    Rhylib.Data.Set("inventory", ply:SteamID64(), serialize(c))
end

--------------------------------------------------------------------------
-- Client requests
--------------------------------------------------------------------------

Rhylib.Net.Receive("inv.req", function(ply)
    Inv.SendFull(ply)
end, { rate = 1, burst = 2 })

Rhylib.Net.Receive("inv.move", function(ply)
    local uid = net.ReadUInt(Items.UID_BITS)
    local x = net.ReadUInt(Items.POS_BITS)
    local y = net.ReadUInt(Items.POS_BITS)
    local rot = net.ReadBool()
    Inv.Move(ply, uid, x, y, rot)
end, { rate = 20, burst = 10 })

Rhylib.Net.Receive("inv.drop", function(ply)
    Inv.Drop(ply, net.ReadUInt(Items.UID_BITS))
end, { rate = 5, burst = 5 })

Rhylib.Net.Receive("inv.use", function(ply)
    local inst = Inv.Get(ply).items[net.ReadUInt(Items.UID_BITS)]
    local def = inst and Items.defs[inst.id]
    if def and def.weapon and ply:HasWeapon(def.weapon) then
        ply:SelectWeapon(def.weapon)
    end
end, { rate = 5, burst = 5 })

--------------------------------------------------------------------------
-- Game hooks
--------------------------------------------------------------------------

-- Weapons from the spawn menu, the map or other addons go into the
-- inventory instead of straight into the hands.
Rhylib.Hook.Add("PlayerCanPickupWeapon", "inventory.pickup", function(ply, wep)
    if ply.rhylibGiving then return end
    local class = wep:GetClass()
    local def = Items.defs[class]
    if not def then return end  -- not an inventory weapon: normal behaviour

    if wep.rhylibClaimed then return false end
    if not Inv.CanAdd(ply, class) then
        if (ply.rhylibFullNotice or 0) < CurTime() then
            ply.rhylibFullNotice = CurTime() + 2
            ply:PrintMessage(HUD_PRINTCENTER, Inv.Has(ply, class) and "You already carry one" or "No room in your inventory")
        end
        return false
    end

    wep.rhylibClaimed = true
    timer.Simple(0, function()
        if IsValid(wep) then wep:Remove() end
        if not IsValid(ply) then return end
        if Inv.AddItem(ply, class, 1, {}) == 0 then
            hook.Run("Rhylib.InventoryWeaponPickup", ply, class)
        end
    end)
    return false
end)

Rhylib.Hook.Add("PlayerInitialSpawn", "inventory.load", function(ply)
    Inv.Get(ply)
end)

Rhylib.Hook.Add("PlayerSpawn", "inventory.weapons", function(ply)
    timer.Simple(0, function()
        if IsValid(ply) and ply:Alive() then Inv.GiveAllWeapons(ply) end
    end)
end)

-- Keep clip and cell state before the weapons are removed on death.
Rhylib.Hook.Add("DoPlayerDeath", "inventory.capture", function(ply)
    Inv.CaptureWeapons(ply)
end)

Rhylib.Hook.Add("PlayerDisconnected", "inventory.save", function(ply)
    Inv.Save(ply)
    Inv.containers[ply] = nil
    Inv.dirty[ply] = nil
end)

timer.Create("Rhylib.Inventory.Save", Config.Get("inventory", "saveInterval"), 0, function()
    for ply in pairs(Inv.dirty) do
        if IsValid(ply) then Inv.Save(ply) end
    end
    Inv.dirty = {}
end)

Rhylib.Hook.Add("ShutDown", "inventory.save", function()
    for ply in pairs(Inv.containers) do
        if IsValid(ply) then Inv.Save(ply) end
    end
end, -10)  -- before the data layer's final flush
