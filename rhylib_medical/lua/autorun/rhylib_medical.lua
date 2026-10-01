if not Rhylib then
    print("[Rhylib] rhylib_medical needs rhylib_core. Install it and restart the map.")
    return
end

Rhylib.LoadModule("medical", { name = "Medical", version = "0.1.0" })
