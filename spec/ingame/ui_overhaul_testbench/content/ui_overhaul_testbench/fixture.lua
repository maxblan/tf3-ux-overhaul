--- Which game the in-game test runs on. spec/ingame/run.sh rewrites this file in the staging copy:
-- with --save <name> the app script loads a copy of that savegame (named "uio_fixture") instead of
-- starting a small new map; --with-mod <id> adds installed mods (`mods`), and the GUI checks expect
-- what those mods change.
-- @module ui_overhaul_testbench.fixture
---@class uo.testbench.Fixture
---@field save string? the savegame copy to load; nil starts a small new map
---@field mods string[] installed mods to add
---@field only string[]? run.sh --only: the GUI checks to run; nil runs all
---@field gallery? boolean run.sh --gallery: the gallery scenes instead of the checks, with only the
--- game's own mods (urbangames_*) besides this mod and the testbench
---@field vanilla? boolean run.sh --vanilla: without the mod (the gallery's "before" shots)
local fixture = { save = nil, mods = {} }
return fixture
