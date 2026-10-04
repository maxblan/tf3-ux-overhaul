--- Entity windows (vehicle, line, station, town, industry ...) can be minimized: a small button in
-- the top right corner of the window's content folds the window to its title bar and a slim row
-- with the restore button; a second click unfolds it. The window keeps its place. Useful with the
-- mod's side-by-side windows (tool_stack.lua). Sections that were open stay open, as the mod
-- remembers them (window_tweaks.lua); a closed window opens unfolded next time.
-- The module function make_entity_window.makeEntityWindowContent, which the window manager calls
-- through the module table for every entity window, is wrapped: the content recipe it returns is
-- rendered inside the recipe UioMinimizable, which shows either the content with the button over its
-- corner or the restore row. The window itself (builtin.Window) is not touched: a wrapped Window
-- builtin breaks window recipes that other code registers later (they no longer find the builtin,
-- and the game crashes when such a window opens; observed in-game). Installed by minimize.script.lua.
-- @module ui_overhaul.gui.minimize
local builtin = require("::/gui/main/builtin.lua")
local make_entity_window = require("::/gui/entity_window/make_entity_window.tl")
local gui_react_util = require("::/gui/main/gui_react_util.tl")
local react = require("::/gui/main/react.lua")

local minimize = {}

local EVENT = "uio.minimize"
local ICON_MINIMIZE = "gui/builtin/window/icons/symbol_minimize_18.tga" -- the game's own (statistics.tl)
local ICON_RESTORE = "gui/builtin/window/icons/symbol_maximize_18.tga"

local minimized = {} -- window key -> true while minimized

local reported = {}
local function report(key, err)
	if reported[key] then return end
	reported[key] = true
	debugPrint("[ui_overhaul] minimize: ", key, ": ", tostring(err))
end

--- Minimizes or restores the window `key`.
function minimize.toggle(key)
	minimized[key] = not minimized[key] or nil
	react.fireEvent(nil, EVENT, key)
end

local function button(key, folded)
	return builtin.Button{
		-- no component id: a window can render its content twice (the industry window's tabs), and ids
		-- must be unique (a duplicate is a React error, observed in-game)
		meta = { class = "uio-minimize", tooltip = folded and _("Restore") or _("Minimize") },
		content = builtin.ImageView{ path = folded and ICON_RESTORE or ICON_MINIMIZE,
			scaling = builtin.type.ImageViewScaling.AutoFit },
		onClick = function() minimize.toggle(key) end,
	}
end

local function render(params)
	local key = params.key
	local state = react.useState(minimized[key] == true)
	react.onEvent(EVENT, function(_e, changed)
		if changed == key then state:set(minimized[changed] == true) end
	end)
	-- testbench: "uio.debug.minimize_all" folds or unfolds every entity window
	react.onEvent("uio.debug.minimize_all", function() minimize.toggle(key) end)
	-- a closed window opens unfolded next time
	react.onUnmount(function() minimized[key] = nil end)
	if state:old() then
		return builtin.BoxLayout{
			meta = { class = "uio-minimized" },
			orientation = builtin.type.Orientation.Horizontal,
			children = { gui_react_util.makeHorizontalSpacer(), button(key, true) },
		}
	end
	return builtin.FloatingLayout{
		children = {
			builtin.FloatingLayoutChild{ h = -1, v = -1, item = params.content },
			builtin.FloatingLayoutChild{ h = 1, v = 0, item = builtin.BoxLayout{ children = { button(key, false) } } },
		},
	}
end

local Minimizable = react.RegisterRecipe("UioMinimizable", function(params)
	local content = params.inner(params.innerParam)
	local ok, node = pcall(render, { key = params.key, content = content })
	if ok then return node end
	report("render", node)
	return builtin.BoxLayout{ children = { content } }
end)

--- The window manager's result for an entity window, with its content recipe inside UioMinimizable.
-- Other results (no recipe, or a builtin content) are returned unchanged.
function minimize.wrap_result(result, entity)
	if type(result) ~= "table" or type(result.recipe) ~= "function" or entity == nil then return result end
	local copy = {}
	for k, v in pairs(result) do copy[k] = v end
	copy.recipe = Minimizable
	copy.param = { key = "entity_" .. tostring(entity), inner = result.recipe, innerParam = result.param,
		keyEntity = result.param and result.param.keyEntity or entity }
	return copy
end

--- Called from the react-replacement-config before the UI starts.
function minimize.install(_replacement_api)
	local original = make_entity_window.makeEntityWindowContent
	if type(original) ~= "function" then error("makeEntityWindowContent not found") end
	make_entity_window.makeEntityWindowContent = function(entity, ...)
		local result = original(entity, ...)
		local ok, wrapped = pcall(minimize.wrap_result, result, entity)
		if ok then return wrapped end
		report("wrap", wrapped)
		return result
	end
	debugPrint("[ui_overhaul] window minimize installed")
end

return minimize
