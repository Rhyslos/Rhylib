--[[
    Admin commands (shared list; the server runs them, sv_10_admin.lua).

    { id, name, cat, perm (default = id), target, args, desc, aliases }
      target: "player"  an online player (required)
              "self"    an online player, or yourself when left out
              "opt"     an online player, or nobody when left out
              "id"      an online player or any SteamID / SteamID64
              nil       no target
      args: { { key, label, kind } } in order; kinds:
              text (the rest of the line), word, number, duration ("30m",
              "2h", "1d", "1w", "perm"), rank, rosterrank, battalion,
              qual, onoff, map, class, job
    Chat: !id target args  (or /id); quotes for names with spaces.
    Targets: name (or part of it), SteamID, SteamID64, ^ = you, @ = the
    player you're looking at.
]]

local Admin = Rhylib.Admin

Admin.COMMANDS = {
    -- Discipline
    { id = "kick", name = "Kick", cat = "Discipline", target = "player", args = { { "reason", "Reason", "text" } }, desc = "Disconnect a player" },
    { id = "ban", name = "Ban", cat = "Discipline", target = "id",
      args = { { "time", "Length (30m, 2h, 1d, 1w, perm)", "duration" }, { "reason", "Reason", "text" } },
      desc = "Ban by name or SteamID (offline too); perm or over the limit needs permaban" },
    { id = "unban", name = "Unban", cat = "Discipline", target = "id", args = {}, desc = "Lift a ban (SteamID)" },
    { id = "warn", name = "Warn", cat = "Discipline", target = "player", args = { { "reason", "Reason", "text" } }, desc = "A logged warning the player sees" },
    { id = "mute", name = "Mute chat", cat = "Discipline", target = "player", args = {}, desc = "No text chat until unmuted or they leave" },
    { id = "unmute", name = "Unmute chat", cat = "Discipline", target = "player", args = {} },
    { id = "gag", name = "Gag voice", cat = "Discipline", target = "player", args = {}, desc = "No voice until ungagged or they leave" },
    { id = "ungag", name = "Ungag voice", cat = "Discipline", target = "player", args = {} },
    { id = "freeze", name = "Freeze", cat = "Discipline", target = "player", args = {} },
    { id = "unfreeze", name = "Unfreeze", cat = "Discipline", target = "player", args = {} },
    { id = "slay", name = "Slay", cat = "Discipline", target = "player", args = {} },
    { id = "respawn", name = "Respawn", cat = "Discipline", target = "self", args = {} },
    { id = "warnings", name = "Show warnings", cat = "Discipline", perm = "warn", target = "id", args = {}, desc = "Their warning history (to you)" },
    { id = "setjob", name = "Set job", cat = "Discipline", target = "self", args = { { "job", "Job command or name", "job" } }, desc = "DarkRP job, skipping its checks" },
    { id = "spectate", name = "Spectate", cat = "Teleport", target = "player", args = {}, aliases = { "spec" }, desc = "Watch them; run again (or !unspectate) to stop" },
    { id = "unspectate", name = "Stop spectating", cat = "Teleport", perm = "spectate", args = {} },
    { id = "who", name = "Staff online", cat = "Server", perm = "logs", args = {}, desc = "Lists online staff and their ranks (to you)" },

    -- Moving people
    { id = "goto", name = "Go to", cat = "Teleport", target = "player", args = {} },
    { id = "bring", name = "Bring", cat = "Teleport", target = "player", args = {} },
    { id = "return", name = "Return", cat = "Teleport", target = "self", args = {}, desc = "Back to where they were before goto / bring / teleport" },
    { id = "teleport", name = "Teleport to aim", cat = "Teleport", target = "self", args = {}, aliases = { "tp" }, desc = "To where you're looking" },

    -- Powers (toggles; on yourself when no target)
    { id = "noclip", name = "Noclip", cat = "Powers", target = "self", args = {}, desc = "Toggle (staff with noclip can also use the noclip key)" },
    { id = "god", name = "God mode", cat = "Powers", target = "self", args = {} },
    { id = "cloak", name = "Invisible", cat = "Powers", target = "self", args = {}, aliases = { "invis" } },
    { id = "notarget", name = "No target", cat = "Powers", target = "self", args = {}, desc = "NPCs and droids ignore them" },
    { id = "hp", name = "Set health", cat = "Powers", target = "self", args = { { "amount", "Health", "number" } }, aliases = { "health" } },
    { id = "armor", name = "Set armour", cat = "Powers", target = "self", args = { { "amount", "Armour", "number" } }, aliases = { "armour" } },
    { id = "give", name = "Give weapon", cat = "Powers", target = "self", args = { { "class", "Weapon class", "class" } } },

    -- Ranks
    { id = "rank", name = "Set staff rank", cat = "Ranks", target = "id", args = { { "rank", "Rank", "rank" } }, desc = "Below your own rank only" },
    { id = "rrank", name = "Set roster rank", cat = "Ranks", perm = "roster", target = "id", args = { { "rank", "Rank", "rosterrank" } }, aliases = { "rosterrank" } },
    { id = "battalion", name = "Set battalion", cat = "Ranks", perm = "roster", target = "id", args = { { "bn", "Battalion", "battalion" } }, desc = "Moves them in as PVT" },
    { id = "unbattalion", name = "Remove from battalion", cat = "Ranks", perm = "roster", target = "id", args = {} },
    { id = "train", name = "Pass basic training", cat = "Ranks", perm = "roster", target = "id", args = {} },
    { id = "qual", name = "Qualification", cat = "Ranks", perm = "roster", target = "id", args = { { "qual", "Qualification", "qual" }, { "on", "On / off", "onoff" } } },
    { id = "charreset", name = "Reset character", cat = "Ranks", target = "player", args = {}, desc = "They pick a new number and nickname" },

    -- Server / events
    { id = "map", name = "Change map", cat = "Server", args = { { "map", "Map", "map" } }, desc = "After a 10 s countdown" },
    { id = "cleanup", name = "Clean up spawned things", cat = "Server", target = "opt", args = {}, desc = "Everything players spawned (props, entities, NPCs...), or one player's with a target (^ = yours)" },
    { id = "cancelmap", name = "Cancel map change", cat = "Server", perm = "map", args = {} },
    { id = "announce", name = "Announcement", cat = "Server", args = { { "text", "Text", "text" } }, aliases = { "a" }, desc = "A banner for everyone" },
}

Admin.byId = {}
Admin.byAlias = {}
for i, c in ipairs(Admin.COMMANDS) do
    c.order = i
    c.perm = c.perm or c.id
    Admin.byId[c.id] = c
    Admin.byAlias[c.id] = c
    for _, a in ipairs(c.aliases or {}) do Admin.byAlias[a] = c end
end

-- "30m" / "2h" / "1d" / "1w" / "perm" / "0" / "45" (minutes) -> minutes (0 = forever), or nil.
function Admin.ParseDuration(s)
    s = string.lower(string.Trim(s or ""))
    if s == "perm" or s == "permanent" or s == "forever" or s == "0" then return 0 end
    local n, u = string.match(s, "^(%d+%.?%d*)%s*([mhdwy]?)$")
    n = tonumber(n)
    if not n or n <= 0 or n ~= n or n == math.huge then return nil end
    local mult = { [""] = 1, m = 1, h = 60, d = 1440, w = 10080, y = 525600 }
    return math.max(1, math.ceil(n * mult[u]))   -- never 0 (that's "perm")
end

function Admin.FormatMinutes(m)
    if not m or m <= 0 then return "permanently" end
    if m % 10080 == 0 then return (m / 10080) .. " week" .. (m == 10080 and "" or "s") end
    if m % 1440 == 0 then return (m / 1440) .. " day" .. (m == 1440 and "" or "s") end
    if m % 60 == 0 then return (m / 60) .. " hour" .. (m == 60 and "" or "s") end
    return m .. " minute" .. (m == 1 and "" or "s")
end

-- Splits a command line into words; "quoted text" stays one word.
function Admin.Split(line)
    local out = {}
    line = line or ""
    local i = 1
    while i <= #line do
        local c = string.sub(line, i, i)
        if c == " " or c == "\t" then
            i = i + 1
        elseif c == '"' then
            local j = string.find(line, '"', i + 1, true) or (#line + 1)
            out[#out + 1] = string.sub(line, i + 1, j - 1)
            i = j + 1
        else
            local j = string.find(line, "[ \t]", i) or (#line + 1)
            out[#out + 1] = string.sub(line, i, j - 1)
            i = j
        end
    end
    return out
end
