-- Phase 0 spike stylesheet: hides a probe text, which the testbench checks to prove that mod
-- stylesheets load.
local ssu = require("::/gui/main/stylesheetutil.lua")

function data()
	local result = {}
	local add = ssu.makeAdder(result)
	add("TextView!uxo-spike-css-probe", {
		visibility = "none",
	})
	return result
end
