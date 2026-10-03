--- Runs functions a few frames later, driven by the entry point's per-frame step (entry.lua). For
-- UI events whose target window mounts only after the event that opens it. GUI thread.
-- @module ui_overhaul.gui.defer
local defer = {}

local queue = {}

--- Calls `fn` after `frames` steps.
function defer.after(frames, fn)
	queue[#queue + 1] = { frames = frames, fn = fn }
end

--- Called every step by the entry point.
function defer.step()
	if #queue == 0 then return end
	local due, waiting = {}, {}
	for _i, item in ipairs(queue) do
		item.frames = item.frames - 1
		if item.frames <= 0 then due[#due + 1] = item.fn else waiting[#waiting + 1] = item end
	end
	queue = waiting
	for _i, fn in ipairs(due) do
		local ok, err = pcall(fn)
		if not ok then debugPrint("[ui_overhaul] deferred call failed: ", tostring(err)) end
	end
end

return defer
