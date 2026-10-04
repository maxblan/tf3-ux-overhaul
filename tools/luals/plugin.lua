-- Lua Language Server plugin: resolves the game's require paths, which LuaLS cannot map through
-- runtime.path.
--   "/ui_overhaul/x.lua", "ui_overhaul_1::/ui_overhaul/x.lua"  -> this mod's file
--   "/ui_overhaul_testbench/x.lua"                              -> the testbench's file
--   "::/gui/main/react.lua", "::/scripts/util.tl"               -> the stub in types/game/
-- Other names fall through to runtime.path.

-- LuaLS's own uri helper, available to plugins.
---@class uo.luals.FileUri
---@field decode fun(uri: string): string
---@field encode fun(path: string): string

---@type uo.luals.FileUri
local furi = require("file-uri")

local mod_roots = {
	"src/ui_overhaul/content",
	"spec/ingame/ui_overhaul_testbench/content",
}

---@param path string
---@return boolean
local function exists(path)
	local file = io.open(path)
	if file then file:close() end
	return file ~= nil
end

--- Called by LuaLS for every require; nil falls back to runtime.path.
---@param uri string the workspace uri
---@param name string the required name
---@return string[]? uris
function ResolveRequire(uri, name)
	local root = furi.decode(uri)
	---@type string?
	local game_path = name:match("^::(/.+)%.[%a]+$")
	if game_path then
		local path = root .. "/types/game" .. game_path .. ".lua"
		return exists(path) and { furi.encode(path) } or nil
	end
	---@type string?
	local mod_path = name:match("^[%w_]*::(/.+)$") or name:match("^(/.+)$")
	if mod_path then
		for _, mod_root in ipairs(mod_roots) do
			local path = root .. "/" .. mod_root .. mod_path
			if exists(path) then return { furi.encode(path) } end
		end
	end
	return nil
end
