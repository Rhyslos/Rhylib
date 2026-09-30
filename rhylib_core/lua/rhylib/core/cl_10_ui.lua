--[[
    Shared UI kit (client only). This is the starting point that the HUD,
    inventory and menus build on.

        draw.SimpleText("Ammo", Rhylib.UI.Font(18), x, y, Rhylib.UI.Colors.text)

    Fonts are created once per size and weight, then reused.
]]

Rhylib.UI = Rhylib.UI or {}
local UI = Rhylib.UI

UI.Colors = {
    bg = Color(30, 32, 29, 235),
    panel = Color(42, 44, 40, 255),
    border = Color(68, 70, 64, 255),
    text = Color(228, 227, 220),
    textDim = Color(169, 168, 160),
    accent = Color(133, 183, 235),
    good = Color(151, 196, 89),
    warn = Color(239, 159, 39),
    bad = Color(226, 75, 74),
}

-- fonts[weight][size] = font name. A lookup costs two table reads, with
-- no string building, so it is safe to call every frame.
UI.fonts = UI.fonts or {}

function UI.Font(size, weight)
    weight = weight or 500
    local byWeight = UI.fonts[weight]
    if not byWeight then
        byWeight = {}
        UI.fonts[weight] = byWeight
    end
    local name = byWeight[size]
    if name then return name end

    name = "Rhylib." .. size .. "." .. weight
    surface.CreateFont(name, {
        font = "Roboto",
        size = math.Round(size * ScrH() / 1080),
        weight = weight,
        extended = true,
    })
    byWeight[size] = name
    return name
end

-- Fonts are sized to the screen, so recreate them if the resolution changes.
Rhylib.Hook.Add("OnScreenSizeChanged", "core.ui.fonts", function()
    UI.fonts = {}
end)
