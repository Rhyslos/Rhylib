if not Rhylib then
    print("[Rhylib] rhylib_stamina needs rhylib_core. Install it and restart the map.")
    return
end

Rhylib.LoadModule("stamina", { name = "Stamina", version = "0.1.0" })
