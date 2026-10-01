if not Rhylib then
    print("[Rhylib] rhylib_mp needs rhylib_core. Install it and restart the map.")
    return
end

Rhylib.LoadModule("mp", { name = "Military police", version = "0.1.0" })
