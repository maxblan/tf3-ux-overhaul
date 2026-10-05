--- Catchment areas that stay on the map: two toggle buttons in the mod button area of the game bar,
-- one for the passenger and one for the cargo catchment areas of all stations, each switched on and
-- off separately. While one is on, the map shows those areas whenever no tool and no entity window
-- draws its own overlay (the station window, a layer, construction show theirs as before), and the
-- choice is saved with the game.
-- The areas are the game's own catchment overlay (LayerConfig.catchmentAreaRenderableConfig, as the
-- Infrastructure layer draws it). The default map action is built by the module function
-- selector_react_util.makeDefaultSelectorCombinedFn, which the window manager calls through the module
-- table; it is wrapped so its ActionDescriptor gets one more LayerConfig. Toggles: a plugin of
-- ::MainModButtonAreaExtension, one per button (catchment_buttons*.res.lua). Installed by
-- catchment.script.lua.
-- @module ui_overhaul.gui.catchment
local builtin = require("::/gui/main/builtin.lua")
local react = require("::/gui/main/react.lua")
local selector_react_util = require("::/gui/main/selector_react_util.tl")
local guard = require("ui_overhaul_1::/ui_overhaul/gui/guard.lua")
local priority = require("ui_overhaul_1::/ui_overhaul/gui/priority.lua")

local catchment = {}

---Which catchment areas the map shows.
---@class uo.gui.catchment.Shown: { [uo.gui.catchment.Kind]: boolean }
---@field person boolean
---@field cargo boolean

---@alias uo.gui.catchment.Kind "person"|"cargo"

local SAVE_KEY = "ui_overhaul_catchment"
local EVENT = "uio.catchment"

-- read from the savegame on first use
---@type uo.gui.catchment.Shown?
local shown

local report = guard.reporter("catchment: ")

--- The current choice (GUI thread).
---@return uo.gui.catchment.Shown
function catchment.get()
	if shown == nil then
		shown = { person = false, cargo = false }
		local ok, saved = pcall(api.gui.game.getGuiSaveData, SAVE_KEY)
		if ok and type(saved) == "table" then
			shown.person = saved.person == true or saved.person == "true"
			shown.cargo = saved.cargo == true or saved.cargo == "true"
		end
	end
	return { person = shown.person, cargo = shown.cargo }
end

--- Switches one kind ("person" or "cargo") on or off, saves the choice and tells the map action.
---@param kind uo.gui.catchment.Kind
---@param on boolean
function catchment.set(kind, on)
	local current = catchment.get()
	current[kind] = on and true or false
	shown = current
	local ok, err = pcall(api.gui.game.setGuiSaveData, SAVE_KEY,
		{ person = tostring(current.person), cargo = tostring(current.cargo) })
	if not ok then report("save", err) end
	react.fireEvent(nil, EVENT, current)
end

--- The game's catchment overlay for all stations, passenger and/or cargo areas.
---@param s uo.gui.catchment.Shown
---@return LayerConfig
function catchment.layer_config(s)
	local config = api.type.LayerConfig.new()
	local area = api.type.LayerConfig.CatchmentAreaRenderableConfig.new()
	local display = api.type.LayerConfig.CatchmentAreaDisplaySettings.new()
	display.innerAlpha = 0.4 -- as the Infrastructure layer (layer_infrastructure.tl)
	display.borderAlpha = 1.0
	display.godrayAlpha = 1.0
	area.isVisible = true
	area.displaySettings = display
	area.entity = -1
	area.person = s.person
	area.cargo = s.cargo
	config.catchmentAreaRenderableConfig = area
	return config
end

-- Calls `inner` (the base action function) with builtin.ActionDescriptor swapped for one that adds
-- the overlay to the children, for this call only.
---@param inner fun(): react.TreeNodeId
---@param s uo.gui.catchment.Shown
---@return react.TreeNodeId
local function with_overlay(inner, s)
	local base = builtin.ActionDescriptor
	-- called as the builtin is: (params) or (ref, params)
	---@param p? builtin.ActionDescriptorParam|react.RefFill
	---@param ... builtin.ActionDescriptorParam
	---@return react.TreeNodeId
	builtin.ActionDescriptor = function(p, ...)
		if select("#", ...) == 0 and type(p) == "table" then
			local ok, config = pcall(catchment.layer_config, s)
			if ok then
				---@cast p builtin.ActionDescriptorParam -- a table and the only argument: the params
				local copy = guard.shallow_copy(p)
				---@type react.TreeNodeId[]
				local children = {}
				for i, child in ipairs(p.children or {}) do children[i] = child end
				children[#children + 1] = builtin.LayerConfig{ config = config }
				copy.children = children
				return base(copy)
			end
			report("overlay", config)
		end
		return base(p, ...)
	end
	local ok, node = pcall(inner)
	builtin.ActionDescriptor = base
	if not ok then error(node, 0) end
	return node
end

---@alias uo.gui.catchment.Params game.gui.main.selector_react_util.DefaultSelectorCompParams
---@alias uo.gui.catchment.CombinedFn fun(params: uo.gui.catchment.Params, ...: any): (fun(): react.TreeNodeId)

-- `...: any`: arguments a future game version might add, passed on untouched (the game passes none)
---@param original uo.gui.catchment.CombinedFn
---@return uo.gui.catchment.CombinedFn
local function wrap_combined_fn(original)
	return function(params, ...)
		local inner = original(params, ...)
		return function()
			-- hooks before the base ones, the same on every render
			local state = react.useState(catchment.get())
			react.onEvent(EVENT, function(_e, s) state:set(s) end)
			local s = state:old()
			if not (s.person or s.cargo) then return inner() end
			return with_overlay(inner, s)
		end
	end
end

-- Toggle buttons ------------------------------------------------------------------------------------

---@param kind uo.gui.catchment.Kind
---@param icon string
---@param tooltip string
---@param value boolean
---@return react.TreeNodeId
local function toggle(kind, icon, tooltip, value)
	return builtin.ToggleButton{
		meta = { tooltip = tooltip, class = "uio-catchment-toggle", id = "uio.catchment." .. kind },
		content = builtin.ImageView{ meta = { class = "uio-catchment-icon" }, path = icon,
			scaling = builtin.type.ImageViewScaling.AutoFit },
		value = value and 1 or 0,
		onValueChange = function(v) catchment.set(kind, v == 1) end,
	}
end

-- One toggle, as its own plugin of the mod button area, so the area spaces it like its neighbours.
---@param kind uo.gui.catchment.Kind
---@param icon string
---@param tooltip string
---@return react.TreeNodeId
local function button(kind, icon, tooltip)
	local state = react.useState(catchment.get())
	react.onEvent(EVENT, function(_e, s) state:set(s) end)
	return builtin.BoxLayout{ children = { toggle(kind, icon, tooltip, state:old()[kind]) } }
end

--- Plugin recipe bodies of the mod button area (catchment_buttons.res.lua): the white symbols of
-- the layer buttons next to them (layer_infrastructure.tl's areas).
---@return react.TreeNodeId
function catchment.person_button()
	return button("person", "::/gui/layers/icons/symbol_person.tga",
		_("Show the passenger catchment areas of all stations"))
end

---@return react.TreeNodeId
function catchment.cargo_button()
	return button("cargo", "::/gui/layers/icons/symbol_cargo.tga", _("Show the cargo catchment areas of all stations"))
end

--- Called by installer.lua before the UI starts.
---@param _replacement_api react.ReplacementApi
function catchment.install(_replacement_api)
	if type(selector_react_util.makeDefaultSelectorCombinedFn) ~= "function" then
		error("makeDefaultSelectorCombinedFn not found")
	end
	priority.chain(selector_react_util, "makeDefaultSelectorCombinedFn", wrap_combined_fn)
	debugPrint("[ui_overhaul] catchment overlay installed")
end

return catchment
