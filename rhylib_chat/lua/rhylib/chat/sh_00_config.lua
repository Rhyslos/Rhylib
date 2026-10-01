--[[
    Chat channels and command parsing (shared).

    Channels: public, local, advert, admin, and private messages.
    (Squad, battalion and command come with those systems.)

    Typing:
      plain text            goes to your current channel (click the
                            channel name to change it, or type /local etc.)
      /public text  // text /ooc text      public
      /local text   /l text               people near you
      /advert text  /ad text              everyone, highlighted, with a cooldown
      /admin text   /a text               admins (anyone can send, for reports)
      /pm name text  /pm "two words" text a private message
      /local (nothing else)               switches your current channel

    Anything else starting with / or ! is passed on untouched, so DarkRP's
    commands (/job, /dropmoney, ...) and admin mod commands (!goto, ...)
    keep working. That choice is made in one place, Chat.Parse below: to
    take those over later, handle them there instead of returning "pass".
]]

Rhylib.Chat = Rhylib.Chat or {}
local Chat = Rhylib.Chat

-- index = network id (3 bits), keep the order stable.
Chat.CHANNELS = {
    { id = "public", name = "Public", color = Color(228, 227, 220), cmds = { "public", "p", "ooc" }, desc = "Everyone on the server" },
    { id = "local", name = "Local", color = Color(151, 196, 89), cmds = { "local", "l" }, desc = "People near you" },
    { id = "advert", name = "Advert", color = Color(239, 159, 39), cmds = { "advert", "ad" }, desc = "Everyone, highlighted (cooldown)" },
    { id = "admin", name = "Admin", color = Color(226, 75, 74), cmds = { "admin", "a" }, desc = "Reach the admins" },
    { id = "pm", name = "PM", color = Color(190, 150, 255), cmds = { "pm", "w", "msg" }, desc = "Private message: /pm name text", private = true },
}
Chat.byId, Chat.byCmd = {}, {}
for i, c in ipairs(Chat.CHANNELS) do
    c.index = i
    Chat.byId[c.id] = c
    for _, cmd in ipairs(c.cmds) do Chat.byCmd[cmd] = c end
end
Chat.CHANNEL_BITS = 3

local Config = Rhylib.Config
Config.Register("chat", "defaultChannel", "public", "Channel plain text goes to until a player picks another")
Config.Register("chat", "localRange", 600, "How far local chat carries (units)")
Config.Register("chat", "advertCooldown", 30, "Seconds between adverts per player")
Config.Register("chat", "maxLength", 300, "Longest message in characters")

-- Finds a player by (part of) their name. Exact matches win.
function Chat.FindPlayer(name)
    name = string.lower(name or "")
    if name == "" then return nil end
    local partial
    for _, p in ipairs(player.GetAll()) do
        local nick = string.lower(p:Nick())
        if nick == name then return p end
        if not partial and string.find(nick, name, 1, true) then partial = p end
    end
    return partial
end

--[[
    Works out what a line of typed text is. Returns one of:
      "send", channel, body, targetName   a Rhylib channel message
      "switch", channel                   just a channel command: change channel
      "pass"                              not ours: send it as normal chat
      "usage", text                       a Rhylib command used wrongly
    current: the channel plain text goes to.
]]
function Chat.Parse(text, current)
    if string.sub(text, 1, 2) == "//" then
        return "send", Chat.byId.public, string.Trim(string.sub(text, 3))
    end
    local first = string.sub(text, 1, 1)
    if first ~= "/" and first ~= "!" then
        return "send", current, text
    end
    if first == "!" then return "pass" end

    local cmd, rest = string.match(text, "^/(%S+)%s*(.*)$")
    local ch = cmd and Chat.byCmd[string.lower(cmd)]
    if not ch then return "pass" end  -- DarkRP's and other addons' commands

    if ch.private then
        local target, body = string.match(rest, '^"([^"]+)"%s*(.*)$')
        if not target then target, body = string.match(rest, "^(%S+)%s*(.*)$") end
        if not target or body == "" then return "usage", "Usage: /pm name message (\"quotes\" for names with spaces)" end
        return "send", ch, body, target
    end
    if rest == "" then return "switch", ch end
    return "send", ch, rest
end
