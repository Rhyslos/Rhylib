--[[
    Searching: an MP with the stun baton in hand (RMB on a player) sees
    that player's inventory, backpack and back slot. Taking items needs
    the player to be cuffed; taken items go to the MP's inventory.

    Messages:
      mp.search  client -> server  target (open), or NULL (close)
      mp.list    server -> MP      target, cuffed, then the items
      mp.take    client -> server  target, item uid
]]

local MP = Rhylib.MP
local Items = Rhylib.Items

Rhylib.Net.Register("mp.list")

MP.searching = MP.searching or {}   -- [mp] = target
MP.searchSig = MP.searchSig or {}   -- [mp] = rough checksum of the last list sent

local function inv()
    if not Items then Items = Rhylib.Items end
    return Items and Rhylib.Inventory and Rhylib.Inventory.Get and Rhylib.Inventory or nil
end

local function holdingBaton(ply)
    local w = ply:GetActiveWeapon()
    return IsValid(w) and w:GetClass() == "rhylib_stunbaton"
end

local function canSearch(mp, target)
    if not (IsValid(mp) and IsValid(target) and mp:Alive() and target:Alive()) then return false end
    if mp == target or not MP.IsMP(mp) or MP.IsCuffed(mp) or mp.rhylibDown then return false end
    if not holdingBaton(mp) then return false end
    local r = MP.Cfg("searchRange")
    if mp:GetPos():DistToSqr(target:GetPos()) > r * r then return false end
    local tr = util.TraceLine({ start = mp:EyePos(), endpos = target:WorldSpaceCenter(), filter = { mp, target }, mask = MASK_SOLID })
    return not tr.Hit
end
MP.CanSearch = canSearch

-- Items as rows: uid, item net id, count, fill, container.
function MP.SendList(mp, target)
    local I = inv()
    if not I then return end
    local st = I.Get(target)
    local list = {}
    local sig = 0
    for _, o in pairs(st.byUid) do
        list[#list + 1] = o
        sig = sig + o.uid * 7 + (o.count or 1) * 13 + (o.c or 1)
    end
    MP.searchSig[mp] = sig + #list + (MP.IsCuffed(target) and 1000000 or 0)
    table.sort(list, function(a, b) return (a.c or 0) * 1000 + a.uid < (b.c or 0) * 1000 + b.uid end)
    Rhylib.Net.Start("mp.list")
    net.WriteEntity(target)
    net.WriteBool(MP.IsCuffed(target))
    net.WriteUInt(math.min(#list, 255), 8)
    for i = 1, math.min(#list, 255) do
        local o = list[i]
        net.WriteUInt(o.uid, Items.UID_BITS)
        net.WriteUInt(Items.NetId(o.id), Items.NET_BITS)
        net.WriteUInt(math.Clamp(o.count or 1, 0, 255), 8)
        net.WriteUInt(math.Clamp(math.floor((o.data and o.data.fill or 1) * 100 + 0.5), 0, 100), 7)
        net.WriteUInt(o.c or 1, Items.CONT_BITS)
    end
    net.Send(mp)
end

Rhylib.Net.Receive("mp.search", function(mp)
    local target = net.ReadEntity()
    if not IsValid(target) then
        MP.searching[mp] = nil
        return
    end
    if not target:IsPlayer() or not canSearch(mp, target) or not inv() then return end
    MP.searching[mp] = target
    MP.SendList(mp, target)
    -- Tell them once per search, not on every reopen.
    if (target.rhylibSearchMsg or 0) < CurTime() then
        target.rhylibSearchMsg = CurTime() + 20
        target:ChatPrint(mp:Nick() .. " is searching you")
    end
end, { rate = 3, burst = 3 })

Rhylib.Net.Receive("mp.take", function(mp)
    local target = net.ReadEntity()
    local I = inv()
    if not I then return end
    local uid = net.ReadUInt(Items.UID_BITS)
    if MP.searching[mp] ~= target or not canSearch(mp, target) then return end
    if not MP.IsCuffed(target) then return end
    local st = I.Get(target)
    local o = st.byUid[uid]
    if not o then return end
    if not Items.CanLeave(st, o) then
        mp:ChatPrint("Empty the backpack first")
        return
    end
    -- A gun keeps its current clip and cell.
    I.Internal.captureWeapon(target, o)
    local id, count, data = o.id, o.count or 1, table.Copy(o.data or {})
    I.Internal.removeInst(target, st, uid)
    I.AddOrDrop(mp, id, count, data)
    MP.SendList(mp, target)
    hook.Run("Rhylib.MPConfiscated", mp, target, id, count)
end, { rate = 8, burst = 8 })

local function sigOf(target)
    local I = inv()
    if not I then return 0 end
    local sig, n = 0, 0
    for _, o in pairs(I.Get(target).byUid) do
        n = n + 1
        sig = sig + o.uid * 7 + (o.count or 1) * 13 + (o.c or 1)
    end
    return sig + n + (MP.IsCuffed(target) and 1000000 or 0)
end

-- Keep an open search list fresh while it's open (and drop it when it isn't allowed any more).
timer.Create("Rhylib.MP.Search", 1, 0, function()
    if next(MP.searching) == nil then return end
    for mp, target in pairs(MP.searching) do
        if canSearch(mp, target) then
            if sigOf(target) ~= MP.searchSig[mp] then MP.SendList(mp, target) end
        else
            MP.searching[mp] = nil
            MP.searchSig[mp] = nil
            if IsValid(mp) then
                Rhylib.Net.Start("mp.list")
                net.WriteEntity(NULL)
                net.WriteBool(false)
                net.WriteUInt(0, 8)
                net.Send(mp)
            end
        end
    end
end)

Rhylib.Hook.Add("PlayerDisconnected", "mp.search", function(ply)
    MP.searching[ply] = nil
    MP.searchSig[ply] = nil
    for m, t in pairs(MP.searching) do
        if t == ply then MP.searching[m] = nil end
    end
end)
