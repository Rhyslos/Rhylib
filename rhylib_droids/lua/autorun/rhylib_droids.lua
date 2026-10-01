if not Rhylib then
    print("[Rhylib] rhylib_droids needs rhylib_core. Install it and restart the map.")
    return
end

-- Droids shoot rhylib_weapons bolts; it's looked up when they fire.
Rhylib.LoadModule("droids", { name = "Droids", version = "0.1.0" })
