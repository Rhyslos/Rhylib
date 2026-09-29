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

UI.fonts = UI.fonts or {}

function UI.Font(size, weight)
    weight = weight or 500
    local name = "Rhylib." .. size .. "." .. weight
    if not UI.fonts[name] then
        surface.CreateFont(name, {
            font = "Roboto",
            size = math.Round(size * ScrH() / 1080),
            weight = weight,
            extended = true,
        })
        UI.fonts[name] = true
    end
    return name
end

-- Fonts are sized to the screen, so recreate them if the resolution changes.
Rhylib.Hook.Add("OnScreenSizeChanged", "core.ui.fonts", function()
    UI.fonts = {}
end)
