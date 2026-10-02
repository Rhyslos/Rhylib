--[[
    Battalion computer: log search, and the battalion board.

    Search (logs and medical records):
      dp.tfind   entity, text, days (0 = any time) -> dp.tfound: matching ids
                 (title, text, author or patient contain the text)

    Board (battalion computers only): posts in sections Info, Plans and
    Sessions. A session has a time (os.time, shown in each player's own
    time zone); past sessions are listed as an archive. Posts can be pinned.
    Who may post: admins and the battalion's commander for now, or anyone
    the Rhylib.CanPostBoard(ply, battalion) hook allows (the rank system).
      dp.bopen   entity -> dp.board: canPost, posts (no text)
      dp.bget    entity, id -> dp.bbody
      dp.bsave   entity, id (0 = new), section, title, text, time
      dp.bdel    entity, id
      dp.bpin    entity, id

    Data "dp_board"/battalion = { next, list }.
]]

local D = Rhylib.Datapad

Rhylib.Net.Register("dp.tfound")
Rhylib.Net.Register("dp.board")
Rhylib.Net.Register("dp.bbody")

D.SEC_INFO, D.SEC_PLANS, D.SEC_SESSION = 1, 2, 3
local BOARD_CAP = 120

--------------------------------------------------------------------------
-- Search
--------------------------------------------------------------------------

D.TermRecv("dp.tfind", {
    read = function() return { q = string.lower(D.Clip(net.ReadString(), 64)), days = net.ReadUInt(10) } end,
    run = function(ply, ent, a, arg)
        local key = D.TermKey(ent)
        if not a.view or key == "" then return end
        local since = arg.days > 0 and (os.time() - arg.days * 86400) or 0
        local q = arg.q
        local out = {}
        for _, e in ipairs(D.Book(key).list) do
            if (e.t or 0) >= since and (q == "" or string.find(string.lower((e.ti or "") .. "\n" .. (e.b or "") .. "\n" .. (e.a or "") .. "\n" .. (e.pn or "")), q, 1, true)) then
                out[#out + 1] = e.id
                if #out >= 255 then break end
            end
        end
        Rhylib.Net.Start("dp.tfound")
        net.WriteUInt(#out, 8)
        for _, id in ipairs(out) do net.WriteUInt(id, 20) end
        net.Send(ply)
    end,
}, { rate = 3, burst = 4 })

--------------------------------------------------------------------------
-- Board
--------------------------------------------------------------------------

function D.Board(bn)
    local b = D.Load("dp_board", bn, nil)
    if not b.list then b.next, b.list = 1, {} end
    return b
end

function D.CanPost(ply, bn, admin)
    if admin then return true end
    local r = hook.Run("Rhylib.CanPostBoard", ply, bn)
    if r ~= nil then return r end
    return D.Battalion(ply) == bn and D.IsCommander(ply)
end

local function sendBoard(ply, ent, a)
    local bn = ent:GetBattalion()
    local list = bn ~= "" and a.view and D.Board(bn).list or {}
    Rhylib.Net.Start("dp.board")
    net.WriteEntity(ent)
    net.WriteBool(bn ~= "" and D.CanPost(ply, bn, a.admin))
    local n = math.min(#list, 255)
    net.WriteUInt(n, 8)
    for i = 1, n do
        local p = list[i]
        net.WriteUInt(p.id, 16)
        net.WriteUInt(p.sec or 1, 2)
        net.WriteString(p.ti or "")
        net.WriteString(p.a or "?")
        net.WriteUInt(p.t or 0, 32)
        net.WriteUInt(p.at or 0, 32)
        net.WriteBool(p.pin or false)
    end
    net.Send(ply)
end

local function boardTerm(ent) return not D.IsMedTerm(ent) and ent:GetBattalion() ~= "" end

local function findPost(board, id)
    for i, p in ipairs(board.list) do
        if p.id == id then return p, i end
    end
end

D.TermRecv("dp.bopen", {
    run = function(ply, ent, a)
        if boardTerm(ent) then sendBoard(ply, ent, a) end
    end,
}, { rate = 3, burst = 4 })

D.TermRecv("dp.bget", {
    read = function() return net.ReadUInt(16) end,
    run = function(ply, ent, a, id)
        if not boardTerm(ent) or not a.view then return end
        local p = findPost(D.Board(ent:GetBattalion()), id)
        if not p then return end
        Rhylib.Net.Start("dp.bbody")
        net.WriteUInt(p.id, 16)
        net.WriteString(p.b or "")
        net.Send(ply)
    end,
})

D.TermRecv("dp.bsave", {
    read = function()
        return {
            id = net.ReadUInt(16), sec = net.ReadUInt(2),
            ti = D.Clip(net.ReadString(), D.Cfg("titleMax")),
            b = D.Clip(net.ReadString(), D.Cfg("bodyMax"), true),
            at = net.ReadUInt(32),
        }
    end,
    run = function(ply, ent, a, arg)
        if not boardTerm(ent) then return end
        local bn = ent:GetBattalion()
        if not D.CanPost(ply, bn, a.admin) then return end
        if arg.sec < D.SEC_INFO or arg.sec > D.SEC_SESSION then return end
        if arg.ti == "" then arg.ti = "Untitled" end
        local at = arg.sec == D.SEC_SESSION and arg.at or 0
        local board = D.Board(bn)
        if arg.id == 0 then
            table.insert(board.list, 1, {
                id = board.next, sec = arg.sec, ti = arg.ti, b = arg.b, at = at,
                a = ply:Nick(), s = ply:SteamID64(), t = os.time(),
            })
            board.next = board.next % 65535 + 1
            while #board.list > BOARD_CAP do table.remove(board.list) end
        else
            local p = findPost(board, arg.id)
            if not p then return end
            p.sec, p.ti, p.b, p.at = arg.sec, arg.ti, arg.b, at
        end
        D.Store("dp_board", bn, board)
        sendBoard(ply, ent, a)
    end,
}, { rate = 2, burst = 3 })

D.TermRecv("dp.bdel", {
    read = function() return net.ReadUInt(16) end,
    run = function(ply, ent, a, id)
        if not boardTerm(ent) then return end
        local bn = ent:GetBattalion()
        if not D.CanPost(ply, bn, a.admin) then return end
        local board = D.Board(bn)
        local _, i = findPost(board, id)
        if not i then return end
        table.remove(board.list, i)
        D.Store("dp_board", bn, board)
        sendBoard(ply, ent, a)
    end,
})

D.TermRecv("dp.bpin", {
    read = function() return net.ReadUInt(16) end,
    run = function(ply, ent, a, id)
        if not boardTerm(ent) then return end
        local bn = ent:GetBattalion()
        if not D.CanPost(ply, bn, a.admin) then return end
        local board = D.Board(bn)
        local p = findPost(board, id)
        if not p then return end
        p.pin = not p.pin or nil
        D.Store("dp_board", bn, board)
        sendBoard(ply, ent, a)
    end,
})
