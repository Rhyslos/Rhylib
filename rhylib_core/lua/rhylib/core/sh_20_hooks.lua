--[[
    Hook bus.

    Every Rhylib module registers here instead of calling hook.Add directly:
        Rhylib.Hook.Add("PlayerDeath", "medic.downed", function(ply) ... end)
        Rhylib.Hook.Add("Tick", "weapons.bolts", stepBolts, 10)   -- priority 10

    For each event, the bus puts exactly one real hook into GMod
    ("Rhylib.Bus") and calls the module handlers from a flat array.
    That gives us:
      - one engine hook per event, no matter how many modules are loaded
      - a fixed call order (lower priority number runs first)
      - per-handler timing when the profiler is on, at zero cost when off

    Like normal GMod hooks, a handler that returns a non-nil value stops
    the chain and that value is returned to the engine.
]]

Rhylib.Hook = Rhylib.Hook or {}
local Hook = Rhylib.Hook

Hook.events = Hook.events or {}  -- [event] = { entries = { ... }, order = n }

local HOOK_ID = "Rhylib.Bus"

local function rebuild(event)
    local ev = Hook.events[event]
    if not ev or #ev.entries == 0 then
        hook.Remove(event, HOOK_ID)
        Hook.events[event] = nil
        return
    end

    table.sort(ev.entries, function(a, b)
        if a.priority ~= b.priority then return a.priority < b.priority end
        return a.order < b.order
    end)

    -- Copy into plain arrays so adding or removing a handler while the
    -- event is running never changes the array being looped over.
    local fns, keys, n = {}, {}, #ev.entries
    for i = 1, n do
        fns[i] = ev.entries[i].fn
        keys[i] = event .. "/" .. ev.entries[i].id
    end

    local dispatch
    if Rhylib.Profiler.enabled then
        local addTime, clock = Rhylib.Profiler.AddTime, SysTime
        dispatch = function(...)
            for i = 1, n do
                local t = clock()
                local a, b, c, d, e, f = fns[i](...)
                addTime(keys[i], clock() - t)
                if a ~= nil then return a, b, c, d, e, f end
            end
        end
    else
        dispatch = function(...)
            for i = 1, n do
                local a, b, c, d, e, f = fns[i](...)
                if a ~= nil then return a, b, c, d, e, f end
            end
        end
    end

    hook.Add(event, HOOK_ID, dispatch)
end

function Hook.Add(event, id, fn, priority)
    local ev = Hook.events[event]
    if not ev then
        ev = { entries = {}, order = 0 }
        Hook.events[event] = ev
    end

    -- Replace an existing handler with the same id (safe with Lua autorefresh).
    for i, e in ipairs(ev.entries) do
        if e.id == id then
            table.remove(ev.entries, i)
            break
        end
    end

    ev.order = ev.order + 1
    ev.entries[#ev.entries + 1] = { id = id, fn = fn, priority = priority or 0, order = ev.order }
    rebuild(event)
end

function Hook.Remove(event, id)
    local ev = Hook.events[event]
    if not ev then return end
    for i, e in ipairs(ev.entries) do
        if e.id == id then
            table.remove(ev.entries, i)
            rebuild(event)
            return
        end
    end
end

function Hook.RebuildAll()
    for event in pairs(Hook.events) do rebuild(event) end
end

-- Rebuild once in case the profiler flag changed before this file loaded.
Hook.RebuildAll()
