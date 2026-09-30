--[[
    Inventory window (client only).

    Press I (rhylib_inventory_key) or run rhylib_inventory to open or close.
    Left to right: your player model (drag to turn it), the Back slot,
    then the main grid with the backpack grid under it while one is worn.

    Drag items to move them, press R while dragging to rotate, drop onto a
    matching stack to merge, drag outside the window to drop on the ground.
    Right-click an item for options.

    One panel paints all grids; the only child panel is the model preview.
    Nothing runs while the window is closed except a key check.
]]

local Inv = Rhylib.Inventory
local Items = Rhylib.Items
local UI = Rhylib.UI

local MAIN, BACK, SLOT_BACK = Items.MAIN, Items.BACK, Items.SLOT_BACK

local keyVar = CreateClientConVar("rhylib_inventory_key", "i", true, false, "Key that opens the Rhylib inventory")
local sizeVar = CreateClientConVar("rhylib_inventory_cellsize", "100", true, false, "Inventory cell size in pixels at 1080p (48-128); everything else scales with it. Reopen the inventory to apply.")

local CATEGORY_COLORS = {
    weapon = Color(58, 69, 82),
    ammo = Color(74, 65, 48),
    medical = Color(47, 74, 60),
    gear = Color(69, 64, 58),
    misc = Color(62, 62, 60),
}
local COL_CELL = Color(42, 44, 40)
local COL_BORDER = Color(68, 70, 64)
local COL_BACK_CELL = Color(46, 42, 34)
local COL_BACK_BORDER = Color(154, 122, 60)
local COL_SLOT = Color(36, 38, 35)
local COL_OK = Color(151, 196, 89, 60)
local COL_BAD = Color(226, 75, 74, 60)
local COL_OK_LINE = Color(151, 196, 89)
local COL_BAD_LINE = Color(226, 75, 74)
local COL_TIP = Color(20, 21, 19, 245)

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

--------------------------------------------------------------------------
-- Model preview
--------------------------------------------------------------------------

local function setupModel(mdl)
    local ply = LocalPlayer()
    mdl:SetModel(ply:GetModel())
    local ent = mdl.Entity
    if not IsValid(ent) then return end

    ent:SetSkin(ply:GetSkin())
    ent.GetPlayerColor = function() return ply:GetPlayerColor() end
    local seq = ent:LookupSequence("idle_all_01")
    if seq and seq > 0 then ent:SetSequence(seq) end

    local mn, mx = ent:GetRenderBounds()
    local centre = (mn + mx) * 0.5
    local height = mx.z - mn.z
    local dist = height * 0.5 / math.tan(math.rad(20)) * 1.1
    mdl:SetFOV(40)
    mdl:SetLookAt(centre)
    mdl:SetCamPos(centre + Vector(dist, 0, 0))
end

local function createModelPanel(parent)
    local mdl = vgui.Create("DModelPanel", parent)
    mdl.yaw = 20
    setupModel(mdl)

    function mdl:LayoutEntity(ent)
        if self.dragging then
            local x = gui.MouseX()
            self.yaw = self.yaw + (x - self.lastX) * 0.6
            self.lastX = x
        end
        ent:SetAngles(Angle(0, self.yaw, 0))
        self:RunAnimation()
    end

    function mdl:OnMousePressed(code)
        if code ~= MOUSE_LEFT then return end
        self.dragging = true
        self.lastX = gui.MouseX()
        self:MouseCapture(true)
    end

    function mdl:OnMouseReleased()
        self.dragging = false
        self:MouseCapture(false)
    end

    function mdl:Think()
        if self:GetModel() ~= LocalPlayer():GetModel() then setupModel(self) end
    end

    return mdl
end

--------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------

local PANEL = {}

function PANEL:Init()
    -- Everything is sized from the cell size (64 was the original design size).
    self.k = math.Clamp(sizeVar:GetFloat(), 48, 128) / 64  -- 128 still fits a 16:9 screen
    local s = ScrH() / 1080 * self.k
    self.s = s
    self.cell = math.floor(64 * s)
    self.gap = math.floor(4 * s)
    self.step = self.cell + self.gap
    self.pad = math.floor(16 * s)
    self.header = math.floor(40 * s)
    self.label = math.floor(24 * s)
    self.footer = math.floor(28 * s)
    self.drag = nil
    self.rDown = false
    self.model = createModelPanel(self)
    self:Relayout()
end

function PANEL:Font(size)
    return UI.Font(math.Round(size * self.k))
end

function PANEL:SpanPx(n)
    return n * self.cell + (n - 1) * self.gap
end

function PANEL:LayoutKey()
    local m, b = Inv.cont[MAIN], Inv.cont[BACK]
    return (m and (m.w .. "x" .. m.h) or "-") .. "|" .. (b and (b.w .. "x" .. b.h) or "-")
end

-- Works out where every region sits and sizes the window.
function PANEL:Relayout()
    self.layoutKey = self:LayoutKey()
    local pad, label = self.pad, self.label
    local main = Inv.cont[MAIN] or { w = 5, h = 3 }
    local back = Inv.cont[BACK]
    local top = self.header + label   -- row labels ("Back", "Backpack") sit above this

    -- Columns, left to right: model, Back slot, grids.
    local modelW = self:SpanPx(3)
    local slotSize = self:SpanPx(2)
    local slotX = pad + modelW + pad
    local gridX = slotX + slotSize + pad

    -- Grids: main, then the backpack under it.
    local gridsH = self:SpanPx(main.h) + label
    local gridsW = self:SpanPx(main.w)
    self.backLabelY = top + self:SpanPx(main.h) + label * 0.5 + self.gap
    self.regions = {
        { cid = SLOT_BACK, slot = true, x = slotX, y = top, pw = slotSize, ph = slotSize, title = "Back" },
        { cid = MAIN, x = gridX, y = top, gw = main.w, gh = main.h },
    }
    if back then
        self.regions[#self.regions + 1] = { cid = BACK, x = gridX, y = top + gridsH, gw = back.w, gh = back.h }
        gridsH = gridsH + self:SpanPx(back.h)
        gridsW = math.max(gridsW, self:SpanPx(back.w))
    end
    self.rightX = gridX

    -- The model fills the full height of the content.
    local contentH = math.max(gridsH, self:SpanPx(3))
    self.model:SetPos(pad, top)
    self.model:SetSize(modelW, contentH)

    self:SetSize(gridX + gridsW + pad, top + contentH + self.footer + pad * 0.5)
    self:Center()  -- stays centred when a backpack grid appears or disappears
end

-- Region and cell under panel coordinates. Grids allow a small margin so
-- items can be dragged against the edge.
function PANEL:HitTest(mx, my, margin)
    margin = margin or 0
    for _, r in ipairs(self.regions) do
        if r.slot then
            if mx >= r.x and mx <= r.x + r.pw and my >= r.y and my <= r.y + r.ph then
                return r, 0, 0
            end
        else
            local pw, ph = self:SpanPx(r.gw), self:SpanPx(r.gh)
            if mx >= r.x - margin and mx <= r.x + pw + margin and my >= r.y - margin and my <= r.y + ph + margin then
                return r, math.floor((mx - r.x) / self.step), math.floor((my - r.y) / self.step)
            end
        end
    end
end

function PANEL:ItemAtCursor()
    local mx, my = self:CursorPos()
    local r, cx, cy = self:HitTest(mx, my)
    if not r then return nil end
    local c = Inv.cont[r.cid]
    if not c then return nil end
    if r.slot then
        local _, inst = next(c.items)
        return inst, r, 0, 0
    end
    return Items.At(c.items, cx, cy), r, cx, cy
end

function PANEL:DrawItemBox(inst, x, y, pw, ph, alpha)
    local def = Items.Get(inst.id)
    if not def then return end
    local s = self.s

    local col = CATEGORY_COLORS[def.category] or CATEGORY_COLORS.misc
    surface.SetDrawColor(col.r, col.g, col.b, alpha)
    surface.DrawRect(x, y, pw, ph)

    local active = LocalPlayer():GetActiveWeapon()
    if def.weapon and IsValid(active) and active:GetClass() == def.weapon then
        surface.SetDrawColor(UI.Colors.accent)
        surface.DrawOutlinedRect(x, y, pw, ph, math.max(1, math.floor(2 * s)))
    end

    local font = self:Font(14)
    local pad = math.floor(5 * s)
    draw.SimpleText(fitText(def.name, font, pw - pad * 2), font, x + pad, y + pad, UI.Colors.text)

    local corner
    if inst.count > 1 then
        corner = "x" .. inst.count
    elseif def.fill then
        corner = math.ceil((inst.data.fill or 1) * 100) .. "%"
    end
    if corner then
        draw.SimpleText(corner, font, x + pw - pad, y + ph - pad, UI.Colors.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
    end
end

function PANEL:ItemRect(r, inst)
    if r.slot then return r.x, r.y, r.pw, r.ph end
    local w, h = Items.Size(inst.id, inst.rot)
    return r.x + inst.x * self.step, r.y + inst.y * self.step, self:SpanPx(w), self:SpanPx(h)
end

function PANEL:PaintRegion(r, dragUid)
    local c = Inv.cont[r.cid]
    if not c then return end

    if r.slot then
        surface.SetDrawColor(COL_SLOT)
        surface.DrawRect(r.x, r.y, r.pw, r.ph)
        surface.SetDrawColor(COL_BORDER)
        surface.DrawOutlinedRect(r.x, r.y, r.pw, r.ph)
        draw.SimpleText(r.title, self:Font(15), r.x + r.pw * 0.5, r.y - self.label * 0.5, UI.Colors.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        if next(c.items) == nil then
            draw.SimpleText("Empty", self:Font(14), r.x + r.pw * 0.5, r.y + r.ph * 0.5, UI.Colors.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    else
        local isBack = r.cid == BACK
        for y = 0, r.gh - 1 do
            for x = 0, r.gw - 1 do
                local cx, cy = r.x + x * self.step, r.y + y * self.step
                surface.SetDrawColor(isBack and COL_BACK_CELL or COL_CELL)
                surface.DrawRect(cx, cy, self.cell, self.cell)
                surface.SetDrawColor(isBack and COL_BACK_BORDER or COL_BORDER)
                surface.DrawOutlinedRect(cx, cy, self.cell, self.cell)
            end
        end
    end

    for uid, inst in pairs(c.items) do
        local x, y, pw, ph = self:ItemRect(r, inst)
        self:DrawItemBox(inst, x, y, pw, ph, uid == dragUid and 70 or 255)
    end
end

function PANEL:Paint(pw, ph)
    if self:LayoutKey() ~= self.layoutKey then self:Relayout() end
    local s = self.s

    draw.RoundedBox(math.floor(8 * s), 0, 0, pw, ph, UI.Colors.bg)
    draw.SimpleText("Inventory", self:Font(20), self.pad, self.header * 0.5, UI.Colors.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    draw.SimpleText("Drag to move · R rotates · Right-click for options · Drag out to drop",
        self:Font(13), self.pad, ph - self.footer * 0.5 - self.pad * 0.25, UI.Colors.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

    draw.SimpleText(Inv.cont[BACK] and "Backpack" or "No backpack worn", self:Font(15), self.rightX, self.backLabelY,
        UI.Colors.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

    local dragUid = self.drag and self.drag.inst.uid
    for _, r in ipairs(self.regions) do self:PaintRegion(r, dragUid) end

    if self.drag then
        self:PaintDrag()
    else
        self:PaintTooltip()
    end
end

-- Where the dragged item would land: region, x, y (or nil).
function PANEL:DragTarget(d)
    local mx, my = self:CursorPos()
    local r, cx, cy = self:HitTest(mx, my, self.step * 0.5)
    if not r then return nil end
    if r.slot then return r, 0, 0 end
    return r, cx - d.offX, cy - d.offY
end

function PANEL:PaintDrag()
    local d = self.drag
    local s = self.s
    local r, tx, ty = self:DragTarget(d)

    if r and Inv.cont[r.cid] then
        local c = Inv.cont[r.cid]
        local ok = Items.CanLeave(Inv, d.inst) or r.cid == d.inst.c
        ok = ok and ((not r.slot and Items.MergeTarget(c.items, d.inst, tx, ty))
            or Items.CanPlace(Inv, d.inst.id, r.cid, tx, ty, d.rot, d.inst.uid))

        local x, y, pw, ph
        if r.slot then
            x, y, pw, ph = r.x, r.y, r.pw, r.ph
        else
            local w, h = Items.Size(d.inst.id, d.rot)
            x, y, pw, ph = r.x + tx * self.step, r.y + ty * self.step, self:SpanPx(w), self:SpanPx(h)
        end
        surface.SetDrawColor(ok and COL_OK or COL_BAD)
        surface.DrawRect(x, y, pw, ph)
        surface.SetDrawColor(ok and COL_OK_LINE or COL_BAD_LINE)
        surface.DrawOutlinedRect(x, y, pw, ph, math.max(1, math.floor(2 * s)))
    end

    -- The item follows the cursor.
    local mx, my = self:CursorPos()
    local w, h = Items.Size(d.inst.id, d.rot)
    local ghost = { id = d.inst.id, rot = d.rot, count = d.inst.count, data = d.inst.data }
    self:DrawItemBox(ghost, mx - d.offX * self.step - self.cell * 0.5, my - d.offY * self.step - self.cell * 0.5,
        self:SpanPx(w), self:SpanPx(h), 200)
end

function PANEL:PaintTooltip()
    if not self:IsHovered() then return end
    local inst = self:ItemAtCursor()
    if not inst then return end
    local def = Items.Get(inst.id)
    if not def then return end
    local s = self.s

    local lines = { def.name }
    if def.fill then lines[#lines + 1] = "Charge " .. math.ceil((inst.data.fill or 1) * 100) .. "%" end
    if def.stack > 1 then lines[#lines + 1] = inst.count .. " / " .. def.stack end
    if def.grid then lines[#lines + 1] = "Adds " .. def.grid[1] .. " x " .. def.grid[2] .. " cells when worn" end
    if def.large then lines[#lines + 1] = "Too large for a backpack" end
    if def.weapon then lines[#lines + 1] = "Right-click to equip" end

    local font = self:Font(14)
    surface.SetFont(font)
    local tw, lh = 0, math.floor(18 * s)
    for _, l in ipairs(lines) do tw = math.max(tw, (surface.GetTextSize(l))) end
    local pad = math.floor(8 * s)
    local mx, my = self:CursorPos()
    local bx, by = mx + 16 * s, my + 16 * s

    DisableClipping(true)
    draw.RoundedBox(math.floor(4 * s), bx, by, tw + pad * 2, #lines * lh + pad * 2, COL_TIP)
    for i, l in ipairs(lines) do
        draw.SimpleText(l, font, bx + pad, by + pad + (i - 1) * lh, i == 1 and UI.Colors.text or UI.Colors.textDim)
    end
    DisableClipping(false)
end

function PANEL:OnMousePressed(code)
    local inst, r, cx, cy = self:ItemAtCursor()
    if not inst then return end

    if code == MOUSE_LEFT then
        local offX, offY = 0, 0
        if not r.slot then offX, offY = cx - inst.x, cy - inst.y end
        self.drag = { inst = inst, rot = inst.rot, offX = offX, offY = offY }
        self:MouseCapture(true)
    elseif code == MOUSE_RIGHT then
        local def = Items.Get(inst.id)
        local menu = DermaMenu()
        if def and def.weapon then
            menu:AddOption("Equip", function() Inv.RequestUse(inst) end)
        end
        if def and def.slot == "back" and inst.c ~= SLOT_BACK then
            menu:AddOption("Wear", function() Inv.RequestMove(inst, SLOT_BACK, 0, 0, false) end)
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
    if not Inv.byUid[d.inst.uid] then return end

    local mx, my = self:CursorPos()
    local pw, ph = self:GetSize()
    if mx < 0 or my < 0 or mx > pw or my > ph then
        Inv.RequestDrop(d.inst)
        return
    end

    local r, tx, ty = self:DragTarget(d)
    if not r then return end
    if r.cid ~= d.inst.c or tx ~= d.inst.x or ty ~= d.inst.y or d.rot ~= d.inst.rot then
        Inv.RequestMove(d.inst, r.cid, tx, ty, d.rot)
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
