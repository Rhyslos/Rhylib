if not Rhylib then
    print("[Rhylib] rhylib_weapons needs rhylib_core. Install it and restart the map.")
    return
end

Rhylib.LoadModule("weapons", { name = "Weapons", version = "0.1.0" })
