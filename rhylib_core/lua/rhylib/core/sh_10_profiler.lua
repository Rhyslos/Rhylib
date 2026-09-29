--[[
    Profiler.

    Off by default and free when off. Turn it on with:
        rhylib_profile 1
    Then after some play, print the results:
        rhylib_profile_report       (server; console or superadmin)
        rhylib_profile_report_cl    (your client)
    rhylib_profile_reset clears the numbers.

    It records time spent in every hook handler registered through
    Rhylib.Hook, and bytes sent by Rhylib net messages.
]]

Rhylib.Profiler = Rhylib.Profiler or {}
local Profiler = Rhylib.Profiler

Profiler.enabled = Profiler.enabled or false
Profiler.hooks = Profiler.hooks or {}  -- [key] = { t = seconds, n = calls }
Profiler.net = Profiler.net or {}      -- [name] = { bytes, n }
Profiler.since = SysTime()

function Profiler.AddTime(key, dt)
    local e = Profiler.hooks[key]
    if not e then
        e = { t = 0, n = 0 }
        Profiler.hooks[key] = e
    end
    e.t = e.t + dt
    e.n = e.n + 1
end

function Profiler.AddNet(name, bytes)
    if not Profiler.enabled then return end
    local e = Profiler.net[name]
    if not e then
        e = { bytes = 0, n = 0 }
        Profiler.net[name] = e
    end
    e.bytes = e.bytes + bytes
    e.n = e.n + 1
end

function Profiler.Reset()
    Profiler.hooks = {}
    Profiler.net = {}
    Profiler.since = SysTime()
end

function Profiler.SetEnabled(on)
    if Profiler.enabled == on then return end
    Profiler.enabled = on
    Profiler.Reset()
    -- The hook bus swaps to its timed dispatchers (or back).
    if Rhylib.Hook and Rhylib.Hook.RebuildAll then Rhylib.Hook.RebuildAll() end
end

local function sortedByValue(tbl, field)
    local rows = {}
    for key, e in pairs(tbl) do rows[#rows + 1] = { key = key, e = e } end
    table.sort(rows, function(a, b) return a.e[field] > b.e[field] end)
    return rows
end

function Profiler.Report(print)
    local elapsed = math.max(SysTime() - Profiler.since, 0.001)
    print(string.format("Rhylib profile over %.1f s (%s)", elapsed, SERVER and "server" or "client"))

    print("Hooks (ms per second of play, calls per second):")
    local rows = sortedByValue(Profiler.hooks, "t")
    for i = 1, math.min(#rows, 25) do
        local r = rows[i]
        print(string.format("  %-40s %8.3f ms/s %8.1f calls/s", r.key, r.e.t * 1000 / elapsed, r.e.n / elapsed))
    end
    if #rows == 0 then print("  (nothing recorded)") end

    print("Net (bytes per second, messages per second):")
    rows = sortedByValue(Profiler.net, "bytes")
    for i = 1, math.min(#rows, 25) do
        local r = rows[i]
        print(string.format("  %-40s %8.0f B/s %8.1f msg/s", r.key, r.e.bytes / elapsed, r.e.n / elapsed))
    end
    if #rows == 0 then print("  (nothing recorded)") end
end

local cvar = CreateConVar("rhylib_profile", "0", { FCVAR_ARCHIVE }, "Record Rhylib hook time and net traffic (0/1)")
Profiler.SetEnabled(cvar:GetBool())
cvars.AddChangeCallback("rhylib_profile", function(_, _, new)
    Profiler.SetEnabled(new == "1")
end, "Rhylib.Profiler")

if SERVER then
    local function allowed(ply)
        return not IsValid(ply) or ply:IsSuperAdmin()
    end

    concommand.Add("rhylib_profile_report", function(ply)
        if not allowed(ply) then return end
        Profiler.Report(function(line)
            if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
        end)
    end)

    concommand.Add("rhylib_profile_reset", function(ply)
        if not allowed(ply) then return end
        Profiler.Reset()
    end)

    concommand.Add("rhylib_status", function(ply)
        if not allowed(ply) then return end
        local out = function(line)
            if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
        end
        out("Rhylib " .. Rhylib.Version .. ", modules:")
        for id, mod in SortedPairs(Rhylib.Modules) do
            out(string.format("  %-16s %-8s %d files", id, mod.version, mod.files))
        end
    end)
else
    concommand.Add("rhylib_profile_report_cl", function()
        Profiler.Report(print)
    end)
end
