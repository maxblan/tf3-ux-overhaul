--- In-game GUI checks, run in order by testbench.script.lua on the GUI thread (guiUpdate).
--
-- Each check has:
--   name           unique name, shown in the PASS/FAIL line
--   act(ctx)       optional; drives the GUI (fires react events, selects entities ...)
--   wait           guiUpdate calls (about one per frame) between act and check
--   check(ctx)     returns passed (boolean) and a details string
--
-- `ctx` is a plain table kept in the GUI state; checks may store values in it (serialisable only).
-- @module ux_overhaul_testbench.gui_checks

local function visible(id)
	return api.gui.byId.isVisibleRecursive(id)
end

local function first_town()
	local towns = api.engine.getEntitiesWithComponent(api.type.ComponentType.TOWN)
	return towns[1], #towns
end

return {
	{
		name = "gui_fixture_facts",
		wait = 60,
		check = function()
			local player = api.engine.util.getPlayer()
			local lines = api.engine.system.lineSystem.getLinesForPlayer(player)
			local vehicles = api.engine.getEntitiesWithComponent(api.type.ComponentType.TRANSPORT_VEHICLE)
			local towns = api.engine.getEntitiesWithComponent(api.type.ComponentType.TOWN)
			return true, string.format("lines=%d vehicles=%d towns=%d", #lines, #vehicles, #towns)
		end,
	},
	{
		name = "gui_gamebar_plugin",
		check = function()
			return visible("uxo.spike.status"), "status chip visible=" .. tostring(visible("uxo.spike.status"))
		end,
	},
	{
		name = "gui_stylesheet",
		check = function()
			-- spike.css.lua hides the probe; its sibling text stays visible.
			local probe = api.gui.byId.isVisible("uxo.spike.css_probe")
			return not probe and visible("uxo.spike.status"), "css probe visible=" .. tostring(probe)
		end,
	},
	{
		name = "gui_mod_button_plugin",
		check = function()
			local shown = api.gui.byId.isVisible("uxo.spike.launcher")
			return shown, "launcher visible=" .. tostring(shown) .. " recursive=" .. tostring(visible("uxo.spike.launcher"))
		end,
	},
	{
		name = "gui_recipe_replacement",
		check = function()
			return visible("uxo.spike.replaced"), "replaced earnings marker visible=" .. tostring(visible("uxo.spike.replaced"))
		end,
	},
	{
		name = "gui_entry_point_window",
		act = function() api.gui.fireReactEvent("uxo.spike.open", nil) end,
		wait = 60,
		check = function()
			return visible("uxo.spike.window"), "window visible=" .. tostring(visible("uxo.spike.window"))
		end,
	},
	{
		name = "gui_town_window_card",
		act = function(ctx)
			local town, count = first_town()
			ctx.town, ctx.town_count = town, count
			if town then api.gui.fireReactEvent("selectEntity", { entity = town, stack = true }) end
		end,
		wait = 90,
		check = function(ctx)
			if not ctx.town then return false, "no town on the map" end
			return visible("uxo.spike.town"), string.format("town=%d of %d, card visible=%s", ctx.town, ctx.town_count,
				tostring(visible("uxo.spike.town")))
		end,
	},
	{
		name = "gui_save_data_roundtrip",
		act = function() api.gui.game.setGuiSaveData("ux_overhaul_1", { probe = 42, nested = { "a" } }) end,
		wait = 5,
		check = function()
			local data = api.gui.game.getGuiSaveData("ux_overhaul_1") or {}
			return data.probe == 42, "probe=" .. tostring(data.probe)
		end,
	},
}
