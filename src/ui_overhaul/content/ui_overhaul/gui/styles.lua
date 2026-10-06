--- Classes the stylesheets (*.css.lua) select by, so that a rule on the game's own elements applies
-- only while its feature is shown.
--
-- The game runs the stylesheets once, before the replacement configs, in a Lua state of their own
-- without api.engine (observed in game): they can read neither the player's settings nor which mod
-- comes first. So every rule must select something only this mod puts there while the feature is
-- shown: a uio- class or an R::Uio recipe (spec/gui/stylesheets_spec.lua checks every rule). For the
-- game's own elements inside a window, that is a class on the window: every window gets
--   * "uio-on-<feature>" for a feature that is shown (priority.active), and
--   * "uio-own-<feature>" for a feature whose own version shows, no mod that comes first having
--     the last word in it (priority.outranked), for elements it shares with such a mod,
-- but only the ones a stylesheet selects (CLASSES). A feature key's underscores are written as
-- hyphens there: the game's selector parser does not take an underscore in a class name (observed in
-- game: Window!uio-on-station_terminals matched no window, Window!uio-on-construction did).
-- The classes are set once the load order is decided (`decide`, after priority.late); until then
-- no window is drawn.
-- @module ui_overhaul.gui.styles
local builtin_wraps = require("ui_overhaul_1::/ui_overhaul/gui/builtin_wraps.lua")
local guard = require("ui_overhaul_1::/ui_overhaul/gui/guard.lua")
local priority = require("ui_overhaul_1::/ui_overhaul/gui/priority.lua")

---@class uo.gui.styles
local styles = {}

local report = guard.reporter("styles: ")

-- The classes the stylesheets select by, in the order a window gets them: feature and kind ("on":
-- shown, "own": its own version shows). spec/gui/stylesheets_spec.lua checks that every class a rule
-- selects is here.
---@type { [1]: string, [2]: "on"|"own" }[]
styles.CLASSES = {
	{ "station_terminals", "on" }, -- terminals.css.lua: room for the buttons in the station window
	{ "terminals", "own" }, -- terminals.css.lua: the width of the terminal popover
	{ "construction", "on" }, -- construction.css.lua: the construction settings above the game bar
	{ "minimize", "on" }, -- minimize.css.lua: the Line Manager keeps its height
	{ "notifications", "on" }, -- notifications.css.lua: notification colours inside windows
}

-- the classes every window gets, ", "-separated; nil until decided or where none applies
local window_classes ---@type string?

--- The window class of feature `key` while it is shown.
---@param key string a feature of styles.CLASSES
---@return string
function styles.on(key)
	return "uio-on-" .. (key:gsub("_", "-"))
end

--- The window class of feature `key` while its own version shows.
---@param key string a feature of styles.CLASSES
---@return string
function styles.own(key)
	return "uio-own-" .. (key:gsub("_", "-"))
end

--- The classes every window gets, from the decisions: see the module comment.
---@param active fun(key: string): boolean
---@param outranked fun(key: string): boolean
---@return string?
function styles.classes(active, outranked)
	local classes = {} ---@type string[]
	for _i, entry in ipairs(styles.CLASSES) do
		local key, kind = entry[1], entry[2]
		if active(key) and (kind == "on" or not outranked(key)) then
			classes[#classes + 1] = kind == "on" and styles.on(key) or styles.own(key)
		end
	end
	return #classes > 0 and table.concat(classes, ", ") or nil
end

--- Whether `x` is one of react's special first arguments (react.ref, react.style), not params.
---@param x any
---@return boolean
local function special(x)
	return type(x) == "table" and (x.is_react_ref_info == true or x.is_react_style_info == true)
end

--- The window params `p` with the classes added to its meta; `p` itself is not changed.
---@param p builtin.WindowParam
---@param classes string
---@return builtin.WindowParam
function styles.with_classes(p, classes)
	local copy = guard.shallow_copy(p) ---@type builtin.WindowParam
	local meta = p.meta and guard.shallow_copy(p.meta) or {} ---@type react.Meta
	local own = meta.class
	meta.class = (type(own) == "string" and own ~= "") and own .. ", " .. classes or classes
	copy.meta = meta
	return copy
end

--- Wraps builtin.Window so that every window gets the classes (from `decide` on).
---@param base function builtin.Window, or another wrap of it
---@return function
function styles.wrap_window(base)
	---@param ... any the window's arguments: its params, after a react.ref or react.style if given
	---@return react.TreeNodeId
	return function(...)
		local classes = window_classes
		if classes == nil then return base(...) end
		local args = table.pack(...) ---@type table<integer, any> the window's arguments, whatever they are
		local index = 1
		while index <= 2 and special(args[index]) do index = index + 1 end
		local p = args[index] ---@type any
		if type(p) ~= "table" then return base(...) end
		local ok, copy = pcall(styles.with_classes, p --[[@as builtin.WindowParam]], classes)
		if not ok then
			report("window", copy)
			return base(...)
		end
		args[index] = copy
		return base(table.unpack(args, 1, select("#", ...)))
	end
end

--- Called by installer.lua before the UI starts, after the features' installs.
function styles.install()
	builtin_wraps.wrap("Window", styles.wrap_window)
end

--- Called by installer.lua once the load order is decided (after priority.late).
function styles.decide()
	window_classes = styles.classes(priority.active, priority.outranked)
	debugPrint("[ui_overhaul] window classes: ", window_classes or "none")
end

return styles
