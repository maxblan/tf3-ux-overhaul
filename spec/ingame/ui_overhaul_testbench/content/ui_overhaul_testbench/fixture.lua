--- Which game the in-game test runs on. spec/ingame/run.sh rewrites this file in the staging copy:
-- with --save <name> the app script loads a copy of that savegame (named "uio_fixture") instead of
-- starting a small new map; --with-mod <id> adds installed mods (`mods`), and the GUI checks expect
-- what those mods change.
-- @module ui_overhaul_testbench.fixture
return { save = nil, mods = {} }
