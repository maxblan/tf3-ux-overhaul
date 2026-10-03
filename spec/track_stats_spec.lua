local mock_engine = require("mock_engine")

describe("track_stats", function()
	local track_stats

	before_each(function()
		mock_engine.new() -- installs the engine API used by the module
		track_stats = require("/ux_overhaul/track_stats.lua")
	end)

	local function segment(segment_type, edge_type)
		return { type = segment_type, comp = { type = edge_type } }
	end

	it("counts track edges and the tunnels among them", function()
		local tracks, tunnels = track_stats.count({
			segment(1, mock_engine.NORMAL),
			segment(1, mock_engine.TUNNEL),
			segment(0, mock_engine.NORMAL), -- street
		})
		assert.are.equal(2, tracks)
		assert.are.equal(1, tunnels)
	end)

	it("returns zero for builds without tracks", function()
		local tracks, tunnels = track_stats.count({})
		assert.are.equal(0, tracks)
		assert.are.equal(0, tunnels)
	end)
end)
