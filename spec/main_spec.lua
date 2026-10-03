local mock_engine = require("mock_engine")

describe("main game script", function()
	local world, game

	before_each(function()
		world = mock_engine.new()
		game = mock_engine.new_game(world, mock_engine.load_resource("/ux_overhaul/main.script.lua"))
		game.frame() -- the first update subscribes to events
	end)

	it("subscribes to completed builds", function()
		assert.truthy(game.state.subscriptions.onPostBuildProposal)
	end)

	it("logs the track edges of every build and keeps a running total", function()
		game.player_built(world.straight_track(0, 0, 100, 3))
		game.player_built(world.straight_track(10, 0, 100, 2, mock_engine.TUNNEL))

		assert.are.equal("[ux_overhaul] built 3 track edges (0 tunnel), 3 in total", world.log[1])
		assert.are.equal("[ux_overhaul] built 2 track edges (2 tunnel), 5 in total", world.log[2])
		assert.are.equal(5, game.state:get().total_tracks)
	end)
end)
