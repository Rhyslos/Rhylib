--[[
    Ammo store for reloads (server only).

    With rhylib_inventory installed, magazines and power cells are real
    inventory items ("mag", "cell") with a fill level from 0 to 1.
    Without it, a simple per-player pouch is used instead, so the weapons
    addon still works on its own.

    Magazines and cells are universal: a fill level becomes shots when
    loaded (0.46 of a 50-shot DC-15S magazine = 23 shots). Reloading
    always loads the fullest one and puts the old one back if it isn't
    empty, so no shots are lost.

    Counts are mirrored into GMod ammo types so the default HUD shows them.
]]

local W = Rhylib.Weapons
W.Pouch = W.Pouch or {}
local Pouch = W.Pouch
local Config = Rhylib.Config

local ITEM = { mags = "mag", cells = "cell" }
local LIMIT = { mags = "maxMags", cells = "maxCells" }
local AMMO = { mags = "rhylib_blaster", cells = "rhylib_cell" }

local function inventory()
    local Inv = Rhylib.Inventory
    return Inv and Inv.AddItem and Inv or nil
end

-- Fallback pouch -------------------------------------------------------

local function get(ply)
    local p = ply.RhylibPouch
    if not p then
        p = { mags = {}, cells = {} }
        ply.RhylibPouch = p
    end
    return p
end

-- Shared API -----------------------------------------------------------

function Pouch.Count(ply, kind)
    local Inv = inventory()
    if Inv then return Inv.Count(ply, ITEM[kind]) end
    return #get(ply)[kind]
end

function Pouch.Sync(ply)
    ply:SetAmmo(Pouch.Count(ply, "mags"), AMMO.mags)
    ply:SetAmmo(Pouch.Count(ply, "cells"), AMMO.cells)
end

-- Returns false if there's no room. force: never lose it (drops it on
-- the ground with the inventory, ignores the limit without).
function Pouch.Add(ply, kind, fill, force)
    fill = math.Clamp(fill, 0, 1)
    local Inv = inventory()
    if Inv then
        if force then
            Inv.AddOrDrop(ply, ITEM[kind], 1, { fill = fill })
            return true
        end
        return Inv.AddItem(ply, ITEM[kind], 1, { fill = fill }) == 0
    end

    local list = get(ply)[kind]
    if not force and #list >= Config.Get("weapons", LIMIT[kind]) then return false end
    list[#list + 1] = fill
    Pouch.Sync(ply)
    return true
end

-- Removes and returns the fullest one, or nil if there are none.
function Pouch.TakeBest(ply, kind)
    local Inv = inventory()
    if Inv then return Inv.TakeBest(ply, ITEM[kind]) end

    local list = get(ply)[kind]
    local best, bestIndex = -1, nil
    for i, fill in ipairs(list) do
        if fill > best then
            best, bestIndex = fill, i
        end
    end
    if not bestIndex then return nil end
    table.remove(list, bestIndex)
    Pouch.Sync(ply)
    return best
end

function Pouch.Reset(ply)
    ply.RhylibPouch = { mags = {}, cells = {} }
    Pouch.Sync(ply)
end

-- Hooks ----------------------------------------------------------------

-- Without the inventory, players respawn with an empty pouch.
Rhylib.Hook.Add("PlayerSpawn", "weapons.pouch", function(ply)
    if inventory() then
        timer.Simple(0, function() if IsValid(ply) then Pouch.Sync(ply) end end)
        return
    end
    Pouch.Reset(ply)
end)

-- Keep the HUD's spare magazine and cell counts in step with the inventory.
Rhylib.Hook.Add("Rhylib.InventoryChanged", "weapons.pouch", function(ply)
    Pouch.Sync(ply)
end)

-- A newly picked-up weapon comes with its start ammo (testing only).
Rhylib.Hook.Add("Rhylib.InventoryWeaponPickup", "weapons.startammo", function(ply, class)
    local swep = weapons.Get(class)
    if not swep or not swep.IsRhylib then return end
    for _ = 1, swep.StartMags or 0 do Pouch.Add(ply, "mags", 1, true) end
    for _ = 1, swep.StartCells or 0 do Pouch.Add(ply, "cells", 1, true) end
end)

-- E + R (fire mode) and Shift + E + R (safety).
Rhylib.Net.Receive("wep.mode", function(ply)
    local safety = net.ReadBool()
    local wep = ply:GetActiveWeapon()
    if not (IsValid(wep) and wep.IsRhylib) then return end
    if safety then wep:ToggleSafety() else wep:CycleFireMode() end
end, { rate = 4, burst = 3 })

-- Reload requests from the radial menu: 1 = magazine, 2 = power cell.
Rhylib.Net.Receive("wep.reload", function(ply)
    local kind = net.ReadUInt(2)
    local wep = ply:GetActiveWeapon()
    if IsValid(wep) and wep.IsRhylib and wep.StartReload then
        wep:StartReload(kind)
    end
end, { rate = 4, burst = 3 })
