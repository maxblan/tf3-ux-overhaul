--- Shared snapshot for all of the mod's widgets. The always-mounted entry point refreshes it on a
-- timer (store.REFRESH_SECONDS, see gui/control_center.lua); every widget only reads the cached
-- result. Lives in the GUI's React Lua state, which keeps module state for the whole session.
--
-- Observed in-game: calling api.util.getApplicationTime() ("GUI thread only") inside a
-- useStepStateTimer / onStepTimer callback crashes the game natively. Nothing on this path may
-- call GUI-thread-only APIs, including translation: the snapshot holds untranslated text.
-- @module ux_overhaul.engine.store
local snapshot = require("/ux_overhaul/engine/snapshot.lua")
local health = require("/ux_overhaul/core/health.lua")

local store = {}

store.REFRESH_SECONDS = 2.0

snapshot.trace = 0 -- set > 0 to trace the engine calls of the next snapshots (see snapshot.trace)

local current = { revision = 0 }

local function clock()
	return type(os) == "table" and os.clock and os.clock() or nil
end

--- Takes a new snapshot. Called by the entry point's timer and after the player acted.
function store.refresh()
	local started = clock()
	local ok, result = pcall(snapshot.take)
	if not ok then
		debugPrint("[ux_overhaul] snapshot failed: ", tostring(result))
		return
	end
	current.data = result
	current.summary = health.summarize(result)
	current.problems = health.problems(result)
	current.revision = current.revision + 1
	if current.revision == 1 then
		local seconds = started and clock() and clock() - started
		debugPrint(string.format("[ux_overhaul] first snapshot: %d lines, %d vehicles%s", #result.lines,
			#result.vehicles, seconds and string.format(", %.1f ms cpu", seconds * 1000) or ""))
	end
end

--- The current { data, summary, problems, revision }; takes the first snapshot on first use.
function store.get()
	if current.revision == 0 then store.refresh() end
	return current
end

--- Refreshes now, after an action changed the network (e.g. a vehicle was bought).
function store.invalidate()
	store.refresh()
end

return store
