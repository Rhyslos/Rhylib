Rhylib.Weapons = Rhylib.Weapons or {}

local Config = Rhylib.Config
Config.Register("weapons", "lagCompMax", 0.2, "Max seconds of ping covered by lag compensation on a bolt's first leg")
Config.Register("weapons", "shotRange", 6000, "Players further than this from a shot don't receive it")
Config.Register("weapons", "boltLife", 1.2, "Seconds before a bolt that hit nothing disappears")
Config.Register("weapons", "headMult", 2, "Damage multiplier for head hits")
Config.Register("weapons", "limbMult", 0.75, "Damage multiplier for arm and leg hits")

-- One ammo type for blaster magazines until the inventory system takes over.
game.AddAmmoType({
    name = "rhylib_blaster",
    dmgtype = DMG_BULLET,
    tracer = TRACER_NONE,
    plydmg = 0,
    npcdmg = 0,
    force = 0,
    maxcarry = 9999,
})

if CLIENT then
    language.Add("rhylib_blaster_ammo", "Blaster ammo")
end
