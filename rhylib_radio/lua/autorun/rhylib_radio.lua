if not Rhylib then
    print("[Rhylib] rhylib_radio needs rhylib_core. Install it and restart the map.")
    return
end

Rhylib.LoadModule("radio", { name = "Radio and squads", version = "0.1.0" })
