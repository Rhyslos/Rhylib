--[[
    Networking helpers.

    All Rhylib messages are named "rhylib.<name>".

    1) Client-to-server requests, rate limited per player:
        -- server
        Rhylib.Net.Receive("inv.move", function(ply, len) ... end, { rate = 20, burst = 10 })
        -- client
        Rhylib.Net.Start("inv.move") net.WriteUInt(uid, 16) ... net.SendToServer()

    2) Batches: many small events per tick packed into one message
       per recipient. Used for things like blaster shots.
        -- server (create once, when the file loads)
        local shots = Rhylib.Net.CreateBatch("wep.shots", function(item)
            net.WriteUInt(item.shooter, 8)
            net.WriteVector(item.origin)
        end)
        shots:Send(ply, item)        -- one player
        shots:SendTo(players, item)  -- a list of players
        shots:Broadcast(item)        -- everyone
        -- client
        Rhylib.Net.ReceiveBatch("wep.shots", function()
            return { shooter = net.ReadUInt(8), origin = net.ReadVector() }
        end, function(item) ... end)

       Batches are flushed once per server tick. Each message carries a
       count, so nothing is sent when nothing happened.

    Write exact bit sizes (net.WriteUInt with a bit count). Never use
    net.WriteTable for anything sent often.
]]

Rhylib.Net = Rhylib.Net or {}
local Net = Rhylib.Net

local PREFIX = "rhylib."
local COUNT_BITS = 10                  -- up to 1023 items per message
local MAX_PER_MSG = 1023               -- 2^COUNT_BITS - 1

function Net.Name(name)
    return PREFIX .. name
end

function Net.Register(name)
    if SERVER then util.AddNetworkString(PREFIX .. name) end
end

function Net.Start(name)
    net.Start(PREFIX .. name)
end

-- Send the message that is being written and record its size.
local function finish(name, sendFn, target)
    Rhylib.Profiler.AddNet(name, net.BytesWritten() or 0)
    sendFn(target)
end

--------------------------------------------------------------------------
-- Receiving
--------------------------------------------------------------------------

if SERVER then
    local buckets = {}  -- [name][ply] = { tokens, last }

    -- opts.rate: messages per second allowed, opts.burst: max saved up.
    function Net.Receive(name, fn, opts)
        Net.Register(name)
        local rate = opts and opts.rate or 10
        local burst = opts and opts.burst or rate
        buckets[name] = buckets[name] or setmetatable({}, { __mode = "k" })
        local perPly = buckets[name]

        net.Receive(PREFIX .. name, function(len, ply)
            if not IsValid(ply) then return end
            local now = SysTime()
            local b = perPly[ply]
            if not b then
                b = { tokens = burst, last = now }
                perPly[ply] = b
            end
            b.tokens = math.min(burst, b.tokens + (now - b.last) * rate)
            b.last = now
            if b.tokens < 1 then return end  -- over the limit: drop silently
            b.tokens = b.tokens - 1
            fn(ply, len)
        end)
    end
else
    function Net.Receive(name, fn)
        net.Receive(PREFIX .. name, function(len)
            fn(len)
        end)
    end
end

--------------------------------------------------------------------------
-- Batches
--------------------------------------------------------------------------

if SERVER then
    local Batch = {}
    Batch.__index = Batch

    Net.batches = Net.batches or {}

    function Net.CreateBatch(name, writeItem)
        Net.Register(name)
        local b = Net.batches[name]
        if b then
            b.write = writeItem  -- autorefresh: keep queues, swap the writer
            return b
        end
        b = setmetatable({ name = name, write = writeItem, perPly = {}, all = {} }, Batch)
        Net.batches[name] = b
        return b
    end

    function Batch:Send(ply, item)
        local q = self.perPly[ply]
        if not q then
            q = {}
            self.perPly[ply] = q
        end
        q[#q + 1] = item
        self.dirty = true
    end

    function Batch:SendTo(players, item)
        for i = 1, #players do self:Send(players[i], item) end
    end

    function Batch:Broadcast(item)
        self.all[#self.all + 1] = item
        self.dirty = true
    end

    local function sendQueue(batch, queue, sendFn, target)
        local total, i = #queue, 1
        while i <= total do
            local count = math.min(MAX_PER_MSG, total - i + 1)
            net.Start(PREFIX .. batch.name)
            net.WriteUInt(count, COUNT_BITS)
            for j = i, i + count - 1 do batch.write(queue[j]) end
            finish(batch.name, sendFn, target)
            i = i + count
        end
    end

    local function clear(q)
        for i = #q, 1, -1 do q[i] = nil end
    end

    -- Queue tables are kept and emptied, so a busy tick allocates nothing
    -- here and an idle tick costs one flag check.
    function Batch:Flush()
        if not self.dirty then return end
        self.dirty = false
        for ply, q in pairs(self.perPly) do
            if not IsValid(ply) then
                self.perPly[ply] = nil  -- allowed while iterating with pairs
            elseif #q > 0 then
                sendQueue(self, q, net.Send, ply)
                clear(q)
            end
        end
        if #self.all > 0 then
            sendQueue(self, self.all, net.Broadcast)
            clear(self.all)
        end
    end

    -- Runs last in the tick, after modules have queued their events.
    Rhylib.Hook.Add("Tick", "core.net.flush", function()
        for _, b in pairs(Net.batches) do b:Flush() end
    end, 1000)
else
    function Net.ReceiveBatch(name, readItem, onItem)
        net.Receive(PREFIX .. name, function()
            local count = net.ReadUInt(COUNT_BITS)
            for _ = 1, count do onItem(readItem()) end
        end)
    end
end
