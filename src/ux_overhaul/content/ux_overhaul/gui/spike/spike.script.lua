--- Phase 0 spike: one minimal recipe per GUI hook the mod relies on. The in-game testbench checks
-- each one by its meta id (see spec/ingame/.../gui_checks.lua). Throw-away code; the real
-- features replace it.
-- @module ux_overhaul.gui.spike
local react = require("::/gui/main/react.lua")
local builtin = require("::/gui/main/builtin.lua")
local engine_react_util = require("::/gui/main/engine_react_util.tl")
local game_react_globals = require("::/gui/main/game_react_globals.tl")
local mod_entry_point = require("::/gui/main/mod_entry_point.tl")
local main_mod_button_area = require("::/gui/main/main_mod_button_area.tl")
local game_bar_widgets = require("::/gui/game_bar/game_bar_widgets.tl")
local earnings_plugin = require("::/gui/game_bar/game_bar_display_earnings_plugin/game_bar_display_earnings.script.tl")
local town_eow = require("::/gui/entity_window/town/town_eow.script.tl")
local station_group_eow = require("::/gui/entity_window/station_group/station_group_eow.script.tl")

local spike = {}

local TAG = "[ux_overhaul]"
local logged = {}

-- Logs a line once per Lua state, so recipes that re-render don't flood the log.
local function log_once(key, ...)
	if logged[key] then return end
	logged[key] = true
	debugPrint(TAG, "spike", key, ...)
end

-- Every recipe must return a layout as its root: a Component, TextView or Button root aborts the
-- whole game UI ("Recipe child must be a layout", observed in-game).
local function box(children, meta)
	return builtin.BoxLayout{ meta = meta, orientation = builtin.type.Orientation.Horizontal, children = children }
end

local function player_line_count()
	return #api.engine.system.lineSystem.getLinesForPlayer(api.engine.util.getPlayer())
end

-- 1. Game bar: a status chip with a live engine value.
spike.UxoSpikeStatus = react.RegisterPluginRecipe(game_bar_widgets.GameBarInfoDisplayExtension, "UxoSpikeStatus",
	function()
		local lines = engine_react_util.useStepStateTimer(player_line_count)
		log_once("status", "lines=" .. tostring(lines:old()))
		return box{
			builtin.Component{
				meta = { id = "uxo.spike.status", class = "uxo-spike-chip", tooltip = "UX Overhaul spike" },
				layout = box{
					builtin.TextView{ meta = { class = "font-scale-headline" }, text = "UXO lines: " .. tostring(lines:old()) },
					-- Hidden by spike.css.lua; visible means the mod's stylesheet did not load.
					builtin.TextView{ meta = { id = "uxo.spike.css_probe", class = "uxo-spike-css-probe" }, text = "CSS?" },
				},
			},
		}
	end)

-- 2. Our own window, opened through the event "uxo.spike.open".
local SpikeWindow
SpikeWindow = react.RegisterWrapperRecipe("UxoSpikeWindow", builtin.Window, function(params)
	log_once("window")
	return builtin.Window{
		id = "uxo.spike.window",
		title = "UX Overhaul",
		closable = true,
		onClose = function()
			game_react_globals.getDefaultWindowApi().removeAllWindows(SpikeWindow)
		end,
		content = box{ builtin.TextView{ meta = { id = "uxo.spike.window.text" }, text = params.text } },
	}
end)

local function open_window()
	local windows = game_react_globals.getDefaultWindowApi()
	windows.addSingletonWindow(SpikeWindow, { text = "Spike window, lines: " .. player_line_count() })
	api.gui.byId.setVisible("uxo.spike.window", true)
end

-- 3. Headless entry point: owns the mod's events.
spike.UxoSpikeEntry = react.RegisterPluginRecipe(mod_entry_point.ModEntryPointExtension, "UxoSpikeEntry", function()
	log_once("entry")
	react.onEvent("uxo.spike.open", function()
		log_once("open_event")
		open_window()
	end)
	return box{}
end)

-- 4. Launcher button next to the layer buttons.
spike.UxoSpikeLauncher = react.RegisterPluginRecipe(main_mod_button_area.MainModButtonAreaExtension,
	"UxoSpikeLauncher", function()
		log_once("launcher")
		return box{
			builtin.Button{
				meta = { id = "uxo.spike.launcher", tooltip = "UX Overhaul" },
				content = builtin.TextView{ text = "UXO" },
				onClick = function() react.fireEvent(nil, "uxo.spike.open") end,
			},
		}
	end)

-- 5. Entity-window cards: town (has base plugins) and station (empty in the base game).
spike.UxoSpikeTownCard = react.RegisterPluginRecipe(town_eow.TownEowExtensionPoint, "UxoSpikeTownCard",
	function(params)
		log_once("town_card", "entity=" .. tostring(params.entityId))
		local text = "UXO town card " .. tostring(params.entityId)
		return box{ builtin.TextView{ meta = { id = "uxo.spike.town" }, text = text } }
	end)

spike.UxoSpikeStationCard = react.RegisterPluginRecipe(station_group_eow.StationGroupEowExtensionPoint,
	"UxoSpikeStationCard", function(params)
		log_once("station_card", "entity=" .. tostring(params.entityId))
		local text = "UXO station card " .. tostring(params.entityId)
		return box{ builtin.TextView{ meta = { id = "uxo.spike.station" }, text = text } }
	end)

-- 6. Wrapping replacement of an exported base recipe (the game bar's earnings display).
local EarningsReplacement = react.RegisterRecipe("GameBarEarningsPlugin", function(...)
	log_once("replacement")
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			react.CallOriginalRecipe(earnings_plugin.GameBarEarningsPlugin, ...),
			builtin.TextView{ meta = { id = "uxo.spike.replaced" }, text = "*" },
		},
	}
end)

function spike.doReplaceFn(replacement_api)
	log_once("doReplaceFn")
	replacement_api.ReplaceRecipe(earnings_plugin.GameBarEarningsPlugin, EarningsReplacement)
end

-- The engine loads *.script.lua resources by calling data(); see base/init.lua.
function data()
	return spike
end

return spike
