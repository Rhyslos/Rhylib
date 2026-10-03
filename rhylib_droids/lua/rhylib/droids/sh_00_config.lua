--[[
    Droids: lightweight NextBot enemies that fire real bolts (rhylib_weapons),
    so hits, hit markers and kill markers work like against players.

      B1 battle droid (rhylib_b1): 200 health, E-5 blaster with red bolts.
      Spots players in sight within range (checked a few times a second,
      not every tick), turns, fires short inaccurate bursts, advances when
      far away, chases to where it last saw you, wanders near where it was
      spawned when idle. Walking needs a navmesh (nav_generate); without
      one droids stand and shoot.

    Spawn menu: NPCs tab, "Rhylib Droids" (admins). Droids don't hurt each
    other. At most maxActive droids exist at once.
]]

Rhylib.Droids = Rhylib.Droids or {}
local D = Rhylib.Droids
local Config = Rhylib.Config

Config.Register("droids", "maxActive", 40, "Most droids alive at once (more are removed when spawned)")
Config.Register("droids", "b1Health", 200, "B1 battle droid health")
Config.Register("droids", "b1Speed", 170, "B1 run speed")
Config.Register("droids", "b1Range", 3000, "How far a B1 sees and shoots")
Config.Register("droids", "b1Reaction", 0.6, "Seconds before a B1 starts firing at a new target")
Config.Register("droids", "e5Damage", 12, "E-5 damage per bolt")
Config.Register("droids", "e5RPM", 300, "E-5 shots per minute within a burst")
Config.Register("droids", "e5Spread", 2.5, "E-5 inaccuracy cone (degrees), more against moving targets")

Config.Register("droids", "flashSuppress", 3, "Flash charge: droid aim cone multiplier while dazzled")
Config.Register("droids", "flashTime", 5, "Flash charge: seconds droids stay dazzled")

function D.Cfg(k) return Config.Get("droids", k) end

D.B1_MODEL = "models/npc_b1/npc_droid_cis_b1_h.mdl"
D.E5_MODEL = "models/jajoff/sps/cgiweapons/tc13j/e5.mdl"
D.E5_SOUND = "weapons/airboat/airboat_gun_energy2.wav"

-- The E-5 as rhylib_weapons sees it (BoltColor 2 = red).
function D.E5()
    return { BoltSpeed = 6500, Damage = D.Cfg("e5Damage"), BoltColor = 2 }
end

list.Set("NPC", "rhylib_b1", {
    Name = "B1 battle droid",
    Class = "rhylib_b1",
    Category = "Rhylib Droids",
    AdminOnly = true,
})

if CLIENT then
    language.Add("rhylib_b1", "B1 battle droid")
end
