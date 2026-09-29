# Rhylib

A free, modular Clone Wars roleplay suite for Garry's Mod, built for performance first.

Rhylib is a set of addons that run on top of DarkRP / StarWarsRP. One required core addon holds shared code, and every other system (weapons, HUD, stamina, medic, inventory and so on) is a separate addon that hosts can add or leave out.

## Repository layout

```
addons/
  rhylib_core/          required: loader, config, hook bus, networking, data, permissions, profiler, UI kit
    addon.json
    lua/autorun/_rhylib_core.lua
    lua/rhylib/core/*.lua
docs/                   design notes and the host config example
tools/link-addons.bat   links the addons into Garry's Mod for live testing
```

Each folder in `addons/` is a complete Garry's Mod addon.

## Development setup (Windows)

1. Clone the repo somewhere outside the Garry's Mod folder, for example `C:\dev\Rhylib`.
2. Open `tools\link-addons.bat` in a text editor and check that `GMOD_ADDONS` points at your `garrysmod\addons` folder. Set `SERVER_ADDONS` too if you run a local dedicated server.
3. Run `tools\link-addons.bat`. It creates a junction for each addon, so Garry's Mod loads them straight from the repo. Run it again whenever a new addon folder is added.
4. Start a game. The console should show `[Rhylib:core] Loaded module Core 0.1.0`.

Saving a Lua file reloads it in game. New files, models and materials need a map restart.

Test networking on a dedicated server, not only in singleplayer or a listen server. The listen server host is both client and server, which hides networking bugs.

## Console commands

| Command | Where | What it does |
| --- | --- | --- |
| `rhylib_status` | Server | Lists loaded Rhylib modules |
| `rhylib_profile 1` | Both | Starts recording hook time and net traffic |
| `rhylib_profile_report` | Server | Prints the server profile |
| `rhylib_profile_report_cl` | Client | Prints your client profile |
| `rhylib_profile_reset` | Server | Clears the recorded numbers |

## Configuration

Hosts override settings in a separate addon, so Workshop updates never overwrite them. See `docs/config-example.lua`.

## Performance rules

Every module follows these:

1. Hooks go through `Rhylib.Hook`, never `hook.Add` directly.
2. Nothing is networked per tick. Send events when something changes, only to players who need them.
3. Small, frequent events use `Rhylib.Net.CreateBatch`. Write exact bit sizes; never `net.WriteTable` for frequent messages.
4. Use timers (0.1 to 0.5 s) instead of per-frame checks wherever possible.
5. Saving uses `Rhylib.Data`, which batches writes.
6. Prefer engine networking (DT vars, bodygroups, health) over custom messages.
7. Check the cost with the profiler before shipping a module.

## License

Free to use on your server. Don't re-upload or sell it.
