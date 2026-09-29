--[[
    Data layer (server only), stored in GMod's built-in SQLite database
    (garrysmod/sv.db). Nothing to install.

    A simple key/value store per module. Values can be any table, string,
    number or boolean.

        Rhylib.Data.Set("inventory", ply:SteamID64(), invTable)
        local inv = Rhylib.Data.Get("inventory", ply:SteamID64())
        Rhylib.Data.Delete("inventory", steamid)

    Writes are queued and saved together every few seconds in one
    transaction, so saving never costs a frame. Reads check the queue
    first, so they always return the latest value. Everything is saved
    immediately on server shutdown and map change.
]]

Rhylib.Data = Rhylib.Data or {}
local Data = Rhylib.Data

local TABLE = "rhylib_kv"
local FLUSH_DELAY = 3  -- seconds

Rhylib.Config.Register("core", "dataFlushDelay", FLUSH_DELAY, "Seconds between batched database saves")

sql.Query("CREATE TABLE IF NOT EXISTS " .. TABLE .. " (module TEXT NOT NULL, key TEXT NOT NULL, value TEXT, PRIMARY KEY (module, key))")

Data.pending = Data.pending or {}  -- [module][key] = encoded string, or false to delete
local pending = Data.pending
local DELETE = false

local function encode(value)
    return util.TableToJSON({ v = value })
end

local function decode(str)
    if not str then return nil end
    local t = util.JSONToTable(str)
    return t and t.v
end

function Data.Flush()
    if next(pending) == nil then return end

    sql.Begin()
    for module, keys in pairs(pending) do
        local m = sql.SQLStr(module)
        for key, value in pairs(keys) do
            local k = sql.SQLStr(key)
            if value == DELETE then
                sql.Query("DELETE FROM " .. TABLE .. " WHERE module = " .. m .. " AND key = " .. k)
            else
                sql.Query("INSERT OR REPLACE INTO " .. TABLE .. " (module, key, value) VALUES (" .. m .. ", " .. k .. ", " .. sql.SQLStr(value) .. ")")
            end
        end
    end
    sql.Commit()

    local err = sql.LastError()
    if err and err ~= "" and err ~= Data.lastError then
        Data.lastError = err
        Rhylib.Error("data", "SQLite: %s", err)
    end

    Data.pending = {}
    pending = Data.pending
end

local function scheduleFlush()
    if timer.Exists("Rhylib.Data.Flush") then return end
    timer.Create("Rhylib.Data.Flush", Rhylib.Config.Get("core", "dataFlushDelay"), 1, Data.Flush)
end

function Data.Set(module, key, value)
    key = tostring(key)
    pending[module] = pending[module] or {}
    pending[module][key] = encode(value)
    scheduleFlush()
end

function Data.Delete(module, key)
    key = tostring(key)
    pending[module] = pending[module] or {}
    pending[module][key] = DELETE
    scheduleFlush()
end

function Data.Get(module, key)
    key = tostring(key)
    local p = pending[module]
    if p and p[key] ~= nil then
        if p[key] == DELETE then return nil end
        return decode(p[key])
    end

    local row = sql.QueryRow("SELECT value FROM " .. TABLE .. " WHERE module = " .. sql.SQLStr(module) .. " AND key = " .. sql.SQLStr(key))
    return row and decode(row.value)
end

Rhylib.Hook.Add("ShutDown", "core.data.flush", Data.Flush)
