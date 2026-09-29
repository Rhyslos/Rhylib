--[[
    Rhylib core loader.

    The file name starts with an underscore so it sorts before other
    autorun files and runs first. Every other Rhylib addon has its own
    autorun file that calls Rhylib.LoadModule("<id>").
]]

Rhylib = Rhylib or {}
Rhylib.Version = "0.1.0"
Rhylib.Modules = Rhylib.Modules or {}

local COLOR_TAG = Color(120, 170, 255)
local COLOR_TEXT = Color(230, 230, 230)
local COLOR_WARN = Color(255, 190, 80)

function Rhylib.Print(module, fmt, ...)
    MsgC(COLOR_TAG, "[Rhylib:" .. module .. "] ", COLOR_TEXT, string.format(fmt, ...), "\n")
end

function Rhylib.Warn(module, fmt, ...)
    MsgC(COLOR_TAG, "[Rhylib:" .. module .. "] ", COLOR_WARN, string.format(fmt, ...), "\n")
end

function Rhylib.Error(module, fmt, ...)
    ErrorNoHalt("[Rhylib:" .. module .. "] " .. string.format(fmt, ...) .. "\n")
end

-- Load one file by its realm prefix: sh_ (both), sv_ (server), cl_ (client).
local function loadFile(path, prefix)
    if prefix == "sh_" then
        if SERVER then AddCSLuaFile(path) end
        include(path)
    elseif prefix == "sv_" then
        if SERVER then include(path) end
    elseif prefix == "cl_" then
        if SERVER then
            AddCSLuaFile(path)
        else
            include(path)
        end
    end
end

--[[
    Load every file in lua/rhylib/<id>/.
    Shared files load first, then server, then client. Within each group,
    files load in alphabetical order, so number them to control order
    (sh_00_first.lua, sh_10_second.lua, ...).
]]
function Rhylib.LoadModule(id, info)
    if Rhylib.Modules[id] then return Rhylib.Modules[id] end

    local dir = "rhylib/" .. id .. "/"
    local files = file.Find(dir .. "*.lua", "LUA")
    table.sort(files)

    local count = 0
    for _, prefix in ipairs({ "sh_", "sv_", "cl_" }) do
        for _, name in ipairs(files) do
            if string.sub(name, 1, 3) == prefix then
                loadFile(dir .. name, prefix)
                count = count + 1
            end
        end
    end

    local mod = {
        id = id,
        name = info and info.name or id,
        version = info and info.version or "0.0.0",
        files = count,
    }
    Rhylib.Modules[id] = mod
    Rhylib.Print("core", "Loaded module %s %s (%d files)", mod.name, mod.version, count)

    hook.Run("Rhylib.ModuleLoaded", id, mod)
    return mod
end

--[[
    Host overrides live in lua/rhylib_config/*.lua, ideally in a separate
    addon folder so Workshop updates never overwrite them.
]]
function Rhylib.LoadConfigFiles()
    local files = file.Find("rhylib_config/*.lua", "LUA")
    table.sort(files)
    for _, name in ipairs(files) do
        local path = "rhylib_config/" .. name
        if SERVER then AddCSLuaFile(path) end
        include(path)
    end
end

Rhylib.LoadModule("core", { name = "Core", version = Rhylib.Version })
Rhylib.LoadConfigFiles()
hook.Run("Rhylib.CoreLoaded")
