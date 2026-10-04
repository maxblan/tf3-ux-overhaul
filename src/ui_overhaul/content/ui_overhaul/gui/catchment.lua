--- Catchment areas that stay on the map: two toggle buttons in the mod button area of the game bar,
-- one for the passenger and one for the cargo catchment areas of all stations, each switched on and
-- off separately. While one is on, the map shows those areas whenever no tool and no entity window
-- draws its own overlay (the station window, a layer, construction show theirs as before), and the
-- choice is saved with the game.
-- The areas are the game's own catchment overlay (LayerConfig.catchmentAreaRenderableConfig, as the
-- Infrastructure layer draws it). The default map action is built by the module function
-- selector_react_util.makeDefaultSelectorCombinedFn, which the window manager calls through the module
-- table; it is wrapped so its ActionDescriptor gets one more LayerConfig. Toggles: a plugin of
-- ::MainModButtonAreaExtension (catchment_buttons.res.lua). Installed by catchment.script.lua.
-- @module ui_overhaul.gui.catchment
local builtin = require("::/gui/main/builtin.lua")
local react = require("::/gui/main/react.lua")
local selector_react_util = require("::/gui/main/selector_react_util.tl")

local catchment = {}

local SAVE_KEY = "ui_overhaul_catchment"
local EVENT = "uio.catchment"

-- { person = bool, cargo = bool }; read from the savegame on first use
local shown

local reported = {}
local function report(key, err)
	if reported[key] then return end
	reported[key] = true
	debugPrint("[ui_overhaul] catchment: ", key, ": ", tostring(err))
end

--- The current choice (GUI thread).
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
function catchment.layer_config(s)
	local config = api.type.LayerConfig.new()
	local area = api.type.LayerConfig.CatchmentAreaRenderableConfig.new()
	local display = api.type.LayerConfig.CatchmentAreaDisplaySettings.new()
	-- a light fill, so what lies under the areas stays readable (Infrastructure layer: 0.4)
	display.innerAlpha = 0.12
	display.borderAlpha = 0.9
	display.godrayAlpha = 0.0
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
local function with_overlay(inner, s)
	local base = builtin.ActionDescriptor
	builtin.ActionDescriptor = function(p, ...)
		if select("#", ...) == 0 and type(p) == "table" then
			local ok, config = pcall(catchment.layer_config, s)
			if ok then
				local copy = {}
				for k, v in pairs(p) do copy[k] = v end
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

local function toggle(kind, icon, tooltip, value)
	return builtin.ToggleButton{
		meta = { tooltip = tooltip, class = "uio-catchment-toggle", id = "uio.catchment." .. kind },
		content = builtin.ImageView{ meta = { class = "uio-catchment-icon" }, path = icon,
			scaling = builtin.type.ImageViewScaling.AutoFit },
		value = value and 1 or 0,
		onValueChange = function(v) catchment.set(kind, v == 1) end,
	}
end

--- Plugin recipe body of the mod button area.
function catchment.buttons()
	local state = react.useState(catchment.get())
	react.onEvent(EVENT, function(_e, s) state:set(s) end)
	local s = state:old()
	return builtin.BoxLayout{
		meta = { class = "uio-catchment-buttons" },
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			-- the white symbols of the layer buttons next to them (layer_infrastructure.tl's areas)
			toggle("person", "::/gui/layers/icons/symbol_person.tga",
				_("Show the passenger catchment areas of all stations"), s.person),
			toggle("cargo", "::/gui/layers/icons/symbol_cargo.tga",
				_("Show the cargo catchment areas of all stations"), s.cargo),
		},
	}
end

--- Called from the react-replacement-config before the UI starts.
function catchment.install(_replacement_api)
	local original = selector_react_util.makeDefaultSelectorCombinedFn
	if type(original) ~= "function" then error("makeDefaultSelectorCombinedFn not found") end
	selector_react_util.makeDefaultSelectorCombinedFn = wrap_combined_fn(original)
	debugPrint("[ui_overhaul] catchment overlay installed")
end

return catchment
