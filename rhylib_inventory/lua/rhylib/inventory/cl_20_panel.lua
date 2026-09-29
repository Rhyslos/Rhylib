--[[
    Inventory window (client only).

    Press I (rhylib_inventory_key) or run rhylib_inventory to open or close.
    Drag items to move them, press R while dragging to rotate, drop onto a
    matching stack to merge, drag outside the window to drop on the ground.
    Right-click an item for options.

    One panel paints the whole grid; there are no child panels per cell,
    and nothing runs while the window is closed except a key check.
]]

local Inv = Rhylib.Inventory
local Items = Rhylib.Items
local UI = Rhylib.UI

local keyVar = CreateClientConVar("rhylib_inventory_key", "i", true, false, "Key that opens the Rhylib inventory")

local CATEGORY_COLORS = {
    weapon = Color(58, 69, 82),
    ammo = Color(74, 65, 48),
    medical = Color(47, 74, 60),
    gear = Color(69, 64, 58),
    misc = Color(62, 62, 60),
}
local COL_CELL = Color(42, 44, 40)
local COL_CELL_BORDER = Color(68, 70, 64)
local COL_OK = Color(151, 196, 89, 60)
local COL_BAD = Color(226, 75, 74, 60)
local COL_OK_LINE = Color(151, 196, 89)
local COL_BAD_LINE = Color(226, 75, 74)

-- Cut text to fit a width, cached so it's measured once per item size.
local fitCache = {}
local function fitText(text, font, maxW)
    local key = text .. "|" .. font .. "|" .. math.floor(maxW)
    local cached = fitCache[key]
    if cached then return cached end
    surface.SetFont(font)
    local out = text
    if surface.GetTextSize(text) > maxW then
        for i = #text - 1, 1, -1 do
            out = string.sub(text, 1, i) .. "…"
            if surface.GetTextSize(out) <= maxW then break end
        end
    end
    fitCache[key] = out
    return out
end

local PANEL = {}

function PANEL:Init()
    self.s = ScrH() / 1080
    local s = self.s
    self.cell = math.floor(64 * s)
    self.gap = math.floor(4 * s)
    self.pad = math.floor(16 * s)
    self.header = math.floor(40 * s)
    self.footer = math.floor(28 * s)
    self:Relayout()
    self.drag = nil
    self.rDown = false
end

function PANEL:Relayout()
    local step = self.cell + self.gap
    local w = self.pad * 2 + Inv.w * step - self.gap
    local h = self.header + Inv.h * step - self.gap + self.footer + self.pad
    self:SetSize(w, h)
    self.gw, self.gh = Inv.w, Inv.h
end

function PANEL:CellPos(x, y)
    local step = self.cell + self.gap
    return self.pad + x * step, self.header + y * step
end

function PANEL:SpanPx(n)
    return n * self.cell + (n - 1) * self.gap
end

-- Grid cell under panel coordinates (may be outside the grid).
function PANEL:CellAt(px, py)
    local step = self.cell + self.gap
    return math.floor((px - self.pad) / step), math.floor((py - self.header) / step)
end

function PANEL:ItemAtCursor()
    local mx, my = self:CursorPos()
    local cx, cy = self:CellAt(mx, my)
    return Items.At(Inv.items, cx, cy), cx, cy
end

function PANEL:DrawItem(inst, x, y, alpha, s)
    local def = Items.Get(inst.id)
    if not def then return end
    local w, h = Items.Size(inst.id, inst.rot)
    local pw, ph = self:SpanPx(w), self:SpanPx(h)

    local col = CATEGORY_COLORS[def.category] or CATEGORY_COLORS.misc
    surface.SetDrawColor(col.r, col.g, col.b, alpha)
    surface.DrawRect(x, y, pw, ph)

    local active = LocalPlayer():GetActiveWeapon()
    if def.weapon and IsValid(active) and active:GetClass() == def.weapon then
        surface.SetDrawColor(UI.Colors.accent)
        surface.DrawOutlinedRect(x, y, pw, ph, math.max(1, math.floor(2 * s)))
    end

    local font = UI.Font(14)
    local pad = math.floor(5 * s)
    draw.SimpleText(fitText(def.name, font, pw - pad * 2), font, x + pad, y + pad, UI.Colors.text)

    local corner
    if def.fill then
        corner = math.ceil((inst.data.fill or 1) * 100) .. "%"
        if inst.count > 1 then corner = "x" .. inst.count end
    elseif inst.count > 1 then
        corner = "x" .. inst.count
    end
    if corner then
        draw.SimpleText(corner, font, x + pw - pad, y + ph - pad, UI.Colors.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
    end
end

function PANEL:Paint(pw, ph)
    if self.gw ~= Inv.w or self.gh ~= Inv.h then self:Relayout() end
    local s = self.s

    draw.RoundedBox(math.floor(8 * s), 0, 0, pw, ph, UI.Colors.bg)
    draw.SimpleText("Inventory", UI.Font(20), self.pad, self.header * 0.5, UI.Colors.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    draw.SimpleText("Drag to move · R rotates · Right-click for options · Drag out to drop",
        UI.Font(13), self.pad, ph - self.footer * 0.5 - self.pad * 0.25, UI.Colors.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

    -- Empty cells.
    for y = 0, Inv.h - 1 do
        for x = 0, Inv.w - 1 do
            local cx, cy = self:CellPos(x, y)
            surface.SetDrawColor(COL_CELL)
            surface.DrawRect(cx, cy, self.cell, self.cell)
            surface.SetDrawColor(COL_CELL_BORDER)
            surface.DrawOutlinedRect(cx, cy, self.cell, self.cell)
        end
    end

    local dragUid = self.drag and self.drag.inst.uid
    for uid, inst in pairs(Inv.items) do
        local x, y = self:CellPos(inst.x, inst.y)
        self:DrawItem(inst, x, y, uid == dragUid and 70 or 255, s)
    end

    if self.drag then
        self:PaintDrag(s)
    else
        self:PaintTooltip(s)
    end
end

function PANEL:DragTarget(d)
    local mx, my = self:CursorPos()
    local cx, cy = self:CellAt(mx, my)
    return cx - d.offX, cy - d.offY
end

function PANEL:PaintDrag(s)
    local d = self.drag
    local tx, ty = self:DragTarget(d)
    local w, h = Items.Size(d.inst.id, d.rot)
    local inside = tx >= 0 and ty >= 0 and tx + w <= Inv.w and ty + h <= Inv.h

    if inside then
        local merge = Items.MergeTarget(Inv.items, d.inst, tx, ty)
        local ok = merge or Items.Fits(Inv.w, Inv.h, Inv.items, d.inst.id, tx, ty, d.rot, d.inst.uid)
        local x, y = self:CellPos(tx, ty)
        local pw, ph = self:SpanPx(w), self:SpanPx(h)
        surface.SetDrawColor(ok and COL_OK or COL_BAD)
        surface.DrawRect(x, y, pw, ph)
        surface.SetDrawColor(ok and COL_OK_LINE or COL_BAD_LINE)
        surface.DrawOutlinedRect(x, y, pw, ph, math.max(1, math.floor(2 * s)))
    end

    -- The item follows the cursor.
    local mx, my = self:CursorPos()
    local step = self.cell + self.gap
    local ghost = { id = d.inst.id, rot = d.rot, count = d.inst.count, data = d.inst.data }
    self:DrawItem(ghost, mx - d.offX * step - self.cell * 0.5, my - d.offY * step - self.cell * 0.5, 200, s)
end

function PANEL:PaintTooltip(s)
    if not self:IsHovered() then return end
    local inst = self:ItemAtCursor()
    if not inst then return end
    local def = Items.Get(inst.id)
    if not def then return end

    local lines = { def.name }
    if def.fill then lines[#lines + 1] = "Charge " .. math.ceil((inst.data.fill or 1) * 100) .. "%" end
    if def.stack > 1 then lines[#lines + 1] = inst.count .. " / " .. def.stack end
    if def.weapon then lines[#lines + 1] = "Right-click to equip" end

    local font = UI.Font(14)
    surface.SetFont(font)
    local tw, lh = 0, math.floor(18 * s)
    for _, l in ipairs(lines) do tw = math.max(tw, (surface.GetTextSize(l))) end
    local pad = math.floor(8 * s)
    local mx, my = self:CursorPos()
    local bx, by = mx + 16 * s, my + 16 * s
    local bw, bh = tw + pad * 2, #lines * lh + pad * 2

    DisableClipping(true)
    draw.RoundedBox(math.floor(4 * s), bx, by, bw, bh, Color(20, 21, 19, 245))
    for i, l in ipairs(lines) do
        draw.SimpleText(l, font, bx + pad, by + pad + (i - 1) * lh, i == 1 and UI.Colors.text or UI.Colors.textDim)
    end
    DisableClipping(false)
end

function PANEL:OnMousePressed(code)
    local inst, cx, cy = self:ItemAtCursor()
    if not inst then return end

    if code == MOUSE_LEFT then
        self.drag = { inst = inst, rot = inst.rot, offX = cx - inst.x, offY = cy - inst.y }
        self:MouseCapture(true)
    elseif code == MOUSE_RIGHT then
        local def = Items.Get(inst.id)
        local menu = DermaMenu()
        if def and def.weapon then
            menu:AddOption("Equip", function() Inv.RequestUse(inst) end)
        end
        menu:AddOption("Drop", function() Inv.RequestDrop(inst) end)
        menu:Open()
    end
end

function PANEL:OnMouseReleased(code)
    if code ~= MOUSE_LEFT or not self.drag then return end
    self:MouseCapture(false)
    local d = self.drag
    self.drag = nil
    if not Inv.items[d.inst.uid] then return end

    local mx, my = self:CursorPos()
    local pw, ph = self:GetSize()
    if mx < 0 or my < 0 or mx > pw or my > ph then
        Inv.RequestDrop(d.inst)
        return
    end

    local tx, ty = self:DragTarget(d)
    if tx ~= d.inst.x or ty ~= d.inst.y or d.rot ~= d.inst.rot then
        Inv.RequestMove(d.inst, tx, ty, d.rot)
    end
end

function PANEL:Think()
    -- R rotates the item being dragged.
    local r = input.IsKeyDown(KEY_R)
    if r and not self.rDown and self.drag then
        local d = self.drag
        local w, h = Items.Size(d.inst.id, d.rot)
        if w ~= h then
            d.rot = not d.rot
            d.offX, d.offY = math.min(d.offY, h - 1), math.min(d.offX, w - 1)
        end
    end
    self.rDown = r

    if not LocalPlayer():Alive() then self:Remove() end
end

vgui.Register("RhylibInventory", PANEL, "EditablePanel")

--------------------------------------------------------------------------
-- Opening and closing
--------------------------------------------------------------------------

function Inv.Toggle()
    if IsValid(Inv.panel) then
        Inv.panel:Remove()
        return
    end
    if not LocalPlayer():Alive() then return end
    local p = vgui.Create("RhylibInventory")
    p:Center()
    p:MakePopup()
    p:SetKeyboardInputEnabled(false)  -- you can keep walking with it open
    Inv.panel = p
end

concommand.Add("rhylib_inventory", Inv.Toggle)

local keyWasDown = false
Rhylib.Hook.Add("Think", "inventory.key", function()
    local code = input.GetKeyCode(keyVar:GetString())
    local down = code and code > 0 and input.IsKeyDown(code)
    if down and not keyWasDown then
        local blocked = gui.IsGameUIVisible() or gui.IsConsoleVisible() or LocalPlayer():IsTyping() or IsValid(vgui.GetKeyboardFocus())
        if not blocked then Inv.Toggle() end
    end
    keyWasDown = down
end)
