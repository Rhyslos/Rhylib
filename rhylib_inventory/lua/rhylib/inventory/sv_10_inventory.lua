--[[
    Server inventory. The server owns every container; clients only ask.

    Each player has a state table:
        { cont = { [1] = main grid, [2] = backpack grid (while worn), [3] = back slot },
          byUid = { [uid] = inst }, nextUid, ready }
    Container ids and placement rules are in sh_00_items.lua.

    Networking (to the owner only):
      - "inv.full"  everything, sent once when the client asks after joining
      - "inv.upd"   batched per tick: changed items, removed items, and
                    container size changes (backpack put on or taken off)
    Client requests (rate limited): inv.req, inv.move, inv.drop, inv.use

    Saving: changed inventories are marked dirty and written to SQLite
    every few seconds (Rhylib.Data batches the writes further).

    Weapons: an item with a `weapon` class gives that weapon while it's in
    any container, and strips it when the item leaves. Clip and power cell
    are stored in the item via the weapon's GetInventoryData / SetInventoryData.

    Other modules can listen to:
      Rhylib.InventoryChanged(ply)
      Rhylib.InventoryWeaponPickup(ply, class)   -- a new weapon was picked up
]]

Rhylib.Inventory = Rhylib.Inventory or {}
local Inv = Rhylib.Inventory
local Items = Rhylib.Items
local Config = Rhylib.Config

local MAIN, BACK, SLOT_BACK = Items.MAIN, Items.BACK, Items.SLOT_BACK

Config.Register("inventory", "width", 5, "Personal inventory width in cells")
Config.Register("inventory", "height", 3, "Personal inventory height in cells")
Config.Register("inventory", "saveInterval", 2, "Seconds between saves of changed inventories")
Config.Register("inventory", "worldItemLife", 600, "Seconds before a dropped item on the ground is removed (0 = never)")

Inv.states = Inv.states or {}  -- [ply] = state
Inv.dirty = Inv.dirty or {}    -- [ply] = true

Rhylib.Net.Register("inv.full")

local OP_REMOVE, OP_SET, OP_DIMS = 0, 1, 2

local updBatch = Rhylib.Net.CreateBatch("inv.upd", function(ch)
    net.WriteUInt(ch.op, 2)
    if ch.op == OP_SET then
        Items.WriteInstance(ch.inst)
    elseif ch.op == OP_REMOVE then
        net.WriteUInt(ch.uid, Items.UID_BITS)
    else
        net.WriteUInt(ch.cid, Items.CONT_BITS)
        net.WriteUInt(ch.w, 5)
        net.WriteUInt(ch.h, 5)
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
    local st = Inv.states[ply]
    if not st then return end
    for _, inst in pairs(st.byUid) do captureWeapon(ply, inst) end
end

function Inv.GiveAllWeapons(ply)
    for _, inst in pairs(Inv.Get(ply).byUid) do giveWeapon(ply, inst) end
end

--------------------------------------------------------------------------
-- State and low-level changes
--------------------------------------------------------------------------

local function nextUid(st)
    for _ = 1, 65535 do
        local uid = st.nextUid
        st.nextUid = uid % 65535 + 1
        if not st.byUid[uid] then return uid end
    end
end

-- Changes are collected and Rhylib.InventoryChanged runs once per player
-- per tick, not once per item (a load or a stacked pickup can touch many
-- items at once, and listeners recount the whole inventory).
Inv.pending = Inv.pending or {}  -- [ply] = true

local function changed(ply)
    Inv.dirty[ply] = true
    Inv.pending[ply] = true
end

-- Before the net batches flush (priority 1000), so updates and listeners
-- land in the same tick.
Rhylib.Hook.Add("Tick", "inventory.changed", function()
    if next(Inv.pending) == nil then return end
    local list = Inv.pending
    Inv.pending = {}
    for ply in pairs(list) do
        if IsValid(ply) then
            -- Weight and carry cap for stamina, in two engine-networked vars.
            local st = Inv.states[ply]
            if st then
                local weight, cap = Items.Weight(st)
                ply:SetNW2Float("rhylib_weight", math.Round(weight, 2))
                ply:SetNW2Float("rhylib_carry", cap)
            end
            hook.Run("Rhylib.InventoryChanged", ply)
        end
    end
end, 900)

local function sendSet(ply, st, inst)
    if st.ready then updBatch:Send(ply, { op = OP_SET, inst = inst }) end
end

local function sendDims(ply, st, cid)
    if not st.ready then return end
    local c = st.cont[cid]
    updBatch:Send(ply, { op = OP_DIMS, cid = cid, w = c and c.w or 0, h = c and c.h or 0 })
end

-- Wearing or removing a backpack adds or removes the backpack grid.
local function updateBackpack(ply, st)
    local worn
    for _, inst in pairs(st.cont[SLOT_BACK].items) do worn = inst end
    local def = worn and Items.defs[worn.id]
    local grid = def and def.grid

    local cur = st.cont[BACK]
    if grid then
        if not cur or cur.w ~= grid[1] or cur.h ~= grid[2] then
            st.cont[BACK] = { w = grid[1], h = grid[2], items = cur and cur.items or {} }
            sendDims(ply, st, BACK)
        end
    elseif cur then
        st.cont[BACK] = nil
        sendDims(ply, st, BACK)
    end
end

-- Put an instance into a container (new, or moved from another one).
local function place(ply, st, inst, cid, x, y, rot)
    local old = inst.c and st.cont[inst.c]
    if old then old.items[inst.uid] = nil end
    local wasSlot = inst.c == SLOT_BACK

    inst.c, inst.x, inst.y, inst.rot = cid, x, y, rot
    st.cont[cid].items[inst.uid] = inst
    st.byUid[inst.uid] = inst
    sendSet(ply, st, inst)
    if wasSlot or cid == SLOT_BACK then updateBackpack(ply, st) end
    changed(ply)
end

local function update(ply, st, inst)
    sendSet(ply, st, inst)
    changed(ply)
end

local function removeInst(ply, st, uid)
    local inst = st.byUid[uid]
    if not inst then return end
    stripWeapon(ply, inst)
    st.cont[inst.c].items[uid] = nil
    st.byUid[uid] = nil
    if st.ready then updBatch:Send(ply, { op = OP_REMOVE, uid = uid }) end
    if inst.c == SLOT_BACK then updateBackpack(ply, st) end
    changed(ply)
    return inst
end

-- First free spot for a new item: worn slot if it fits there, then the
-- main grid, then the backpack.
local ROTS_SQUARE, ROTS_BOTH = { false }, { false, true }
local SEARCH = { MAIN, BACK }

local function findSpot(st, id)
    local def = Items.defs[id]
    if def.slot == "back" and Items.CanPlace(st, id, SLOT_BACK, 0, 0, false) then
        return SLOT_BACK, 0, 0, false
    end
    local rots = def.w == def.h and ROTS_SQUARE or ROTS_BOTH
    for i = 1, #SEARCH do
        local cid = SEARCH[i]
        local c = st.cont[cid]
        if c and Items.ContainerAllows(cid, def) then
            for y = 0, c.h - 1 do
                for x = 0, c.w - 1 do
                    for r = 1, #rots do
                        if Items.Fits(c.w, c.h, c.items, id, x, y, rots[r]) then return cid, x, y, rots[r] end
                    end
                end
            end
        end
    end
end

local function serialize(st)
    local out = {}
    for _, o in pairs(st.byUid) do
        out[#out + 1] = { o.id, o.x, o.y, o.rot and 1 or 0, o.count, o.data, o.c }
    end
    return out
end

local function load(ply, st)
    local saved = Rhylib.Data.Get("inventory", ply:SteamID64())
    if not istable(saved) then return end
    -- Worn items first, so the backpack grid exists before its contents.
    for pass = 1, 2 do
        for _, row in ipairs(saved) do
            local cid = row[7] or MAIN
            if (pass == 1) == (cid == SLOT_BACK) then
                local id, x, y, rot, count = row[1], row[2], row[3], row[4] == 1, row[5]
                if Items.defs[id] and Items.CanPlace(st, id, cid, x, y, rot) then
                    local inst = { uid = nextUid(st), id = id, count = count, data = istable(row[6]) and row[6] or {} }
                    place(ply, st, inst, cid, x, y, rot)
                end
            end
        end
    end
    Inv.dirty[ply] = nil
end

function Inv.Get(ply)
    local st = Inv.states[ply]
    if st then return st end
    Items.EnsureReady()
    st = {
        cont = {
            [MAIN] = { w = Config.Get("inventory", "width"), h = Config.Get("inventory", "height"), items = {} },
            [SLOT_BACK] = { w = 1, h = 1, items = {} },
        },
        byUid = {},
        nextUid = 1,
        ready = false,  -- true once the client has its full copy
    }
    Inv.states[ply] = st
    if ply:SteamID64() then load(ply, st) end
    return st
end

--------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------

function Inv.Count(ply, id)
    local n = 0
    for _, o in pairs(Inv.Get(ply).byUid) do
        if o.id == id then n = n + o.count end
    end
    return n
end

function Inv.Has(ply, id)
    return Inv.Count(ply, id) > 0
end

-- Would one item of this type fit right now?
function Inv.CanAdd(ply, id)
    local st = Inv.Get(ply)
    local def = Items.defs[id]
    if not def then return false end
    if def.weapon and Inv.Has(ply, id) then return false end
    if def.stack > 1 then
        for _, o in pairs(st.byUid) do
            if o.id == id and o.c ~= SLOT_BACK and o.count < def.stack and Items.IsFull(o) then return true end
        end
    end
    return findSpot(st, id) ~= nil
end

-- Adds items, stacking where possible. Returns how many didn't fit.
function Inv.AddItem(ply, id, count, data)
    local st = Inv.Get(ply)
    local def = Items.defs[id]
    count = count or 1
    if not def then return count end
    data = data or {}
    if def.weapon and Inv.Has(ply, id) then return count end

    local stackable = def.stack > 1 and (not def.fill or (data.fill or 1) >= 1)
    if stackable then
        for _, o in pairs(st.byUid) do
            if count <= 0 then break end
            if o.id == id and o.count < def.stack and Items.IsFull(o) then
                local add = math.min(def.stack - o.count, count)
                o.count = o.count + add
                count = count - add
                update(ply, st, o)
            end
        end
    end

    while count > 0 do
        local cid, x, y, rot = findSpot(st, id)
        if not cid then break end
        local n = stackable and math.min(def.stack, count) or 1
        local inst = { uid = nextUid(st), id = id, count = n, data = table.Copy(data) }
        place(ply, st, inst, cid, x, y, rot)
        count = count - n
        giveWeapon(ply, inst)
    end
    return count
end

-- Removes `amount` (default all) from one item.
function Inv.Remove(ply, uid, amount)
    local st = Inv.Get(ply)
    local inst = st.byUid[uid]
    if not inst then return end
    amount = amount or inst.count
    if amount >= inst.count then
        if not Items.CanLeave(st, inst) then return end
        return removeInst(ply, st, uid)
    end
    inst.count = inst.count - amount
    update(ply, st, inst)
    return inst
end

-- Takes one of the fullest item of this type (for reloads). Returns its fill (0-1) or nil.
function Inv.TakeBest(ply, id)
    local best, bestFill
    for _, o in pairs(Inv.Get(ply).byUid) do
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
    local st = Inv.Get(ply)
    local inst = st.byUid[uid]
    if not inst then return end
    if not Items.CanLeave(st, inst) then
        ply:PrintMessage(HUD_PRINTCENTER, "Empty the backpack first")
        return
    end
    captureWeapon(ply, inst)
    local ent = Inv.SpawnWorldItem(ply, inst.id, inst.count, inst.data)
    if IsValid(ent) then removeInst(ply, st, uid) end
end

function Inv.Move(ply, uid, cid, x, y, rot)
    local st = Inv.Get(ply)
    local inst = st.byUid[uid]
    if not inst then return end

    if cid ~= inst.c and not Items.CanLeave(st, inst) then
        ply:PrintMessage(HUD_PRINTCENTER, "Empty the backpack first")
        sendSet(ply, st, inst)
        return
    end

    local c = st.cont[cid]
    local target = c and cid ~= SLOT_BACK and Items.MergeTarget(c.items, inst, x, y)
    if target then
        local def = Items.defs[inst.id]
        local add = math.min(def.stack - target.count, inst.count)
        target.count = target.count + add
        inst.count = inst.count - add
        update(ply, st, target)
        if inst.count <= 0 then removeInst(ply, st, uid) else update(ply, st, inst) end
        return
    end

    if Items.CanPlace(st, inst.id, cid, x, y, rot, uid) then
        place(ply, st, inst, cid, x, y, rot)
    else
        sendSet(ply, st, inst)  -- rejected: put the client's copy back
    end
end

function Inv.SendFull(ply)
    local st = Inv.Get(ply)
    st.ready = true

    local conts, list = {}, {}
    for cid, c in pairs(st.cont) do conts[#conts + 1] = { cid = cid, w = c.w, h = c.h } end
    for _, o in pairs(st.byUid) do list[#list + 1] = o end

    Rhylib.Net.Start("inv.full")
    net.WriteUInt(#conts, Items.CONT_BITS + 1)
    for _, c in ipairs(conts) do
        net.WriteUInt(c.cid, Items.CONT_BITS)
        net.WriteUInt(c.w, 5)
        net.WriteUInt(c.h, 5)
    end
    net.WriteUInt(#list, 8)
    for _, o in ipairs(list) do Items.WriteInstance(o) end
    Rhylib.Profiler.AddNet("inv.full", net.BytesWritten() or 0)
    net.Send(ply)
end

function Inv.Save(ply)
    local st = Inv.states[ply]
    if not st or not ply:SteamID64() then return end
    Inv.CaptureWeapons(ply)
    Rhylib.Data.Set("inventory", ply:SteamID64(), serialize(st))
end

--------------------------------------------------------------------------
-- Client requests
--------------------------------------------------------------------------

Rhylib.Net.Receive("inv.req", function(ply)
    Inv.SendFull(ply)
end, { rate = 1, burst = 2 })

Rhylib.Net.Receive("inv.move", function(ply)
    local uid = net.ReadUInt(Items.UID_BITS)
    local cid = net.ReadUInt(Items.CONT_BITS)
    local x = net.ReadUInt(Items.POS_BITS)
    local y = net.ReadUInt(Items.POS_BITS)
    local rot = net.ReadBool()
    Inv.Move(ply, uid, cid, x, y, rot)
end, { rate = 20, burst = 10 })

Rhylib.Net.Receive("inv.drop", function(ply)
    Inv.Drop(ply, net.ReadUInt(Items.UID_BITS))
end, { rate = 5, burst = 5 })

Rhylib.Net.Receive("inv.use", function(ply)
    local inst = Inv.Get(ply).byUid[net.ReadUInt(Items.UID_BITS)]
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
    Inv.states[ply] = nil
    Inv.dirty[ply] = nil
    Inv.pending[ply] = nil
end)

timer.Create("Rhylib.Inventory.Save", Config.Get("inventory", "saveInterval"), 0, function()
    for ply in pairs(Inv.dirty) do
        if IsValid(ply) then Inv.Save(ply) end
    end
    Inv.dirty = {}
end)

Rhylib.Hook.Add("ShutDown", "inventory.save", function()
    for ply in pairs(Inv.states) do
        if IsValid(ply) then Inv.Save(ply) end
    end
end, -10)  -- before the data layer's final flush
