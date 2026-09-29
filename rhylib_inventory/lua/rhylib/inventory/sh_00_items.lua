--[[
    Item registry and shared grid rules.

    Register an item (shared, at load time):
        Rhylib.Items.Register("mag", {
            name = "Blaster magazine",
            w = 1, h = 1,          -- size in cells
            stack = 5,             -- max per stack (1 = doesn't stack)
            fill = true,           -- has a 0-1 fill level (partly used magazines, cells)
            category = "ammo",     -- weapon, ammo, medical, gear, misc (sets the colour)
            model = "models/items/boxmrounds.mdl",  -- used when dropped
        })

    Weapons become items automatically if their SWEP table sets InvW/InvH.

    An item instance in a container:
        { uid, id, x, y, rot, count, data }
    x, y are the top-left cell (0-based). rot swaps width and height.
    Only items with fill = true stack when full; partly used ones stay single.

    On the network each item type is a small number (netId), assigned by
    sorting ids, so server and client agree without sending names.
]]

Rhylib.Items = Rhylib.Items or {}
local Items = Rhylib.Items

Items.defs = Items.defs or {}
Items.byNet = Items.byNet or {}
Items.finalized = false

Items.UID_BITS = 16
Items.NET_BITS = 10       -- up to 1023 item types
Items.POS_BITS = 4        -- containers up to 16 x 16
Items.COUNT_BITS = 8

function Items.Register(id, def)
    def.id = id
    def.name = def.name or id
    def.w = def.w or 1
    def.h = def.h or 1
    def.stack = def.stack or 1
    def.category = def.category or "misc"
    Items.defs[id] = def
    Items.finalized = false
end

function Items.Get(id)
    return Items.defs[id]
end

function Items.Finalize()
    local ids = {}
    for id in pairs(Items.defs) do ids[#ids + 1] = id end
    table.sort(ids)
    Items.byNet = {}
    for i, id in ipairs(ids) do
        Items.defs[id].netId = i
        Items.byNet[i] = Items.defs[id]
    end
    Items.finalized = true
end

-- Weapons are registered as items once, then ids are assigned.
function Items.EnsureReady()
    if not Items.weaponsDone then
        Items.RegisterWeapons()
        Items.weaponsDone = true
    end
    if not Items.finalized then Items.Finalize() end
end

function Items.NetId(id)
    Items.EnsureReady()
    local def = Items.defs[id]
    return def and def.netId or 0
end

function Items.FromNet(n)
    Items.EnsureReady()
    return Items.byNet[n]
end

-- Any weapon that declares an inventory size becomes an item.
function Items.RegisterWeapons()
    for _, stored in ipairs(weapons.GetList()) do
        local class = stored.ClassName
        if class and not Items.defs[class] then
            local full = weapons.Get(class)
            if full and full.InvW then
                Items.Register(class, {
                    name = full.PrintName or class,
                    w = full.InvW,
                    h = full.InvH or 1,
                    model = full.WorldModel,
                    category = "weapon",
                    weapon = class,
                    large = full.InvLarge,
                })
            end
        end
    end
end

-- Weapons are registered by now on both server and client.
Rhylib.Hook.Add("InitPostEntity", "inventory.items", function()
    Items.weaponsDone = false
    Items.EnsureReady()
end, -10)

--------------------------------------------------------------------------
-- Grid rules (used by the server to validate and the client to preview)
--------------------------------------------------------------------------

function Items.Size(id, rot)
    local def = Items.defs[id]
    if not def then return 1, 1 end
    if rot then return def.h, def.w end
    return def.w, def.h
end

function Items.IsFull(inst)
    local def = Items.defs[inst.id]
    return not (def and def.fill) or (inst.data and inst.data.fill or 1) >= 1
end

-- Can item `id` sit at x, y in a w x h container holding `items` (uid -> inst)?
function Items.Fits(cw, ch, items, id, x, y, rot, ignoreUid)
    if not Items.defs[id] then return false end
    local w, h = Items.Size(id, rot)
    if x < 0 or y < 0 or x + w > cw or y + h > ch then return false end
    for uid, o in pairs(items) do
        if uid ~= ignoreUid then
            local ow, oh = Items.Size(o.id, o.rot)
            if x < o.x + ow and x + w > o.x and y < o.y + oh and y + h > o.y then
                return false
            end
        end
    end
    return true
end

-- The item covering cell x, y, if any.
function Items.At(items, x, y, ignoreUid)
    for uid, o in pairs(items) do
        if uid ~= ignoreUid then
            local ow, oh = Items.Size(o.id, o.rot)
            if x >= o.x and x < o.x + ow and y >= o.y and y < o.y + oh then
                return o
            end
        end
    end
end

-- If dropping `inst` with its top-left on x, y should merge into a stack, return that stack.
function Items.MergeTarget(items, inst, x, y)
    local def = Items.defs[inst.id]
    if not def or def.stack <= 1 or not Items.IsFull(inst) then return nil end
    local target = Items.At(items, x, y, inst.uid)
    if target and target.id == inst.id and target.count < def.stack and Items.IsFull(target) then
        return target
    end
end

--------------------------------------------------------------------------
-- Network encoding: about 6 bytes per item
--------------------------------------------------------------------------

function Items.WriteInstance(inst)
    local def = Items.defs[inst.id]
    net.WriteUInt(inst.uid, Items.UID_BITS)
    net.WriteUInt(Items.NetId(inst.id), Items.NET_BITS)
    net.WriteUInt(inst.x, Items.POS_BITS)
    net.WriteUInt(inst.y, Items.POS_BITS)
    net.WriteBool(inst.rot and true or false)
    net.WriteUInt(math.Clamp(inst.count, 0, 255), Items.COUNT_BITS)
    if def and def.fill then
        net.WriteUInt(math.Round(math.Clamp(inst.data and inst.data.fill or 1, 0, 1) * 255), 8)
    end
end

function Items.ReadInstance()
    local uid = net.ReadUInt(Items.UID_BITS)
    local def = Items.FromNet(net.ReadUInt(Items.NET_BITS))
    local x = net.ReadUInt(Items.POS_BITS)
    local y = net.ReadUInt(Items.POS_BITS)
    local rot = net.ReadBool()
    local count = net.ReadUInt(Items.COUNT_BITS)
    local data = {}
    if def and def.fill then data.fill = net.ReadUInt(8) / 255 end
    return { uid = uid, id = def and def.id, x = x, y = y, rot = rot, count = count, data = data }
end
