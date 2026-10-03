-- Game script registration (TF3 resource file; the engine reads the table returned by data()).
function data()
	return {
		updateScript = {
			fileName = "testbench.script@update",
		},
		handleEventScript = {
			fileName = "testbench.script@handleEvent",
		},
		guiUpdateScript = {
			fileName = "testbench.script@guiUpdate",
		},
	}
end
