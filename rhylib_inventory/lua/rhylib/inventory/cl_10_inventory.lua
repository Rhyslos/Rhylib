--[[
    Client copy of your own inventory. Filled once from "inv.full", then
    kept up to date by the batched "inv.upd" changes. The UI reads it.

    Same shape as the server: Inv.cont[cid] = { w, h, items }, Inv.byUid.
]]

Rhylib.Inventory = Rhylib.Inventory or {}
local Inv = Rhylib.Inventory
local Items = Rhylib.Items

Inv.cont = Inv.cont or { [Items.MAIN] = { w = 5, h = 3, items = {} }, [Items.SLOT_BACK] = { w = 1, h = 1, items = {} } }
Inv.byUid = Inv.byUid or {}

local function setInst(inst)
    if not inst.id then return end
    local old = Inv.byUid[inst.uid]
    if old and Inv.cont[old.c] then Inv.cont[old.c].items[old.uid] = nil end
    local c = Inv.cont[inst.c]
    if not c then return end
    c.items[inst.uid] = inst
    Inv.byUid[inst.uid] = inst
end

local function removeInst(uid)
    local old = Inv.byUid[uid]
    if not old then return end
    if Inv.cont[old.c] then Inv.cont[old.c].items[uid] = nil end
    Inv.byUid[uid] = nil
end

local function setDims(cid, w, h)
    if w == 0 or h == 0 then
        Inv.cont[cid] = nil
        return
    end
    local cur = Inv.cont[cid]
    Inv.cont[cid] = { w = w, h = h, items = cur and cur.items or {} }
end

net.Receive(Rhylib.Net.Name("inv.full"), function()
    Items.EnsureReady()
    Inv.cont = {}
    Inv.byUid = {}
    local nc = net.ReadUInt(Items.CONT_BITS + 1)
    for _ = 1, nc do
        local cid = net.ReadUInt(Items.CONT_BITS)
        setDims(cid, net.ReadUInt(5), net.ReadUInt(5))
    end
    local n = net.ReadUInt(8)
    for _ = 1, n do setInst(Items.ReadInstance()) end
end)

Rhylib.Net.ReceiveBatch("inv.upd", function()
    local op = net.ReadUInt(2)
    if op == 1 then return { op = 1, inst = Items.ReadInstance() } end
    if op == 0 then return { op = 0, uid = net.ReadUInt(Items.UID_BITS) } end
    return { op = 2, cid = net.ReadUInt(Items.CONT_BITS), w = net.ReadUInt(5), h = net.ReadUInt(5) }
end, function(ch)
    if ch.op == 1 then
        setInst(ch.inst)
    elseif ch.op == 0 then
        removeInst(ch.uid)
    else
        setDims(ch.cid, ch.w, ch.h)
    end
end)

function Inv.RequestFull()
    Rhylib.Net.Start("inv.req")
    net.SendToServer()
end

-- Moves locally right away so dragging feels instant; the server confirms
-- or sends the item back where it was.
function Inv.RequestMove(inst, cid, x, y, rot)
    local c = Inv.cont[cid]
    if not c then return end
    if cid ~= inst.c and not Items.CanLeave(Inv, inst) then return end

    local merge = cid ~= Items.SLOT_BACK and Items.MergeTarget(c.items, inst, x, y)
    if not merge then
        if not Items.CanPlace(Inv, inst.id, cid, x, y, rot, inst.uid) then return end
        local moved = { uid = inst.uid, id = inst.id, c = cid, x = x, y = y, rot = rot, count = inst.count, data = inst.data }
        setInst(moved)
    end

    Rhylib.Net.Start("inv.move")
    net.WriteUInt(inst.uid, Items.UID_BITS)
    net.WriteUInt(cid, Items.CONT_BITS)
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
