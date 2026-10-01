--[[
    Chat, server side: checks each message and sends it only to the
    players its channel reaches. One small net message per recipient
    group, nothing per tick.

    Others can listen to Rhylib.ChatMessage(sender, channelId, text, target)
    (e.g. for logs). Messages also go to the server console.
]]

local Chat = Rhylib.Chat
local Config = Rhylib.Config

Rhylib.Net.Register("chat.msg")
Rhylib.Perms.Register("rhylib.chat.admin", "admin", "See the admin chat channel")

local lastAdvert = setmetatable({}, { __mode = "k" })

local function send(recipients, ch, sender, text, target)
    if #recipients == 0 then return end
    Rhylib.Net.Start("chat.msg")
    net.WriteUInt(ch.index, Chat.CHANNEL_BITS)
    net.WriteEntity(sender)
    net.WriteEntity(target or NULL)
    net.WriteString(text)
    net.Send(recipients)
end

local function note(ply, text)
    Rhylib.Net.Start("chat.msg")
    net.WriteUInt(0, Chat.CHANNEL_BITS)  -- 0 = a system note to this player only
    net.WriteEntity(NULL)
    net.WriteEntity(NULL)
    net.WriteString(text)
    net.Send(ply)
end
Chat.Note = note

local route = {}

route.public = function(ply, ch, text)
    send(player.GetHumans(), ch, ply, text)
end

route["local"] = function(ply, ch, text)
    local range = Config.Get("chat", "localRange")
    local pos, list = ply:GetPos(), {}
    for _, p in ipairs(player.GetHumans()) do
        if p:GetPos():DistToSqr(pos) <= range * range then list[#list + 1] = p end
    end
    send(list, ch, ply, text)
end

route.advert = function(ply, ch, text)
    local wait = (lastAdvert[ply] or 0) + Config.Get("chat", "advertCooldown") - CurTime()
    if wait > 0 then
        note(ply, string.format("You can advertise again in %d s", math.ceil(wait)))
        return false
    end
    lastAdvert[ply] = CurTime()
    send(player.GetHumans(), ch, ply, text)
end

-- Anyone can send; admins (CAMI permission) and the sender see it.
route.admin = function(ply, ch, text)
    send({ ply }, ch, ply, text)
    for _, p in ipairs(player.GetHumans()) do
        if p ~= ply then
            Rhylib.Perms.Check(p, "rhylib.chat.admin", function(ok)
                if ok and IsValid(p) and IsValid(ply) then send({ p }, ch, ply, text) end
            end)
        end
    end
end

route.pm = function(ply, ch, text, target)
    if not IsValid(target) or not target:IsPlayer() then
        note(ply, "No player by that name")
        return false
    end
    if target == ply then
        note(ply, "That's you")
        return false
    end
    send({ ply, target }, ch, ply, text, target)
end

Rhylib.Net.Receive("chat.send", function(ply)
    local ch = Chat.CHANNELS[net.ReadUInt(Chat.CHANNEL_BITS)]
    local target = net.ReadEntity()
    local text = string.Trim(net.ReadString())
    if not ch or text == "" then return end
    text = string.sub(text, 1, Config.Get("chat", "maxLength"))

    local fn = route[ch.id]
    if not fn or fn(ply, ch, text, target) == false then return end
    hook.Run("Rhylib.ChatMessage", ply, ch.id, text, IsValid(target) and target or nil)
    print(string.format("[Chat][%s] %s%s: %s", ch.name, ply:Nick(), IsValid(target) and (" -> " .. target:Nick()) or "", text))
end, { rate = 2, burst = 5 })

-- Typing indicator (the HUD's icons above heads read this).
Rhylib.Net.Receive("chat.typing", function(ply)
    ply:SetNW2Bool("rhylib_typing", net.ReadBool())
end, { rate = 4, burst = 4 })
