--[[
    Client copy of your own inventory. Filled once from "inv.full", then
    kept up to date by the batched "inv.upd" changes. The UI reads it.
]]

Rhylib.Inventory = Rhylib.Inventory or {}
local Inv = Rhylib.Inventory
local Items = Rhylib.Items

Inv.w = Inv.w or 5
Inv.h = Inv.h or 3
Inv.items = Inv.items or {}   -- [uid] = inst

net.Receive(Rhylib.Net.Name("inv.full"), function()
    Items.EnsureReady()
    Inv.w = net.ReadUInt(5)
    Inv.h = net.ReadUInt(5)
    local n = net.ReadUInt(8)
    local items = {}
    for _ = 1, n do
        local inst = Items.ReadInstance()
        if inst.id then items[inst.uid] = inst end
    end
    Inv.items = items
end)

Rhylib.Net.ReceiveBatch("inv.upd", function()
    local set = net.ReadBool()
    if set then return { set = true, inst = Items.ReadInstance() } end
    return { set = false, uid = net.ReadUInt(Items.UID_BITS) }
end, function(ch)
    if ch.set then
        if ch.inst.id then Inv.items[ch.inst.uid] = ch.inst end
    else
        Inv.items[ch.uid] = nil
    end
end)

function Inv.RequestFull()
    Rhylib.Net.Start("inv.req")
    net.SendToServer()
end

-- Moves locally right away so dragging feels instant; the server confirms
-- or sends the item back where it was.
function Inv.RequestMove(inst, x, y, rot)
    local target = Items.MergeTarget(Inv.items, inst, x, y)
    if not target then
        if not Items.Fits(Inv.w, Inv.h, Inv.items, inst.id, x, y, rot, inst.uid) then return end
        inst.x, inst.y, inst.rot = x, y, rot
    end
    Rhylib.Net.Start("inv.move")
    net.WriteUInt(inst.uid, Items.UID_BITS)
    net.WriteUInt(x, Items.POS_BITS)
    net.WriteUInt(y, Items.POS_BITS)
    net.WriteBool(rot)
    net.SendToServer()
end

function Inv.RequestDrop(inst)
    Rhylib.Net.Start("inv.drop")
    net.WriteUInt(inst.uid, Items.UID_BITS)
    net.SendToServer()
end

function Inv.RequestUse(inst)
    Rhylib.Net.Start("inv.use")
    net.WriteUInt(inst.uid, Items.UID_BITS)
    net.SendToServer()
end

Rhylib.Hook.Add("InitPostEntity", "inventory.request", function()
    Inv.RequestFull()
end)

-- After a Lua refresh the player already exists, so ask again.
if IsValid(LocalPlayer()) then Inv.RequestFull() end
