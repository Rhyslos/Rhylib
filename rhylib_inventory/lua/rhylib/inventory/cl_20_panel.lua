--[[
    Inventory window (client only).

    Press I (rhylib_inventory_key) or run rhylib_inventory to open or close.
    Left to right: your player model (drag to turn it), the Back slot,
    then the main grid with the backpack grid under it while one is worn.

    Drag items to move them, press R while dragging to rotate, drop onto a
    matching stack to merge, drag outside the window to drop on the ground.
    Hold Ctrl while starting a drag to take just one off a stack.
    Right-click an item for options (split a stack, equip, wear, drop).

    With a locker, crate or armoury open, it shows on the right. Drag items
    between the two. Under the Back slot: Combine munitions.

    Along the bottom: the hotbar (4 slots, 6 with a backpack). Drag an item
    onto a slot to put it there (keys 1-4 / 1-6 then pick it), drag it off
    or right-click the slot to empty it.

    One panel paints all grids; the only child panel is the model preview.
    Nothing runs while the window is closed except a key check.
]]

local Inv = Rhylib.Inventory
local Items = Rhylib.Items
local UI = Rhylib.UI

local MAIN, BACK, SLOT_BACK, EXT = Items.MAIN, Items.BACK, Items.SLOT_BACK, Items.EXT

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
local COL_EXT_CELL = Color(36, 42, 48)
local COL_EXT_BORDER = Color(70, 96, 122)
local COL_BUTTON = Color(52, 56, 52)
local COL_BUTTON_HOVER = Color(66, 72, 66)

local function ctrlDown()
    return input.IsKeyDown(KEY_LCONTROL) or input.IsKeyDown(KEY_RCONTROL)
end

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
    local m, b, e = Inv.cont[MAIN], Inv.cont[BACK], Inv.cont[EXT]
    return (m and (m.w .. "x" .. m.h) or "-") .. "|" .. (b and (b.w .. "x" .. b.h) or "-")
        .. "|" .. (e and (e.w .. "x" .. e.h) or "-")
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

    -- Combine munitions button, under the Back slot.
    self.combineRect = { x = slotX, y = top + slotSize + self.gap * 3, w = slotSize, h = math.floor(label * 1.4) }

    -- An open locker, crate or armoury: to the right of your grids.
    local width = gridX + gridsW + pad
    local ext = Inv.cont[EXT]
    local contentH = math.max(gridsH, self:SpanPx(3))
    if ext then
        local extX = gridX + gridsW + pad * 2
        self.regions[#self.regions + 1] = { cid = EXT, x = extX, y = top, gw = ext.w, gh = ext.h, title = Inv.ext and Inv.ext.title }
        width = extX + self:SpanPx(ext.w) + pad
        contentH = math.max(contentH, self:SpanPx(ext.h))
    end

    -- The model fills the full height of the content.
    self.model:SetPos(pad, top)
    self.model:SetSize(modelW, contentH)

    -- Hotbar row along the bottom, starting under the Back slot.
    self.hotbarN = Items.HotbarSize(Inv)
    self.hotbarX = slotX
    self.hotbarY = top + contentH + label + self.gap * 2
    width = math.max(width, slotX + self:SpanPx(self.hotbarN) + pad)

    self:SetSize(width, self.hotbarY + self.cell + self.footer + pad * 0.5)
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

-- Hotbar slot number under panel coordinates, or nil.
function PANEL:HotbarAt(mx, my)
    if not self.hotbarY or my < self.hotbarY or my > self.hotbarY + self.cell then return nil end
    local n = math.floor((mx - self.hotbarX) / self.step) + 1
    if n < 1 or n > self.hotbarN then return nil end
    if mx - self.hotbarX - (n - 1) * self.step > self.cell then return nil end  -- in the gap
    return n
end

function PANEL:PaintHotbar()
    local s = self.s
    local active = LocalPlayer():GetActiveWeapon()
    local mx, my = self:CursorPos()
    local hover = self.drag and not self.drag.fromExt and self:HotbarAt(mx, my)
    draw.SimpleText("Hotbar", self:Font(15), self.hotbarX, self.hotbarY - self.label * 0.5, UI.Colors.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    draw.SimpleText("drag items here · right-click to empty", self:Font(12), self.hotbarX + math.floor(60 * s), self.hotbarY - self.label * 0.5,
        UI.Colors.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    for n = 1, self.hotbarN do
        local x, y = self.hotbarX + (n - 1) * self.step, self.hotbarY
        local inst = Inv.HotbarItem(n)
        if inst then
            self:DrawItemBox(inst, x, y, self.cell, self.cell, self.drag and self.drag.inst == inst and 70 or 255)
        else
            surface.SetDrawColor(COL_SLOT)
            surface.DrawRect(x, y, self.cell, self.cell)
        end
        surface.SetDrawColor(hover == n and COL_OK_LINE or COL_BORDER)
        surface.DrawOutlinedRect(x, y, self.cell, self.cell, hover == n and math.max(1, math.floor(2 * s)) or 1)
        draw.SimpleText(tostring(n), self:Font(13), x + self.cell - math.floor(5 * s), y + math.floor(3 * s), UI.Colors.textDim, TEXT_ALIGN_RIGHT)
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

function PANEL:DrawItemBox(inst, x, y, pw, ph, alpha, endless)
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
    if inst.hb and inst.c ~= EXT and inst.c then
        -- Hotbar slot badge, bottom-left.
        draw.SimpleText("[" .. inst.hb .. "]", self:Font(12), x + pad, y + ph - pad, UI.Colors.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
    end

    local corner
    if endless then
        corner = "∞"
    elseif inst.count > 1 then
        corner = "x" .. inst.count
    elseif def.rounds and def.rounds > 1 then
        corner = math.floor((inst.data.fill or 1) * def.rounds + 0.5) .. "/" .. def.rounds
    elseif def.fill and def.rounds == nil then
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
        local isBack, isExt = r.cid == BACK, r.cid == EXT
        local cellCol = isExt and COL_EXT_CELL or (isBack and COL_BACK_CELL or COL_CELL)
        local borderCol = isExt and COL_EXT_BORDER or (isBack and COL_BACK_BORDER or COL_BORDER)
        for y = 0, r.gh - 1 do
            for x = 0, r.gw - 1 do
                local cx, cy = r.x + x * self.step, r.y + y * self.step
                surface.SetDrawColor(cellCol)
                surface.DrawRect(cx, cy, self.cell, self.cell)
                surface.SetDrawColor(borderCol)
                surface.DrawOutlinedRect(cx, cy, self.cell, self.cell)
            end
        end
        if isExt and Inv.ext then
            draw.SimpleText(Inv.ext.title, self:Font(15), r.x, r.y - self.label * 0.5, UI.Colors.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end

    local endless = r.cid == EXT and Inv.ext and Inv.ext.depot
    for uid, inst in pairs(c.items) do
        local x, y, pw, ph = self:ItemRect(r, inst)
        local dragged = dragUid == uid and self.drag and (self.drag.fromExt == (r.cid == EXT))
        self:DrawItemBox(inst, x, y, pw, ph, dragged and 70 or 255, endless)
    end
end

function PANEL:Paint(pw, ph)
    if self:LayoutKey() ~= self.layoutKey then self:Relayout() end
    local s = self.s

    draw.RoundedBox(math.floor(8 * s), 0, 0, pw, ph, UI.Colors.bg)
    draw.SimpleText("Inventory", self:Font(20), self.pad, self.header * 0.5, UI.Colors.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    self:PaintWeight(pw)
    draw.SimpleText("Drag to move · Ctrl+drag takes one · R rotates · Right-click for options · Drag out to drop",
        self:Font(13), self.pad, ph - self.footer * 0.5 - self.pad * 0.25, UI.Colors.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

    draw.SimpleText(Inv.cont[BACK] and "Backpack" or "No backpack worn", self:Font(15), self.rightX, self.backLabelY,
        UI.Colors.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

    local dragUid = self.drag and self.drag.inst.uid
    for _, r in ipairs(self.regions) do self:PaintRegion(r, dragUid) end

    self.buttons = {}
    self:PaintHotbar()
    self:PaintCombine()
    self:PaintExtControls()
    self:PaintNote(pw, ph)

    if self.drag then
        self:PaintDrag()
    else
        self:PaintTooltip()
    end
end

-- A clickable text button; remembered for OnMousePressed.
function PANEL:Button(x, y, w, h, text, fn, enabled)
    local mx, my = self:CursorPos()
    local hover = enabled ~= false and mx >= x and mx <= x + w and my >= y and my <= y + h
    draw.RoundedBox(math.floor(4 * self.s), x, y, w, h, hover and COL_BUTTON_HOVER or COL_BUTTON)
    draw.SimpleText(text, self:Font(13), x + w * 0.5, y + h * 0.5, enabled == false and UI.Colors.textDim or UI.Colors.text,
        TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    if enabled ~= false then self.buttons[#self.buttons + 1] = { x = x, y = y, w = w, h = h, fn = fn } end
end

-- Combine munitions: a button, or a progress bar while it runs.
function PANEL:PaintCombine()
    local r = self.combineRect
    if not r then return end
    local now = CurTime()
    if Inv.busyEnd and Inv.busyEnd > now then
        local total = math.max(Inv.busyEnd - (Inv.busyStart or now), 0.01)
        local frac = math.Clamp(1 - (Inv.busyEnd - now) / total, 0, 1)
        draw.RoundedBox(math.floor(4 * self.s), r.x, r.y, r.w, r.h, COL_BUTTON)
        surface.SetDrawColor(UI.Colors.accent.r, UI.Colors.accent.g, UI.Colors.accent.b, 90)
        surface.DrawRect(r.x, r.y, math.floor(r.w * frac), r.h)
        draw.SimpleText("Combining…", self:Font(13), r.x + r.w * 0.5, r.y + r.h * 0.5, UI.Colors.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        return
    end
    self:Button(r.x, r.y, r.w, r.h, "Combine munitions", function() Inv.RequestCombine() end)
end

-- The last message from the server, for a few seconds, above the footer.
function PANEL:PaintNote(pw, ph)
    if not Inv.note or RealTime() - (Inv.noteTime or 0) > 3 then return end
    local a = math.Clamp((3 - (RealTime() - Inv.noteTime)) * 255, 0, 255)
    local col = UI.Colors.warn
    draw.SimpleText(Inv.note, self:Font(14), pw - self.pad, ph - self.footer * 0.5 - self.pad * 0.25,
        Color(col.r, col.g, col.b, a), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
end

-- Lock / unclaim buttons for the owner of an open locker.
function PANEL:PaintExtControls()
    local ext = Inv.ext
    if not ext or not ext.canLock then return end
    local r
    for _, reg in ipairs(self.regions) do
        if reg.cid == EXT then r = reg end
    end
    if not r then return end
    local s = self.s
    local bh = math.floor(self.label * 0.85)
    local bw = math.floor(80 * s)
    local right = r.x + self:SpanPx(r.gw)
    local y = r.y - self.label * 0.5 - bh * 0.5
    self:Button(right - bw, y, bw, bh, ext.locked and "Unlock" or "Lock", function()
        hook.Run("Rhylib.StorageControl", "lock")
    end)
    self:Button(right - bw * 2 - self.gap, y, bw, bh, "Unclaim", function()
        hook.Run("Rhylib.StorageControl", "unclaim")
    end)
end

-- Carried weight in the header: "12.4 / 20 kg" over a thin bar.
-- Worked out from the local copy, so it updates the moment items move.
local COL_TRACK = Color(255, 255, 255, 28)
function PANEL:PaintWeight(pw)
    local s = self.s
    local weight, cap = Items.Weight(Inv)
    local over = weight > cap
    local frac = math.min(weight / cap, 1)
    local col = over and UI.Colors.bad or (frac > 0.8 and UI.Colors.warn or UI.Colors.text)

    local barW = math.floor(160 * s)
    local barH = math.max(2, math.floor(4 * s))
    local right = pw - self.pad
    local x = right - barW
    local midY = self.header * 0.5

    draw.SimpleText(string.format("%.1f / %d kg", weight, cap), self:Font(15), right, midY - barH,
        col, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
    if over then
        draw.SimpleText("Overloaded", self:Font(13), x - math.floor(8 * s), midY - barH, UI.Colors.bad, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
    end
    surface.SetDrawColor(COL_TRACK)
    surface.DrawRect(x, midY + barH, barW, barH)
    surface.SetDrawColor(over and UI.Colors.bad or UI.Colors.accent)
    surface.DrawRect(x, midY + barH, math.floor(barW * frac), barH)
end

-- Where the dragged item would land: region, x, y (or nil).
function PANEL:DragTarget(d)
    local mx, my = self:CursorPos()
    local r, cx, cy = self:HitTest(mx, my, self.step * 0.5)
    if not r then return nil end
    if r.slot then return r, 0, 0 end
    return r, cx - d.offX, cy - d.offY
end

-- Would dropping drag d at region r, x, y do anything?
function PANEL:DropAllowed(d, r, tx, ty)
    local c = Inv.cont[r.cid]
    if not c then return false end
    local toExt, fromExt = r.cid == EXT, d.fromExt
    local probe = { uid = -1, id = d.inst.id, count = d.inst.count, data = d.inst.data }

    if toExt and Inv.ext and Inv.ext.depot then
        if fromExt then return false end
        for _, o in pairs(c.items) do
            if o.id == d.inst.id then return true end  -- handing stocked gear back
        end
        return false
    end
    if toExt and fromExt then
        return Items.MergeTarget(c.items, d.inst, tx, ty) ~= nil
            or Items.Fits(c.w, c.h, c.items, d.inst.id, tx, ty, d.rot, not d.single and d.inst.uid or nil)
    end
    if toExt then
        if not Items.CanLeave(Inv, d.inst) then return false end
        return Items.MergeTarget(c.items, probe, tx, ty) ~= nil or Items.Fits(c.w, c.h, c.items, d.inst.id, tx, ty, d.rot)
    end
    if fromExt then
        return (not r.slot and Items.MergeTarget(c.items, probe, tx, ty) ~= nil)
            or Items.CanPlace(Inv, d.inst.id, r.cid, tx, ty, d.rot)
    end
    if d.fromHotbar then return false end
    local ok = Items.CanLeave(Inv, d.inst) or r.cid == d.inst.c
    return ok and ((not r.slot and Items.MergeTarget(c.items, d.inst, tx, ty) ~= nil)
        or Items.CanPlace(Inv, d.inst.id, r.cid, tx, ty, d.rot, not d.single and d.inst.uid or nil))
end

function PANEL:PaintDrag()
    local d = self.drag
    local s = self.s
    local r, tx, ty = self:DragTarget(d)

    if r and Inv.cont[r.cid] then
        local ok = self:DropAllowed(d, r, tx, ty)

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
    local ghost = { id = d.inst.id, rot = d.rot, count = d.single and 1 or d.inst.count, data = d.inst.data }
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
    if def.rounds then
        if def.rounds > 1 then
            lines[#lines + 1] = math.floor((inst.data.fill or 1) * def.rounds + 0.5) .. " / " .. def.rounds .. " rounds"
        end
    elseif def.fill then
        lines[#lines + 1] = "Charge " .. math.ceil((inst.data.fill or 1) * 100) .. "%"
    end
    if def.stack > 1 then lines[#lines + 1] = inst.count .. " / " .. def.stack end
    if def.weight then
        local w = def.weight * inst.count
        local note = inst.c == BACK and string.format(" (counts as %.2f in the backpack)", w * Rhylib.Config.Get("inventory", "backpackWeightMult")) or ""
        lines[#lines + 1] = string.format("%.2f kg", w) .. note
    end
    if def.carry then lines[#lines + 1] = "+" .. def.carry .. " kg carry cap when worn" end
    if def.grid then lines[#lines + 1] = "Adds " .. def.grid[1] .. " x " .. def.grid[2] .. " cells when worn" end
    if def.large then lines[#lines + 1] = "Too large for a backpack" end
    if inst.data and inst.data.issued then lines[#lines + 1] = "Issued: handed back if dropped" end
    if inst.c == EXT and Inv.ext and Inv.ext.depot then lines[#lines + 1] = "Endless supply, drag to take (Ctrl: just one)" end
    if inst.hb then
        lines[#lines + 1] = "On the hotbar (" .. inst.hb .. ")"
    elseif inst.c ~= EXT then
        lines[#lines + 1] = "Right-click → Equip to put it on the hotbar"
    end

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
    if code == MOUSE_LEFT and self.buttons then
        local mx, my = self:CursorPos()
        for _, b in ipairs(self.buttons) do
            if mx >= b.x and mx <= b.x + b.w and my >= b.y and my <= b.y + b.h then
                b.fn()
                return
            end
        end
    end

    -- Hotbar row: right-click empties a slot, left-drag moves or removes it.
    local mx, my = self:CursorPos()
    local hb = self:HotbarAt(mx, my)
    if hb then
        local inst = Inv.HotbarItem(hb)
        if not inst then return end
        if code == MOUSE_RIGHT then
            Inv.RequestHotbar(nil, hb)
        elseif code == MOUSE_LEFT then
            self.drag = { inst = inst, rot = inst.rot, offX = 0, offY = 0, fromHotbar = hb, single = false }
            self:MouseCapture(true)
        end
        return
    end

    local inst, r, cx, cy = self:ItemAtCursor()
    if not inst then return end
    local fromExt = r.cid == EXT

    if code == MOUSE_LEFT then
        local offX, offY = 0, 0
        if not r.slot then offX, offY = cx - inst.x, cy - inst.y end
        local single = ctrlDown() and (inst.count > 1 or (fromExt and Inv.ext and Inv.ext.depot))
        self.drag = { inst = inst, rot = inst.rot, offX = offX, offY = offY, fromExt = fromExt, single = single or false }
        self:MouseCapture(true)
    elseif code == MOUSE_RIGHT and not fromExt then
        local def = Items.Get(inst.id)
        local menu = DermaMenu()
        if inst.count > 1 then
            menu:AddOption("Split stack", function() Inv.RequestSplit(inst) end)
        end
        -- Equip = put it on the hotbar (first free slot); Unequip = take it off.
        if def and inst.c ~= SLOT_BACK then
            if inst.hb then
                menu:AddOption("Unequip", function() Inv.RequestHotbar(nil, inst.hb) end)
            else
                menu:AddOption("Equip", function()
                    local free
                    for n = 1, Items.HotbarSize(Inv) do
                        if not Inv.HotbarItem(n) then free = n break end
                    end
                    if not free then
                        Inv.note, Inv.noteTime = "Hotbar full: empty a slot first", RealTime()
                        return
                    end
                    Inv.RequestHotbar(inst, free)
                end)
            end
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
    local mx, my = self:CursorPos()
    local pw, ph = self:GetSize()
    local outside = mx < 0 or my < 0 or mx > pw or my > ph

    -- Onto the hotbar: put it in that slot. A slot dragged anywhere else empties.
    local hb = not d.fromExt and self:HotbarAt(mx, my)
    if hb then
        if hb ~= d.fromHotbar then Inv.RequestHotbar(d.inst, hb) end
        return
    end
    if d.fromHotbar then
        Inv.RequestHotbar(nil, d.fromHotbar)
        return
    end

    if d.fromExt then
        local c = Inv.cont[EXT]
        if outside or not c or not c.items[d.inst.uid] then return end
        local r, tx, ty = self:DragTarget(d)
        if not r then return end
        if r.cid ~= EXT then
            Inv.RequestTake(d.inst, r.cid, tx, ty, d.rot, d.single)
        elseif not Inv.ext.depot and (tx ~= d.inst.x or ty ~= d.inst.y or d.rot ~= d.inst.rot) then
            Inv.RequestExtMove(d.inst, tx, ty, d.rot, d.single)
        end
        return
    end

    if not Inv.byUid[d.inst.uid] then return end
    if outside then
        Inv.RequestDrop(d.inst, d.single)
        return
    end

    local r, tx, ty = self:DragTarget(d)
    if not r then return end
    if r.cid ~= d.inst.c or tx ~= d.inst.x or ty ~= d.inst.y or d.rot ~= d.inst.rot then
        Inv.RequestMove(d.inst, r.cid, tx, ty, d.rot, d.single)
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

-- Closing the window closes the locker / armoury too.
function PANEL:OnRemove()
    Inv.CloseExt()
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
