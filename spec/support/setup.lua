--- Busted helper (see .busted): makes the mod's modules loadable outside the game.
-- Run from the repository root.

package.path = "spec/support/?.lua;" .. package.path

local mod_paths = require("mod_paths")

-- Inside the game, require("/x/y.lua") resolves relative to the content folder of the mod that
-- owns the calling file, and "ui_overhaul_1::/x/y.lua" to this mod's. Mirror that for this mod.

---@param name string
---@return (function|string)? loader the chunk, or why there is none
---@return string? path
local function mod_searcher(name)
	-- a fully qualified path of this mod ("ui_overhaul_1::/x/y.lua") is the same file as "/x/y.lua"
	local own = name:match("^ui_overhaul_1::(/.*)$") or name ---@type string
	if own:sub(1, 1) ~= "/" then return nil end
	local path = mod_paths.content .. own ---@type string
	local chunk, err = loadfile(path)
	if not chunk then return "\n\tno file '" .. path .. "' (" .. tostring(err) .. ")" end
	return chunk, path
end
table.insert(package.searchers, 2, mod_searcher)
