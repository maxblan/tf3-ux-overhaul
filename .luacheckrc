-- The game embeds Lua 5.2.2 (TransportFever3.exe strings); specs run on fengari (Lua 5.3).
std = "lua52"

-- Globals provided by Transport Fever 3.
-- "_" is the engine's translation function.
read_globals = { "api", "app", "debugPrint", "_", "pGetText" }
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
files["src/ux_overhaul/content/ux_overhaul/gui/statistics_lines.lua"] = { max_line_length = 140 }
