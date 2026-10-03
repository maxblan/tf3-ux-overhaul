--- Busted helper (see .busted): makes the mod's modules loadable outside the game.
-- Run from the repository root.

package.path = "spec/support/?.lua;" .. package.path

local mod_paths = require("mod_paths")

-- Inside the game, require("/x/y.lua") resolves relative to the content folder of the mod that
-- owns the calling file. Mirror that for this mod.

table.insert(package.searchers, 2, function(name)
	if name:sub(1, 1) ~= "/" then return nil end
	local path = mod_paths.content .. name
	local chunk, err = loadfile(path)
	if not chunk then return "\n\tno file '" .. path .. "' (" .. tostring(err) .. ")" end
	return chunk, path
end)
