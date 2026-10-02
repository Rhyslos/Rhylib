if not Rhylib then
    print("[Rhylib] rhylib_roster needs rhylib_core. Install it and restart the map.")
    return
end

-- Characters, ranks and battalion membership. The UI uses rhylib_menus.
Rhylib.LoadModule("roster", { name = "Roster", version = "0.1.0" })
