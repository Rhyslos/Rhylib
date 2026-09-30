--[[
    Armoury: where troopers get their gear.

      Weapons armoury   endless: one of each gun. Drag one out to take it,
                        drag it back to hand it in. (rhylib_armoury)
      Ammo cabinet      endless: magazines, power cells, rockets and
                        grapple hooks. (rhylib_ammo_cabinet)
      Supply crates     one per magazine size, about 20 slots of it. Run
                        out, and stay empty until an admin refills them.
                        (rhylib_crate_small / _medium / _large)
      Personal locker   36 slots (6 x 6). Press E on a free one to claim it
                        (one per player); the owner can lock it. Contents
                        belong to the owner's SteamID and are saved.
                        (rhylib_locker)

    Gear from the armoury and ammo cabinet is "issued": dropping it hands
    it back instead of leaving it on the ground.

    Admins place them from the spawn menu (Rhylib tab), then run
    rhylib_armoury_save to keep them on this map. They come back at every
    map start, frozen in place.
]]

Rhylib.Armoury = Rhylib.Armoury or {}
local A = Rhylib.Armoury

A.MODELS = {
    armoury = "models/reizer_props/srsp/sci_fi/armory_01/armory_01.mdl",
    ammo = "models/reizer_props/srsp/sci_fi/armory_02_3/armory_02_3.mdl",
    locker = "models/reizer_props/srsp/sci_fi/console_02_1/console_02_1.mdl",
    crate = "models/reizer_props/srsp/sci_fi/crate_01/crate_01.mdl",
}

-- Every armoury entity class, for saving and loading placements.
A.CLASSES = {
    rhylib_armoury = true,
    rhylib_ammo_cabinet = true,
    rhylib_locker = true,
    rhylib_crate_small = true,
    rhylib_crate_medium = true,
    rhylib_crate_large = true,
}

A.AMMO_STOCK = { "mag_small", "mag_medium", "mag_large", "cell", "rocket", "grapple" }

local Config = Rhylib.Config
Config.Register("armoury", "weapons", {}, "Weapon classes in the armoury, in order. Empty = every Rhylib weapon")
Config.Register("armoury", "lockerW", 6, "Personal locker width in cells")
Config.Register("armoury", "lockerH", 6, "Personal locker height in cells")
Config.Register("armoury", "crateW", 5, "Supply crate width in cells")
Config.Register("armoury", "crateH", 4, "Supply crate height in cells")
