--- In-game scenarios, run in order by testbench.script.lua.
--
-- Each scenario has:
--   name         unique name, shown in the PASS/FAIL line
--   build(area)  sends the build commands; `area` = { x, y, base } is the scenario's own flat
--                piece of land (see site.lua)
--   wait         update() calls (0.2 s game time each) between build and check, so the engine
--                applies the builds and the mod under test can react
--   check(area)  returns passed (boolean) and a details string
--
-- Scenario functions run in a fresh Lua state each time (the engine does not keep module
-- state between game script calls): pass everything through `area`, not through upvalues.
-- @module ux_overhaul_testbench.scenarios
local track_builder = require("/ux_overhaul_testbench/track_builder.lua")

return {
	{
		name = "straight_track_is_built",
		build = function(area)
			local build = track_builder.new()
			track_builder.add_straight_track(build, area.y, area.x - 100, area.x + 100, area.base + 0.5)
			build.send()
		end,
		wait = 30,
		check = function(area)
			local edges = track_builder.edges_near(area.x, area.y, 120)
			return #edges == 1, "track edges=" .. #edges
		end,
	},
}
