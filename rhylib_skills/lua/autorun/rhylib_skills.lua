if not Rhylib then
    print("[Rhylib] rhylib_skills needs rhylib_core. Install it and restart the map.")
    return
end

-- Skill trees: categories (Trooper, Support, Officer), specialisations
-- and the skills that change weapons, movement and carrying.
Rhylib.LoadModule("skills", { name = "Skills", version = "0.1.0" })
