if not Rhylib then
    print("[Rhylib] rhylib_menus needs rhylib_core. Install it and restart the map.")
    return
end

Rhylib.LoadModule("menus", { name = "Menus", version = "0.1.0" })
