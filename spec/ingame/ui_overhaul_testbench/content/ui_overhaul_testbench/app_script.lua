--- App script, started with
--   TransportFever3.exe --script ui_overhaul_testbench_1::/ui_overhaul_testbench/app_script.lua
-- (see spec/ingame/run.sh; --script takes a game resource path, not a file path).
-- From the main menu, starts a small test game with the mod and the testbench enabled, or loads the
-- savegame copy named in fixture.lua with both mods added; the fixture's extra mods are added either
-- way. The engine calls update() every frame.
-- @module ui_overhaul_testbench.app_script
local app_script = {}

local TAG = "[testbench]"
-- urbangames_no_costs: a new game starts without money, so builds would fail.
local START_AFTER_FRAMES = 120

local fixture = require("/ui_overhaul_testbench/fixture.lua")

--- This mod (unless vanilla), the testbench and the fixture's extra mods, in activation order: the
-- extra mods after this mod, or before it with fixture.mods_first (to check that the activation order
-- decides which mod wins).
---@return string[]
local function ordered_mods()
	local list = {} ---@type string[]
	if fixture.mods_first then
		for _i, name in ipairs(fixture.mods or {}) do list[#list + 1] = name end
	end
	if not fixture.vanilla then list[#list + 1] = "ui_overhaul_1" end
	list[#list + 1] = "ui_overhaul_testbench_1"
	if not fixture.mods_first then
		for _i, name in ipairs(fixture.mods or {}) do list[#list + 1] = name end
	end
	return list
end

-- The value of "Off" in a feature's param, as the game takes it in modParams: 1-based, as
-- getModParams hands it over (observed in game: 2 switched the feature off, 1 left it on).
local OFF_VALUE = 2

--- This mod's params for the features fixture.off names (run.sh --off), each set to "Off".
---@return table<string, integer>
local function own_params()
	local params = {} ---@type table<string, integer>
	for _i, feature in ipairs(fixture.off or {}) do params["uio_" .. feature] = OFF_VALUE end
	return params
end

local MODS = { "urbangames_no_costs_1" }
for _i, name in ipairs(ordered_mods()) do MODS[#MODS + 1] = name end

local frames, started = 0, false
---@class uo.testbench.PendingLoad
---@field id SaveGameId
---@field info Async<SaveGameData>

local pending_load ---@type uo.testbench.PendingLoad? while the savegame metadata loads

---@param ... any logged with tostring
local function log(...)
	local parts = { TAG, "app:" } ---@type string[]
	for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
	debugPrint(table.concat(parts, " "))
end

local function start_test_game()
	local params = api.type.StartGameParams.new()
	params.numTiles = api.type.Vec2i.new(16, 16)
	params.terrainGenerator = "::/climates/temperate/temperate.gen"
	params.climateGenerator = "::/climates/temperate/temperate.clima"
	params.economy = "::/economy/temperate.eco"
	params.mods = MODS
	local own = own_params()
	if next(own) ~= nil then params.modParams = { ui_overhaul_1 = own } end
	params.seed = "ui-overhaul"
	params.generateTowns = true
	params.generateIndustries = false
	params.generateAssets = false
	app.startGame(params)
end

--- Starts reading the metadata (mod list) of the fixture savegame; load_fixture_game() continues.
---@param name string
local function request_fixture(name)
	local namespace = app.SaveGameNamespace.getSavegame()
	for _, info in ipairs(app.findAllSavegames(namespace)) do
		if info.saveName == name then
			local id = api.type.SavegameId.new()
			id.path, id.saveGameName, id.saveGameNamespace = info.path, info.saveName, namespace
			pending_load = { id = id, info = app.getSavegameInfo(id) }
			return
		end
	end
	error("savegame not found: " .. name)
end

--- Loads the fixture savegame with the savegame's own mods plus the mod and the testbench.
local function load_fixture_game()
	local load = assert(pending_load) -- update() calls this only while a load is pending
	local data = load.info:get()
	local details = api.type.SaveGameDetails.new(data.info)
	local mods, names, listed = {}, {}, {} ---@type Mod.ModId[], string[], table<string, true>
	local added = ordered_mods()
	local wanted = {} ---@type table<string, true>
	for _i, name in ipairs(added) do wanted[name] = true end
	-- with mods_first, the savegame's own entries of these mods are listed again below, in that order
	-- (a savegame made with this mod lists it before mods added now)
	local moved = {} ---@type table<string, Mod.ModId>
	local without = {} ---@type table<string, true> the savegame's mods left out (run.sh --without-mod)
	for _i, name in ipairs(fixture.without or {}) do without[name] = true end
	for _, mod in ipairs(details.mods) do
		-- the gallery shows this mod alone: of the savegame's mods only the game's own content stays
		local keep = not fixture.gallery or mod.name:sub(1, #"urbangames_") == "urbangames_"
		if fixture.vanilla and mod.name == "ui_overhaul_1" then keep = false end
		if without[mod.name] then keep = false end
		if keep and fixture.mods_first and wanted[mod.name] then
			moved[mod.name] = mod
		elseif keep then
			mods[#mods + 1], names[#names + 1] = mod, mod.name
			listed[mod.name] = true
		end
	end
	-- A savegame made with the mod already lists it; a mod listed twice registers its resources
	-- twice and the game crashes while loading (ResTypeRep::Add assertion, observed in-game).
	-- the --with-mod mods: added even where the savegame's own entry is left out
	local requested = {} ---@type table<string, true>
	for _i, name in ipairs(fixture.mods or {}) do requested[name] = true end
	for _, name in ipairs(added) do
		-- --without-mod ui_overhaul_1 runs the checks without the mod, to tell the game's own faults; a mod
		-- both left out and added (--without-mod X --with-mod X) moves to the end of the list
		if not listed[name] and not (without[name] and not requested[name]) then
			local mod = moved[name] or api.type.ModId.new()
			mod.name = name
			mods[#mods + 1], names[#names + 1] = mod, name
			listed[name] = true
		end
	end
	details.mods = mods
	local own = own_params()
	if next(own) ~= nil then
		-- the savegame's own params of every mod, with this mod's switches on top
		local params = {} ---@type table<string, table<string, integer>>
		pcall(function()
			for mod, values in pairs(details.modParams) do
				local copy = {} ---@type table<string, integer>
				for key, value in pairs(values) do copy[key] = value end
				params[mod] = copy
			end
		end)
		params.ui_overhaul_1 = params.ui_overhaul_1 or {}
		for key, value in pairs(own) do params.ui_overhaul_1[key] = value end
		details.modParams = params
	end
	log("loading savegame", fixture.save, "with mods", table.concat(names, ", "))
	app.loadGame(load.id, false, details)
end

function app_script.update()
	frames = frames + 1
	if frames == 1 then log("loaded") end
	if pending_load then
		if not pending_load.info:isCompleted() then return end
		local ok, err = pcall(load_fixture_game)
		if not ok then log("ERROR loadGame failed:", err) end
		pending_load = nil
		return
	end
	if started or frames < START_AFTER_FRAMES then return end
	started = true
	local ok, err ---@type boolean, any pcall's error value
	if fixture.save then
		log("reading savegame", fixture.save)
		ok, err = pcall(request_fixture, fixture.save)
	else
		log("starting test game with mods", table.concat(MODS, ", "))
		ok, err = pcall(start_test_game)
	end
	if not ok then log("ERROR starting the game failed:", err) end
end

function app_script.handleEvent()
end

-- The engine loads resource files (unlike modules loaded with require) by calling the global
-- data(); see base/init.lua.
---@return table
function data()
	return app_script
end
