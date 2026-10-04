--- Every window with a title bar and a close button (entity windows, Statistics, Finances, Company,
-- the vehicle store, layers, the notification log, mods' windows ...) can be minimized: a round
-- button in the title bar, in the design of the close button (the game's
-- fake-builtin-window-close-button style), folds the window to its title bar; a second click
-- unfolds it. The content stays mounted while folded (tabs, open sections and scroll positions are
-- kept) and the window keeps its place. A window that is closed opens unfolded next time.
--
-- The module field builtin.Window, which base recipes look up when they render, is wrapped:
--   * header: the window's header slot, which the engine draws in the title bar, holds the button,
--     right-aligned, so it sits next to the title bar's own buttons (rename, locate, pin, close; the
--     engine places the header before them, so it cannot go between pin and close);
--   * content: wrapped in UioMinimizable, whose root carries the class uio-folded while minimized
--     (minimize.css.lua hides it with visibility "none").
-- The field is replaced through builtin_wraps.lua, which keeps window recipes registered later
-- (react.RegisterWrapperRecipe) on the base builtin; without that the game crashes when such a
-- window opens (observed in game). Windows without a title bar
-- (compact: the Line Manager), without a close button, dialogs and popovers stay as they are.
-- Installed by minimize.script.lua.
-- @module ui_overhaul.gui.minimize
local builtin = require("::/gui/main/builtin.lua")
local gui_react_util = require("::/gui/main/gui_react_util.tl")
local react = require("::/gui/main/react.lua")
local builtin_wraps = require("ui_overhaul_1::/ui_overhaul/gui/builtin_wraps.lua")

---@class uo.gui.minimize
local minimize = {}

local EVENT = "uio.minimize"
local ICON_MINIMIZE = "gui/builtin/window/icons/symbol_minimize_18.tga" -- the game's own (statistics.tl)
local ICON_RESTORE = "gui/builtin/window/icons/symbol_maximize_18.tga"
local SKIPPED_CLASSES = { "popover", "dialog", "no-close-button", "construct-" }
local SKIPPED_TOOLS = { pause = true }

local minimized = {} ---@type table<string, true?> window key -> true while minimized

local reported = {} ---@type table<string, true>
---@param key string
---@param err any what pcall caught: an error can be any Lua value
local function report(key, err)
	if reported[key] then return end
	reported[key] = true
	debugPrint("[ui_overhaul] minimize: ", key, ": ", tostring(err))
end

--- Whether a window's parameters get the minimize button.
---@param p any what the window builtin got first: its params, or a ref, or anything a mod passes
---@return boolean
function minimize.eligible(p)
	if type(p) ~= "table" or p.content == nil or p.header ~= nil or p.compact then return false end
	if p.closable ~= true or SKIPPED_TOOLS[p.tool or ""] then return false end
	if type(p.title) ~= "string" or p.title == "" then return false end
	local class = p.meta and p.meta.class ---@type any whatever a mod passes; checked below
	if type(class) == "string" then
		for _i, skipped in ipairs(SKIPPED_CLASSES) do
			if class:find(skipped, 1, true) then return false end
		end
	end
	return true
end

--- A key that tells the window apart from the others open at the same time.
---@param p builtin.WindowParam
---@return string
function minimize.key(p)
	if type(p.id) == "string" and p.id ~= "" then return "id:" .. p.id end
	if type(p.tool) == "string" and p.tool ~= "" and p.tool ~= "entityWindow" then return "tool:" .. p.tool end
	return "title:" .. tostring(p.title)
end

--- Minimizes or restores the window `key`.
---@param key string
function minimize.toggle(key)
	minimized[key] = not minimized[key] or nil
	react.fireEvent(nil, EVENT, key)
end

-- Re-renders the caller when window `key` folds or unfolds; returns whether it is folded.
---@param key string
---@return boolean
local function use_folded(key)
	local state = react.useState(minimized[key] == true)
	react.onEvent(EVENT, function(_e, changed)
		if changed == key then state:set(minimized[changed] == true) end
	end)
	return state:old()
end

---@class uo.minimize.MinimizableParams: react.Param
---@field key string
---@field content? react.TreeNodeId

---@param params uo.minimize.MinimizableParams
---@return react.TreeNodeId
local Minimizable = react.RegisterRecipe("UioMinimizable", function(params)
	local key = params.key
	local folded = use_folded(key)
	-- testbench: "uio.debug.minimize_all" folds or unfolds every window
	react.onEvent("uio.debug.minimize_all", function() minimize.toggle(key) end)
	react.onUnmount(function() minimized[key] = nil end) -- a closed window opens unfolded next time
	return builtin.BoxLayout{
		meta = { class = folded and "uio-folded" or "uio-unfolded" },
		orientation = builtin.type.Orientation.Vertical,
		children = { params.content },
	}
end)

---@class uo.minimize.MinimizeButtonParams: react.Param
---@field key string

---@param params uo.minimize.MinimizeButtonParams
---@return react.TreeNodeId
local MinimizeButton = react.RegisterRecipe("UioMinimizeButton", function(params)
	local folded = use_folded(params.key)
	return builtin.BoxLayout{
		meta = { class = "uio-minimize-header" },
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			gui_react_util.makeHorizontalSpacer(),
			builtin.Button{
				-- no component id: a window can be rendered twice, and ids must be unique
				meta = { class = "fake-builtin-window-close-button, uio-minimize",
					tooltip = folded and _("Restore") or _("Minimize") },
				content = builtin.ImageView{ path = folded and ICON_RESTORE or ICON_MINIMIZE,
					scaling = builtin.type.ImageViewScaling.AutoFit },
				onClick = function() minimize.toggle(params.key) end,
			},
		},
	}
end)

--- A copy of `t` with the same fields and values.
---@generic T: table
---@param t T
---@return T
local function shallow_copy(t)
	local copy = {}
	-- LuaLS cannot infer pairs()'s key and value types for a generic table
	---@diagnostic disable-next-line: no-unknown
	for k, v in pairs(t) do copy[k] = v end
	return copy
end

---@param base function builtin.Window, or another mod's wrap of it
---@return function
local function wrap_window(base)
	---@param p any what the window builtin gets first: its params, or a ref
	---@param ... any the rest, passed on unchanged
	---@return react.TreeNodeId
	return function(p, ...)
		if select("#", ...) == 0 then
			local ok, eligible = pcall(minimize.eligible, p)
			if ok and eligible then
				local key = minimize.key(p)
				local copy = shallow_copy(p) ---@type builtin.WindowParam eligible() checked the table
				copy.content = Minimizable{ key = key, content = copy.content }
				copy.header = MinimizeButton{ key = key }
				return base(copy)
			elseif not ok then
				report("eligible", eligible)
			end
		end
		return base(p, ...)
	end
end

--- Called from the react-replacement-config before the UI starts.
---@param _replacement_api react.ReplacementApi
function minimize.install(_replacement_api)
	-- builtin_wraps also keeps window recipes registered later on the base builtin
	builtin_wraps.wrap("Window", wrap_window)
	debugPrint("[ui_overhaul] window minimize installed")
end

return minimize
