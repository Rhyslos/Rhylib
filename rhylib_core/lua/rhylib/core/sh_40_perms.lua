--[[
    Permissions through CAMI.

    CAMI is the shared permission standard that ULX, SAM, sAdmin and others
    support. With rhylib_admin installed its staff ranks answer directly
    (Rhylib.Admin.Has). Otherwise CAMI, and without an admin mod GMod's own
    admin and superadmin flags.

        Rhylib.Perms.Register("rhylib.admin.teleport", "admin", "Teleport players")

        Rhylib.Perms.Check(ply, "rhylib.admin.teleport", function(allowed)
            if not allowed then return end
            ...
        end)

    Checks are asynchronous because CAMI is. The server console always passes.
]]

Rhylib.Perms = Rhylib.Perms or {}
local Perms = Rhylib.Perms

Perms.list = Perms.list or {}  -- [name] = { minAccess, desc }

local function registerWithCAMI(name, p)
    if not CAMI then return end
    CAMI.RegisterPrivilege({ Name = name, MinAccess = p.minAccess, Description = p.desc })
end

-- minAccess: "user", "admin" or "superadmin"
function Perms.Register(name, minAccess, desc)
    local p = { minAccess = minAccess or "admin", desc = desc or "" }
    Perms.list[name] = p
    registerWithCAMI(name, p)
end

local function fallback(ply, minAccess)
    if minAccess == "user" then return true end
    if minAccess == "admin" then return ply:IsAdmin() end
    return ply:IsSuperAdmin()
end

function Perms.Check(ply, name, callback)
    if not IsValid(ply) then callback(true) return end

    local p = Perms.list[name]
    if not p then
        Rhylib.Warn("perms", "Unknown permission %s", name)
        callback(false)
        return
    end

    local Admin = Rhylib.Admin
    if Admin and Admin.Has then
        callback(Admin.Has(ply, name, p.minAccess))
    elseif CAMI then
        CAMI.PlayerHasAccess(ply, name, function(allowed)
            callback(allowed and true or false)
        end)
    else
        callback(fallback(ply, p.minAccess))
    end
end

-- Admin mods may load after us, so register everything again once the
-- gamemode has started.
Rhylib.Hook.Add("Initialize", "core.perms.cami", function()
    for name, p in pairs(Perms.list) do registerWithCAMI(name, p) end
end)
