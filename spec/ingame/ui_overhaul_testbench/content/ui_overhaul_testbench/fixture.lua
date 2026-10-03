--- Which game the in-game test runs on. spec/ingame/run.sh --save <name> rewrites this file in the
-- staging copy: the app script then loads a copy of that savegame (named "uio_fixture") with the
-- mod and the testbench added, instead of starting a small new map.
-- @module ui_overhaul_testbench.fixture
return { save = nil }
