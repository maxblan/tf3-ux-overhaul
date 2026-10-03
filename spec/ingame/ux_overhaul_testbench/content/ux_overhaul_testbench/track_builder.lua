--- Build commands for test tracks. They are sent player-initiated, so the mod under test reacts
-- to them like to the player's own builds.
-- @module ux_overhaul_testbench.track_builder
local track_builder = {}

local TRACK_TEMPLATE = "::/infrastructure/track/standard/standard.street_template"
local TRACK = 1 -- SegmentAndEntity.type

local function vec3(x, y, z)
	return api.type.Vec3f.new(x, y, z)
end

--- A new, empty build command.
function track_builder.new()
	local build = { proposal = api.type.SimpleProposal.new(), nodes = {}, edges = {}, to_remove = {}, next_id = -1 }

	function build.id()
		local id = build.next_id
		build.next_id = build.next_id - 1
		return id
	end

	--- Adds a node; returns its (negative) entity id and position.
	function build.node(x, y, z)
		local node = api.type.NodeAndEntity.new()
		node.entity = build.id()
		node.comp.position = vec3(x, y, z)
		build.nodes[#build.nodes + 1] = node
		return node.entity, node.comp.position
	end

	--- Adds a track edge; straight unless tangents are given (tangent length = edge length).
	function build.edge(node0, p0, node1, p1, edge_type, type_index, tangent0, tangent1)
		local template = api.res.streetTemplateRep.get(api.res.streetTemplateRep.find(TRACK_TEMPLATE))
		local chord = vec3(p1.x - p0.x, p1.y - p0.y, p1.z - p0.z)
		local segment = api.type.SegmentAndEntity.new()
		segment.entity = build.id()
		segment.type = TRACK
		segment.comp.node0, segment.comp.node1 = node0, node1
		segment.comp.position0, segment.comp.position1 = p0, p1
		segment.comp.tangent0, segment.comp.tangent1 = tangent0 or chord, tangent1 or chord
		segment.comp.type = edge_type or api.type["enum"].BaseEdgeType.NORMAL
		segment.comp.typeIndex = type_index or 0
		segment.comp.laneConfigs = template.laneConfigs
		segment.comp.roadTemplate = TRACK_TEMPLATE
		segment.comp.roadStyle = template.streetStyle
		segment.comp.roadType = api.type["enum"].RoadType.TRACK
		build.edges[#build.edges + 1] = segment
	end

	function build.send()
		-- List fields of engine objects are copies: always assign whole lists.
		build.proposal.streetProposal.nodesToAdd = build.nodes
		build.proposal.streetProposal.edgesToAdd = build.edges
		build.proposal.streetProposal.edgesToRemove = build.to_remove
		local context = api.type.Context.new()
		context.player = api.engine.util.getPlayer()
		-- Game scripts may not pass a callback; rejected proposals show up in the game log as
		-- "ProposalData error".
		api.cmd.sendCommand(api.cmd.makeWorldBuildProposalCmd(build.proposal, context, false, true))
	end

	return build
end

--- Adds a straight track along +x at lateral position y, from x0 to x1, on the terrain at height z.
function track_builder.add_straight_track(build, y, x0, x1, z)
	local start, start_pos = build.node(x0, y, z)
	local finish, finish_pos = build.node(x1, y, z)
	build.edge(start, start_pos, finish, finish_pos)
end

--- Track edges whose both ends lie within `radius` of x, y.
function track_builder.edges_near(x, y, radius)
	local result = {}
	local candidates = api.engine.util.octree.findEntitiesInCircle(api.type.Vec2f.new(x, y), radius,
		api.type.ComponentType.BASE_EDGE)
	for _, edge_entity in ipairs(candidates) do
		local edge = api.engine.getComponent(edge_entity, api.type.ComponentType.BASE_EDGE)
		if edge and edge.roadType == api.type["enum"].RoadType.TRACK then result[#result + 1] = edge_entity end
	end
	return result
end

return track_builder
