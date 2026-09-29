Rhylib.Weapons = Rhylib.Weapons or {}

local Config = Rhylib.Config
Config.Register("weapons", "lagCompMax", 0.2, "Max seconds of ping covered by lag compensation on a bolt's first leg")
Config.Register("weapons", "shotRange", 6000, "Players further than this from a shot don't receive it")
Config.Register("weapons", "boltLife", 1.2, "Seconds before a bolt that hit nothing disappears")
Config.Register("weapons", "headMult", 2, "Damage multiplier for head hits")
Config.Register("weapons", "limbMult", 0.75, "Damage multiplier for arm and leg hits")

Config.Register("weapons", "lowCellThreshold", 0.1, "Below this power cell charge (0-1), damage starts to drop")
Config.Register("weapons", "lowCellMinDamage", 0.5, "Damage multiplier when the power cell is completely drained")
Config.Register("weapons", "reloadHoldTime", 0.2, "Seconds R must be held to open the reload menu")
Config.Register("weapons", "maxMags", 12, "Spare magazines a player can carry (until the inventory exists)")
Config.Register("weapons", "maxCells", 4, "Spare power cells a player can carry (until the inventory exists)")

-- Ammo types. Their counts mirror the pouch so the default HUD shows
-- spare magazines and cells. The pouch is the real store.
game.AddAmmoType({
    name = "rhylib_blaster",
    dmgtype = DMG_BULLET,
    tracer = TRACER_NONE,
    plydmg = 0,
    npcdmg = 0,
    force = 0,
    maxcarry = 9999,
})

game.AddAmmoType({
    name = "rhylib_cell",
    dmgtype = DMG_BULLET,
    tracer = TRACER_NONE,
    plydmg = 0,
    npcdmg = 0,
    force = 0,
    maxcarry = 9999,
})

-- Inventory items, if rhylib_inventory is installed (it loads before this addon).
if Rhylib.Items then
    Rhylib.Items.Register("mag", {
        name = "Blaster magazine",
        w = 1, h = 1,
        stack = 5,
        fill = true,
        category = "ammo",
        model = "models/items/boxmrounds.mdl",
    })
    Rhylib.Items.Register("cell", {
        name = "Power cell",
        w = 1, h = 2,
        stack = 1,
        fill = true,
        category = "ammo",
        model = "models/items/battery.mdl",
    })
end

if CLIENT then
    language.Add("rhylib_blaster_ammo", "Magazines")
    language.Add("rhylib_cell_ammo", "Power cells")
end
