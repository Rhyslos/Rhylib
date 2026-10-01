--[[
    Rhylib menus: the pause menu (Esc; Shift + Esc opens Garry's Mod's own
    menu), with settings and an admin command page, the scoreboard, the
    killfeed, and a DarkRP F4 menu. Everything is client side; the admin
    commands are the admin mod's own (ULX or SAM) and Rhylib's console
    commands, which check permissions on the server themselves.

    Other addons can add to the menus:
        Rhylib.Menus.AddSetting(section, setting)      (cl_20_settings.lua)
        Rhylib.Menus.AddCommand(group, command)        (cl_30_commands.lua)
]]

Rhylib.Menus = Rhylib.Menus or {}

local Config = Rhylib.Config
Config.Register("menus", "title", "", "Title on the pause menu and scoreboard (empty = the server name)")
Config.Register("menus", "killfeedTime", 6, "Seconds a killfeed line stays")
Config.Register("menus", "killfeedMax", 6, "Most killfeed lines at once")
