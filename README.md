# Transport Fever 3 mod template

Starting point for Transport Fever 3 (TF3) script mods. It comes with offline specs against a mock engine, luacheck, automated in-game tests, the game's own validation, a preview image pipeline and deployment to the game's staging area. It is extracted from [Tunnel Portal Fix](https://github.com/maxblan/tunnel-portal-fix), whose README shows the tooling in use.

## Start a new mod

1. On GitHub, click **Use this template**, then clone your new repository.
2. Rename the placeholder mod:
   ```bash
   tools/init.sh signal_tweaks "Signal Tweaks"
   ```
3. Install the tooling and check that everything passes:
   ```bash
   make deps
   make lint test
   ```

The example mod (`main.script.lua`) logs how many track edges every build adds. Replace it with your own logic.

## Layout

```
src/ux_overhaul/                       the mod as the game loads it
  mod.json                        mod id (ux_overhaul_1), scripts, savegame severities
  _metadata/modinfo.json          name, summary, description, tags, url (shown on mod.io)
  _metadata/0.png                 preview image, 1920x1080 (make preview)
  _content.json                   content file list (generated: make content)
  content/ux_overhaul/
    main.gs.lua                   game script registration
    main.script.lua               game script (update / handleEvent / guiUpdate ...)
    track_stats.lua, logger.lua   modules, loaded with require("/ux_overhaul/....lua")
assets/preview.svg                source of the preview image
spec/                             Busted specs (*_spec.lua) against spec/support/mock_engine.lua
  ingame/run.sh                   in-game test driver (make test-ingame)
  ingame/ux_overhaul_testbench/        dev-only mod: app script that starts a test game, scenario runner
tools/
  init.sh                         rename the placeholder mod (run once)
  deploy.sh, validate.sh          staging area, the game's own validation
  content_index.sh                regenerate _content.json
  lua/                            fengari-based specs and luacheck for machines without native Lua
  preview/                        SVG to PNG renderer
```

## Make targets

```bash
make              # list targets
make deps         # once: fengari, luacheck source, SVG renderer
make lint         # luacheck
make test         # offline specs, seconds
make test-ingame  # in-game scenarios: starts the game, builds, checks, quits
make preview      # assets/preview.svg -> _metadata/0.png
make deploy       # regenerate _content.json, copy the mod into the game's staging area
make validate     # deploy, then run the game's mod validation (dist/validation.json)
make package      # dist/<mod>.zip
```

## Requirements

- **WSL** with the Windows Steam installation of TF3 under `C:\Program Files (x86)\Steam`, and Windows `node`.
- **Busted and luacheck** are used when installed. Otherwise specs and lint run on [fengari](https://github.com/fengari-lua/fengari).
- **In-game tests** need Steam running, the game closed, and a `steam_appid.txt` containing `3493540` in the game folder. Without that file, Steam asks for confirmation of the custom launch argument on every start.

## TF3 modding rules this template follows

- **Engine-loaded files:** files the engine loads as resources must define the global `data()`. These are `*.gs.lua`, the `*.script.lua` files they point to, and app scripts. Modules loaded with `require` are plain `local m = {} … return m` modules.
- **`require` paths:** `require("/x.lua")` resolves inside the owning mod; `require("::/x.lua")` resolves inside the base game.
- **Game script state:** game scripts run in changing Lua states. Keep state in `state:get()` / `state:set()`, not in module-level variables.
- **Commands from game scripts:** `api.cmd.sendCommand` from a game script must not pass a callback. List fields of engine objects are copies, so always assign whole lists.
- **Network changes after a build:** a game script that changes the track network after a player build must wait until no build tool is open (`api.gui.contextHelper.getIdsOfActiveTool()` is only `{ "EntityDetailsTool" }`). The open track tool crashes if its edges disappear.
- **Keep `mod.io_fileid.txt`:** after the first in-game publish, keep `_metadata/mod.io_fileid.txt` in the repository. `make deploy` adopts it from the staging area automatically. It links later publishes to the existing mod.io entry.

## Publishing

Publish from the game (Main menu → Mods → your staging mod → Publish) with a [mod.io](https://mod.io/g/transportfever3) account. The game validates the mod, cooks it and uploads it.

## License

[MIT](LICENSE). Transport Fever 3 is a trademark of Urban Games; this project is not affiliated with Urban Games or Paradox Interactive.
