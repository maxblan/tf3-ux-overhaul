-- The game embeds Lua 5.2.2 (TransportFever3.exe strings); specs run on fengari (Lua 5.3).
std = "lua52"

-- No globals defined by assignment. Unused arguments and values are reported by default (see ignore below).
allow_defined = false
allow_defined_top = false

-- Globals provided by Transport Fever 3.
-- "_" is the engine's translation function.
read_globals = { "api", "app", "debugPrint", "_", "pGetText", "nGetText" }
-- Variables named with a leading underscore are intentionally unused.
ignore = { "21./_.*" }

-- Resource files the engine loads directly (not via require) define the global data() it calls.
files["**/*.gs.lua"] = { globals = { "data" } }
files["**/*.script.lua"] = { globals = { "data" } }
files["**/app_script.lua"] = { globals = { "data" } }
files["**/*.res.lua"] = { globals = { "data" } }
files["**/*.css.lua"] = { globals = { "data" } }

files["spec"] = { std = "+busted" }
-- Loads resource files the way the engine does, through the global data().
files["spec/support/mock_engine.lua"] = { globals = { "data" } }
-- The Busted shim defines the Busted globals.
files["tools/lua/busted.lua"] = { globals = { "describe", "it", "before_each", "after_each" } }
-- Provided by tools/lua/run.js.
files["tools/lua/lint.lua"] = { read_globals = { "read_file" } }

max_line_length = 120
-- Lua conversion of a base game file; keeps the base layout to ease diffing after game updates.
files["src/ui_overhaul/content/ui_overhaul/gui/statistics_lines.lua"] = { max_line_length = 140 }
files["src/ui_overhaul/content/ui_overhaul/gui/statistics_vehicles.lua"] = { max_line_length = 140 }
files["src/ui_overhaul/content/ui_overhaul/gui/statistics_stations.lua"] = { max_line_length = 140 }
-- Wraps the engine's global orderedPairs and reads the React registry _react (base/init.lua).
files["src/ui_overhaul/content/ui_overhaul/gui/station_terminals.lua"] = {
	globals = { "orderedPairs" }, read_globals = { "api", "app", "debugPrint", "_", "_react" },
}
-- Reads the React registry _react (base/init.lua): which recipes wrap builtin.Window.
files["src/ui_overhaul/content/ui_overhaul/gui/minimize.lua"] = {
	read_globals = { "api", "app", "debugPrint", "_", "_react" },
}
-- Reads the React registry _react (base/init.lua): a builtin's recipe id.
files["src/ui_overhaul/content/ui_overhaul/gui/builtin_wraps.lua"] = {
	read_globals = { "api", "app", "debugPrint", "_", "_react" },
}
-- Reads the React registry _react (base/init.lua): the registered extension points; and the loader's
-- registry of loaded modules _ug_loadedModules (base/init.lua).
-- It also watches what the other mods' configs write there, and puts the modules loaded meanwhile back.
files["src/ui_overhaul/content/ui_overhaul/gui/priority.lua"] = {
	read_globals = { "api", "app", "debugPrint", "_", "_react" }, globals = { "_ug_loadedModules" },
}
-- Stand in for the loader's registry of loaded modules and the React registry.
files["spec/gui/priority_spec.lua"] = { std = "+busted", globals = { "_ug_loadedModules", "_react" } }
