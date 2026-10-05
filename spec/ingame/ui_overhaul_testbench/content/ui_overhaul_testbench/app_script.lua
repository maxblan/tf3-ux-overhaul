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
-- The fixture's extra mods come after this mod, or before it with fixture.mods_first (to check that
-- the activation order decides which mod wins).
local MODS = { "urbangames_no_costs_1" }
if fixture.mods_first then
	for _i, name in ipairs(fixture.mods or {}) do MODS[#MODS + 1] = name end
end
if not fixture.vanilla then MODS[#MODS + 1] = "ui_overhaul_1" end
MODS[#MODS + 1] = "ui_overhaul_testbench_1"
if not fixture.mods_first then
	for _i, name in ipairs(fixture.mods or {}) do MODS[#MODS + 1] = name end
end

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
	for _, mod in ipairs(details.mods) do
		-- the gallery shows this mod alone: of the savegame's mods only the game's own content stays
		local keep = not fixture.gallery or mod.name:sub(1, #"urbangames_") == "urbangames_"
		if fixture.vanilla and mod.name == "ui_overhaul_1" then keep = false end
		if keep then
			mods[#mods + 1], names[#names + 1] = mod, mod.name
			listed[mod.name] = true
		end
	end
	local added = {} ---@type string[]
	if fixture.mods_first then
		for _i, name in ipairs(fixture.mods or {}) do added[#added + 1] = name end
	end
	if not fixture.vanilla then added[#added + 1] = "ui_overhaul_1" end
	added[#added + 1] = "ui_overhaul_testbench_1"
	if not fixture.mods_first then
		for _i, name in ipairs(fixture.mods or {}) do added[#added + 1] = name end
	end
	-- A savegame made with the mod already lists it; a mod listed twice registers its resources
	-- twice and the game crashes while loading (ResTypeRep::Add assertion, observed in-game).
	for _, name in ipairs(added) do
		if not listed[name] then
			local mod = api.type.ModId.new()
			mod.name = name
			mods[#mods + 1], names[#names + 1] = mod, name
			listed[name] = true
		end
	end
	details.mods = mods
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
