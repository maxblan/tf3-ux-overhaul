std = "lua53"

-- Globals provided by Transport Fever 3.
read_globals = { "api", "app", "debugPrint" }

-- Resource files the engine loads directly (not via require) define the global data() it calls.
files["**/*.gs.lua"] = { globals = { "data" } }
files["**/*.script.lua"] = { globals = { "data" } }
files["**/app_script.lua"] = { globals = { "data" } }

files["spec"] = { std = "+busted" }
-- Loads resource files the way the engine does, through the global data().
files["spec/support/mock_engine.lua"] = { globals = { "data" } }
-- The Busted shim defines the Busted globals.
files["tools/lua/busted.lua"] = { globals = { "describe", "it", "before_each", "after_each" } }
-- Provided by tools/lua/run.js.
files["tools/lua/lint.lua"] = { read_globals = { "read_file" } }

max_line_length = 120
