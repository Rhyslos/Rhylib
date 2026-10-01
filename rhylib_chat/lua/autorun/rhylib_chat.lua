if not Rhylib then
    print("[Rhylib] rhylib_chat needs rhylib_core. Install it and restart the map.")
    return
end

Rhylib.LoadModule("chat", { name = "Chat", version = "0.1.0" })
