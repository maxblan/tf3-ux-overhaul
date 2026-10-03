--- Testbench game script (development only).
--
-- On game start, unpauses the simulation, finds flat land and runs every scenario of
-- scenarios.lua in turn: build, wait, check, log "[testbench] PASS|FAIL <name> <details>".
-- Ends with "[testbench] DONE". Progress lives in the game script state, because the engine runs
-- game scripts in changing Lua states. spec/ingame/run.sh collects the "[testbench]" lines.
-- @module ux_overhaul_testbench.testbench
local scenarios = require("/ux_overhaul_testbench/scenarios.lua")
local site = require("/ux_overhaul_testbench/site.lua")

local testbench = {}

local TAG = "[testbench]"
local WAIT_START = 60 -- update() calls before the first scenario, 0.2 s game time each

local function log(...)
	local parts = { TAG }
	for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
	debugPrint(table.concat(parts, " "))
end

local function finish(run)
	log("DONE")
	run.phase = "done"
end

local function setup(run)
	run.site = site.find(#scenarios)
	if not run.site then
		log("ERROR no flat site found")
		return finish(run)
	end
	log(string.format("START scenarios=%d site=(%.0f,%.0f) flatness=%.1fm", #scenarios, run.site.x, run.site.y,
		run.site.range))
	run.phase, run.frames = "next", 0
end

local function start_scenario(run)
	run.index = run.index + 1
	local scenario = scenarios[run.index]
	if not scenario then return finish(run) end
	log("SCENARIO", scenario.name)
	scenario.build(site.area(run.site, run.index))
	run.phase, run.frames = "built", 0
end

local function check_scenario(run)
	local scenario = scenarios[run.index]
	local ok, passed, details = pcall(scenario.check, site.area(run.site, run.index))
	if not ok then passed, details = false, "check failed: " .. tostring(passed) end
	log(passed and "PASS" or "FAIL", scenario.name, details or "")
	run.phase, run.frames = "next", 0
end

local function step(run)
	run.frames = run.frames + 1
	if run.phase == "wait" and run.frames >= WAIT_START then
		setup(run)
	elseif run.phase == "next" then
		start_scenario(run)
	elseif run.phase == "built" and run.frames >= (scenarios[run.index].wait or 30) then
		check_scenario(run)
	end
end

function testbench.update(_user_params, state, _dt)
	local run = state:get() or {}
	if not run.phase then
		run.phase, run.frames, run.index = "wait", 0, 0
		log("update running")
	end
	if run.phase == "done" then return end

	local ok, err = pcall(step, run)
	if not ok then
		log("ERROR", err)
		finish(run)
	end
	state:set(run)
end

function testbench.handleEvent()
end

--- A new game starts paused, and update() only runs while the simulation runs.
function testbench.guiUpdate(_user_params, _state, gui_state)
	local g = gui_state:get() or {}
	if g.unpaused then return end
	api.cmd.sendCommand(api.cmd.makeGameSetSpeedCmd(1))
	g.unpaused = true
	gui_state:set(g)
	log("gui: unpaused the simulation")
end

-- The engine loads resource files (unlike modules loaded with require) by calling the global
-- data(); see base/init.lua.
function data()
	return testbench
end
