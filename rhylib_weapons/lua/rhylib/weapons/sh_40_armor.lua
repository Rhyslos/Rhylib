--[[
    Armour: a second bar that soaks damage before health.

    Armour is split into four quarters, the same four bars the HUD draws.
    Each quarter is a tier; the fewer quarters left, the less a hit is
    reduced. At 0 armour you take full damage.
        tier 4  above 75%    mitigation[4]
        tier 3  50-75%       mitigation[3]
        tier 2  25-50%       mitigation[2]
        tier 1  above 0%     mitigation[1]
        tier 0  empty        nothing
    The tier is read when the hit lands. Every hit also costs armour:
    incoming damage (before mitigation) x drain, rounded up.

    Uses the engine's own armour value (Armor / SetArmor / GetMaxArmor),
    so DarkRP jobs, chargers and admin tools keep working. The server
    takes over the damage maths; see sv_40_armor.lua.
]]

Rhylib.Armor = Rhylib.Armor or {}
local A = Rhylib.Armor

local Config = Rhylib.Config
Config.Register("armor", "mitigation", { 0.15, 0.30, 0.45, 0.60 }, "Share of damage blocked per tier, last quarter first (placeholders)")
Config.Register("armor", "drain", 1, "Armour lost per point of incoming damage, before mitigation")
Config.Register("armor", "spawnArmor", 100, "Armour players spawn with (a DarkRP job's armor = N overrides it)")
Config.Register("armor", "bypass", bit.bor(DMG_FALL, DMG_DROWN, DMG_POISON, DMG_RADIATION), "Damage types armour ignores (same as the engine's list)")

-- Tier 0-4 for an armour value.
function A.Tier(armor, maxArmor)
    if armor <= 0 then return 0 end
    if not maxArmor or maxArmor <= 0 then maxArmor = 100 end
    return math.Clamp(math.ceil(armor / maxArmor * 4), 1, 4)
end

-- Share of damage blocked (0-1) for an armour value.
function A.Mitigation(armor, maxArmor)
    local tier = A.Tier(armor, maxArmor)
    if tier == 0 then return 0 end
    local list = Config.Get("armor", "mitigation")
    local m = type(list) == "table" and tonumber(list[tier]) or 0
    return math.Clamp(m, 0, 1)
end
