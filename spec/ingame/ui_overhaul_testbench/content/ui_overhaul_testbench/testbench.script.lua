--- Testbench game script (development only).
--
-- On game start, unpauses the simulation, finds flat land and runs every scenario of
-- scenarios.lua in turn: build, wait, check, log "[testbench] PASS|FAIL <name> <details>".
-- In parallel, guiUpdate runs the GUI checks of gui_checks.lua the same way. Ends with
-- "[testbench] DONE" once both are finished. Progress lives in the game script state, because the
-- engine runs game scripts in changing Lua states. spec/ingame/run.sh collects the "[testbench]" lines.
-- @module ui_overhaul_testbench.testbench
local scenarios = require("/ui_overhaul_testbench/scenarios.lua")
local gui_checks = require("/ui_overhaul_testbench/gui_checks.lua")
local site = require("/ui_overhaul_testbench/site.lua")

local testbench = {}

local TAG = "[testbench]"
local WAIT_START = 60 -- update() calls before the first scenario, 0.2 s game time each

---@param ... any logged with tostring
local function log(...)
	local parts = { TAG } ---@type string[]
	for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
	debugPrint(table.concat(parts, " "))
end

--- The engine side's progress, in the game script state.
---@class uo.testbench.Run
---@field phase? "wait"|"next"|"built"|"done"
---@field frames integer update() calls in this phase
---@field index integer the current scenario
---@field site? uo.testbench.Site

-- The engine side only marks itself done; guiUpdate logs DONE when the GUI checks are finished too.
---@param run uo.testbench.Run
local function finish(run)
	log("engine scenarios finished")
	run.phase = "done"
end

---@param run uo.testbench.Run
---@return nil
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

---@param run uo.testbench.Run
---@return nil
local function start_scenario(run)
	run.index = run.index + 1
	local scenario = scenarios[run.index]
	if not scenario then return finish(run) end
	log("SCENARIO", scenario.name)
	scenario.build(site.area(run.site, run.index))
	run.phase, run.frames = "built", 0
end

---@param run uo.testbench.Run
local function check_scenario(run)
	local scenario = scenarios[run.index]
	local ok, passed, details = pcall(scenario.check, site.area(run.site, run.index))
	if not ok then passed, details = false, "check failed: " .. tostring(passed) end
	log(passed and "PASS" or "FAIL", scenario.name, details or "")
	run.phase, run.frames = "next", 0
end

---@param run uo.testbench.Run
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

---@param _user_params table
---@param state GameScriptState<uo.testbench.Run>
---@param _dt number
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

--- The GUI side's progress, in the GUI state.
---@class uo.testbench.GuiRun
---@field unpaused? boolean
---@field phase "next"|"acted"|"shot_wait"|"finished"|"done"
---@field frames integer guiUpdate calls in this phase
---@field index integer the current check
---@field ctx uo.testbench.GuiContext

---@param g uo.testbench.GuiRun
---@param engine_done boolean
local function gui_step(g, engine_done)
	g.frames = g.frames + 1
	local check = gui_checks[g.index]
	if g.phase == "next" then
		g.index = g.index + 1
		check = gui_checks[g.index]
		if not check then
			g.phase = "finished"
			return
		end
		log("GUI CHECK", check.name)
		if check.act then check.act(g.ctx) end
		g.phase, g.frames = "acted", 0
	elseif g.phase == "acted" and g.frames >= (check.wait or 10) then
		local ok, passed, details = pcall(check.check, g.ctx)
		if not ok then passed, details = false, "check failed: " .. tostring(passed) end
		log(passed and "PASS" or "FAIL", check.name, details or "")
		g.phase, g.frames = "next", 0
		if check.shot then
			-- spec/ingame/run.sh captures the screen when it sees this line; hold still meanwhile.
			log("SHOT", check.shot)
			g.phase = "shot_wait"
		end
	elseif g.phase == "shot_wait" and g.frames >= 400 then
		g.phase, g.frames = "next", 0
	elseif g.phase == "finished" and engine_done then
		log("DONE")
		g.phase = "done"
	end
end

--- A new game starts paused, and update() only runs while the simulation runs. Afterwards runs the
-- GUI checks; the engine state is read-only here.
---@param _user_params table
---@param read_only_state GameScriptStateReadOnly<uo.testbench.Run>
---@param gui_state GameScriptState<uo.testbench.GuiRun>
function testbench.guiUpdate(_user_params, read_only_state, gui_state)
	local g = gui_state:get() or {}
	if not g.unpaused then
		api.cmd.sendCommand(api.cmd.makeGameSetSpeedCmd(1))
		g.unpaused, g.phase, g.frames, g.index, g.ctx = true, "next", 0, 0, {}
		log("gui: unpaused the simulation")
	elseif g.phase ~= "done" then
		local run = read_only_state:get() or {}
		local ok, err = pcall(gui_step, g, run.phase == "done")
		if not ok then
			log("ERROR gui", err)
			g.phase = "finished"
		end
	end
	gui_state:set(g)
end

-- The engine loads resource files (unlike modules loaded with require) by calling the global
-- data(); see base/init.lua.
---@return table
function data()
	return testbench
end
