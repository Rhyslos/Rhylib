if not Rhylib then
    print("[Rhylib] rhylib_armoury needs rhylib_core. Install it and restart the map.")
    return
end

-- Needs rhylib_inventory too. That loads after this file (alphabetical),
-- so the armoury code only looks it up when it's used.
Rhylib.LoadModule("armoury", { name = "Armoury", version = "0.1.0" })
