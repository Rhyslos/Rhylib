AddCSLuaFile()

SWEP.Base = "rhylib_med_base"
SWEP.PrintName = "Medkit"
SWEP.Spawnable = true
SWEP.Category = "Rhylib Medical"  -- the spawn menu reads it from this file, not the base
SWEP.CanSelf = true
SWEP.Hint = "LMB  heal someone   ·   RMB  heal yourself"

SWEP.InvW, SWEP.InvH = 2, 1
SWEP.InvWeight = 0.6
SWEP.InvUses = Rhylib and Rhylib.Config and Rhylib.Config.Get("medical", "medkitUses") or 5

function SWEP:SetupDataTables()
    self:NetworkVar("Int", 0, "Uses")
end

function SWEP:Initialize()
    self:SetHoldType(self.HoldType)
    if SERVER then self:SetUses(self.InvUses) end
end

-- The inventory item keeps the uses (as fill); this only shows them.
function SWEP:SetInventoryData(data)
    local fill = data and data.fill or 1
    self:SetUses(math.floor(fill * self.InvUses + 0.5))
end
