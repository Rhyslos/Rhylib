--[[
    Datapad sync: download the battalion computer's logs and board to the
    datapad, anywhere (uploading still happens at the computer).

    Each battalion has a version (os.time of its last change, Data
    "dp_ver"/battalion). Any change to its logs or board bumps it and tells
    the battalion's online members (dp.ver), so their datapad can show
    that there's something new.

      dp.dl     datapad: download -> dp.dldata (version, log list, board list)
      dp.dread  datapad: kind (0 log, 1 post), id -> dp.dbody
]]

local D = Rhylib.Datapad

for _, n in ipairs({ "dp.ver", "dp.dldata", "dp.dbody" }) do Rhylib.Net.Register(n) end

function D.Version(bn)
    return D.Load("dp_ver", bn, {}).v or 0
end

function D.Touch(bn)
    local t = D.Load("dp_ver", bn, {})
    t.v = math.max((t.v or 0) + 1, os.time())
    D.Store("dp_ver", bn, t)
    local list = {}
    for _, p in ipairs(player.GetHumans()) do
        if D.Battalion(p) == bn then list[#list + 1] = p end
    end
    if #list == 0 then return end
    Rhylib.Net.Start("dp.ver")
    net.WriteString(bn)
    net.WriteUInt(t.v, 32)
    net.Send(list)
end

-- Every save of a battalion's logs or board counts as a change.
local store = D.Store
function D.Store(ns, key, v)
    store(ns, key, v)
    if (ns == "dp_log" or ns == "dp_board") and string.sub(key, 1, 2) ~= "__" then D.Touch(key) end
end

D.PadRecv("dp.dl", function(ply)
    local bn = D.Battalion(ply)
    if bn == "" then return end
    local logs = D.Book(bn).list
    local posts = D.Board and D.Board(bn).list or {}
    Rhylib.Net.Start("dp.dldata")
    net.WriteString(bn)
    net.WriteUInt(D.Version(bn), 32)
    local n = math.min(#logs, 200)
    net.WriteUInt(n, 8)
    for i = 1, n do
        local e = logs[i]
        net.WriteUInt(e.id, 20)
        net.WriteString(e.a or "?")
        net.WriteString(e.ti or "")
        net.WriteUInt(e.t or 0, 32)
        net.WriteBool(e.mp or false)
    end
    n = math.min(#posts, 120)
    net.WriteUInt(n, 7)
    for i = 1, n do
        local p = posts[i]
        net.WriteUInt(p.id, 16)
        net.WriteUInt(p.sec or 1, 2)
        net.WriteString(p.ti or "")
        net.WriteString(p.a or "?")
        net.WriteUInt(p.t or 0, 32)
        net.WriteUInt(p.at or 0, 32)
        net.WriteBool(p.pin or false)
    end
    net.Send(ply)
end, { rate = 1, burst = 2 })

D.PadRecv("dp.dread", function(ply)
    local kind = net.ReadUInt(1)
    local id = net.ReadUInt(20)
    local bn = D.Battalion(ply)
    if bn == "" then return end
    local list = kind == 0 and D.Book(bn).list or (D.Board and D.Board(bn).list or {})
    for _, e in ipairs(list) do
        if e.id == id then
            Rhylib.Net.Start("dp.dbody")
            net.WriteUInt(kind, 1)
            net.WriteUInt(id, 20)
            net.WriteString(e.b or "")
            net.Send(ply)
            return
        end
    end
end, { rate = 4, burst = 6 })
