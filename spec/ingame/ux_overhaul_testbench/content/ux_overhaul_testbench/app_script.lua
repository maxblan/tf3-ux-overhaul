--- App script, started with
--   TransportFever3.exe --script ux_overhaul_testbench_1::/ux_overhaul_testbench/app_script.lua
-- (see spec/ingame/run.sh; --script takes a game resource path, not a file path).
-- From the main menu, starts a small test game with the mod and the testbench enabled. The engine
-- calls update() every frame.
-- @module ux_overhaul_testbench.app_script
local app_script = {}

local TAG = "[testbench]"
-- urbangames_no_costs: a new game starts without money, so builds would fail.
local MODS = { "urbangames_no_costs_1", "ux_overhaul_1", "ux_overhaul_testbench_1" }
local START_AFTER_FRAMES = 120

local frames, started = 0, false

local function log(...)
	local parts = { TAG, "app:" }
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
	params.seed = "ux-overhaul"
	params.generateTowns = true
	params.generateIndustries = false
	params.generateAssets = false
	app.startGame(params)
end

function app_script.update()
	frames = frames + 1
	if frames == 1 then log("loaded") end
	if started or frames < START_AFTER_FRAMES then return end
	started = true
	log("starting test game with mods", table.concat(MODS, ", "))
	local ok, err = pcall(start_test_game)
	if not ok then log("ERROR startGame failed:", err) end
end

function app_script.handleEvent()
end

-- The engine loads resource files (unlike modules loaded with require) by calling the global
-- data(); see base/init.lua.
function data()
	return app_script
end
