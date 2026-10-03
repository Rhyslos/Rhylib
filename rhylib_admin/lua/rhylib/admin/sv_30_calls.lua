--[[
    Calls: "Call to briefing", "Mission prep" ... a banner on everyone's
    screen (cl_30_calls.lua), optionally with a countdown.

    State is Global2 vars, so players who join later get it too:
        rhylib_call_n      Int, bumped for every new call or end
        rhylib_call_title  String ("" = no call)
        rhylib_call_sub    String
        rhylib_call_by     String
        rhylib_call_at     Float, CurTime it went out
        rhylib_call_end    Float, CurTime the timer ends (0 = untimed)

    Admin.StartCall(title, sub, seconds, byName), Admin.EndCall()
    Presets: config admin.calls; !call <preset|custom> [minutes] [text].
]]

local Admin = Rhylib.Admin
local H = Admin.handlers

local function bump() SetGlobal2Int("rhylib_call_n", GetGlobal2Int("rhylib_call_n", 0) + 1) end

function Admin.StartCall(title, sub, seconds, byName)
    SetGlobal2String("rhylib_call_title", string.sub(title, 1, 60))
    SetGlobal2String("rhylib_call_sub", string.sub(sub or "", 1, 120))
    SetGlobal2String("rhylib_call_by", byName or "")
    SetGlobal2Float("rhylib_call_at", CurTime())
    SetGlobal2Float("rhylib_call_end", seconds > 0 and CurTime() + seconds or 0)
    bump()
    timer.Remove("rhylib_admin_call")
    if seconds > 0 then
        timer.Create("rhylib_admin_call", seconds, 1, function()
            Admin.Log(title .. ": time's up")
        end)
    end
end

function Admin.EndCall()
    if GetGlobal2String("rhylib_call_title", "") == "" then return false end
    timer.Remove("rhylib_admin_call")
    SetGlobal2String("rhylib_call_title", "")
    SetGlobal2Float("rhylib_call_end", 0)
    bump()
    return true
end

local function presets() return Admin.Cfg("calls") or {} end

H.call = function(caller, t, a)
    local id = string.lower(a.preset or "")
    local text = string.Trim(a.text or "")
    local p
    for _, x in ipairs(presets()) do
        if x.id == id then p = x end
    end
    local title, sub
    if id == "custom" then
        if text == "" then return nil, "Give the call's text: !call custom 10 Form up at the hangar" end
        title, sub = text, ""
    elseif not p then
        local ids = {}
        for _, x in ipairs(presets()) do ids[#ids + 1] = x.id end
        ids[#ids + 1] = "custom"
        return nil, "No call \"" .. id .. "\" (" .. table.concat(ids, ", ") .. ")"
    else
        title = p.name or p.id
        sub = text ~= "" and text or (p.sub or "")
    end
    local mins = a.minutes or -1
    if mins < 0 then mins = p and tonumber(p.minutes) or 0 end
    local secs = math.Clamp(math.floor(mins * 60 + 0.5), 0, 36000)
    Admin.StartCall(title, sub, secs, IsValid(caller) and caller:Nick() or "Command")
    local left = secs > 0 and string.format(" (%d:%02d)", math.floor(secs / 60), secs % 60) or ""
    -- (The banner and its chat line are the message; just log it.)
    Admin.Log((IsValid(caller) and caller:Nick() or "Console") .. " called: " .. title .. left)
end

H.endcall = function(caller)
    if not Admin.EndCall() then return nil, "No call is up" end
    return (IsValid(caller) and caller:Nick() or "Console") .. " ended the call"
end
