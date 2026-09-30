if not Rhylib then
    print("[Rhylib] rhylib_hud needs rhylib_core. Install it and restart the map.")
    return
end

Rhylib.LoadModule("hud", { name = "HUD", version = "0.1.0" })
