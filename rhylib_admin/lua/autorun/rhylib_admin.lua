if not Rhylib then
    print("[Rhylib] rhylib_admin needs rhylib_core. Install it and restart the map.")
    return
end

-- Staff ranks, permissions (CAMI provider), commands, bans and logs.
-- Replaces ULX / SAM / FAdmin.
Rhylib.LoadModule("admin", { name = "Admin", version = "0.1.0" })
