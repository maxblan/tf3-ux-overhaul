--- Example game script: logs how many track edges every completed build added and keeps a
-- running total in the game script state (module-level variables do not survive between calls).
-- @module ux_overhaul.main
local logger = require("/ux_overhaul/logger.lua")
local track_stats = require("/ux_overhaul/track_stats.lua")

local main = {}

local SUBSCRIPTIONS_VERSION = 1

function main.update(_user_params, state, _dt)
	local s = state:get() or {}
	-- Savegames from older versions of the mod may hold older subscriptions.
	if s.subscriptions ~= SUBSCRIPTIONS_VERSION then
		state:subscribeToEvent("onPostBuildProposal")
		s.subscriptions = SUBSCRIPTIONS_VERSION
		state:set(s)
	end
end

function main.handleEvent(_user_params, state, _src, id, name, param)
	if id ~= "apply_command" or name ~= "onPostBuildProposal" then return end
	local street_proposal = param[1] and param[1].proposal
	if not street_proposal then return end

	local tracks, tunnels = track_stats.count(street_proposal.addedSegments)
	if tracks == 0 then return end
	local s = state:get() or {}
	s.total_tracks = (s.total_tracks or 0) + tracks
	state:set(s)
	logger.info(string.format("built %d track edges (%d tunnel), %d in total", tracks, tunnels, s.total_tracks))
end

-- The engine loads resource files (unlike modules loaded with require) by calling the global
-- data(); see base/init.lua.
function data()
	return main
end
