--- Runs luacheck's library API on the given files with the options from .luacheckrc.
-- For machines without the luacheck CLI (which needs LuaFileSystem); see tools/lua/run.js.
-- Supports the .luacheckrc subset used in this repository: top-level options and `files`
-- overrides keyed by a directory, an exact path, "**/<name>" or "**/*<suffix>".
-- Usage: node tools/lua/run.js tools/lua/lint.lua <file.lua>...
package.path = "tools/lua/vendor/luacheck/src/?.lua;tools/lua/vendor/luacheck/src/?/init.lua;" .. package.path

local luacheck = require("luacheck")

local function load_config(path)
	local config = { files = {} }
	local chunk = assert(loadfile(path, "t", setmetatable(config, { __index = _G })))
	chunk()
	return config
end

local function matches(pattern, file)
	local rest = pattern:match("^%*%*/(.+)$")
	if rest then
		local suffix = rest:match("^%*(.+)$")
		if suffix then return file:sub(-#suffix) == suffix end
		return file == rest or file:sub(-#rest - 1) == "/" .. rest
	end
	return file == pattern or file:sub(1, #pattern + 1) == pattern .. "/"
end

local function options_for(config, file)
	local options = {}
	for key, value in pairs(config) do
		if key ~= "files" then options[key] = value end
	end
	local patterns = {}
	for pattern in pairs(config.files) do patterns[#patterns + 1] = pattern end
	table.sort(patterns, function(a, b) return #a < #b end) -- more specific overrides last
	for _, pattern in ipairs(patterns) do
		if matches(pattern, file) then
			for key, value in pairs(config.files[pattern]) do options[key] = value end
		end
	end
	return options
end

local config = load_config(".luacheckrc")
local files = { table.unpack(arg) }
local sources, options = {}, {}
for i, file in ipairs(files) do
	sources[i] = read_file(file) -- provided by tools/lua/run.js
	options[i] = options_for(config, file)
end

local report = luacheck.check_strings(sources, options)
local warnings = 0
for i, file_report in ipairs(report) do
	for _, event in ipairs(file_report) do
		warnings = warnings + 1
		print(string.format("%s:%d:%d: (%s%s) %s", files[i], event.line, event.column,
			event.code:sub(1, 1) == "0" and "E" or "W", event.code, luacheck.get_message(event)))
	end
end
print(string.format("Checked %d files: %d warnings", #files, warnings))
return warnings > 0 and 1 or 0
