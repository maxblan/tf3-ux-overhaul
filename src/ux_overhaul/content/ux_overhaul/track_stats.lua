--- Example module: pure logic that is easy to spec.
-- @module ux_overhaul.track_stats
local track_stats = {}

local TRACK = 1 -- SegmentAndEntity.type: 0 = street, 1 = track

--- Number of track edges and tunnel edges among the segments a build added.
function track_stats.count(added_segments)
	local tracks, tunnels = 0, 0
	for _, segment in ipairs(added_segments) do
		if segment.type == TRACK then
			tracks = tracks + 1
			if segment.comp.type == api.type["enum"].BaseEdgeType.TUNNEL then tunnels = tunnels + 1 end
		end
	end
	return tracks, tunnels
end

return track_stats
