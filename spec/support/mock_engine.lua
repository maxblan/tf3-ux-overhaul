--- Mock of the parts of the Transport Fever 3 engine API used by the mod.
--
-- Holds a small track network (nodes and cubic Hermite edges), applies the build proposals the
-- mod sends and fires the same events the game does. Engine behaviour observed in-game is
-- modelled explicitly (see the "observed" comments), so regressions against it are caught offline.
-- @module mock_engine
local mod_paths = require("mod_paths")

local mock_engine = {}

local NORMAL, BRIDGE, TUNNEL = 0, 1, 2
mock_engine.NORMAL, mock_engine.BRIDGE, mock_engine.TUNNEL = NORMAL, BRIDGE, TUNNEL

local TRACK = 1 -- SegmentAndEntity.type

-- Vec3f with the metamethods the engine provides.
local Vec3 = {}
Vec3.__index = Vec3

local function vec3(x, y, z)
	return setmetatable({ x = x, y = y, z = z or 0 }, Vec3)
end

Vec3.__add = function(a, b) return vec3(a.x + b.x, a.y + b.y, a.z + b.z) end
Vec3.__sub = function(a, b) return vec3(a.x - b.x, a.y - b.y, a.z - b.z) end
Vec3.__mul = function(a, s) return vec3(a.x * s, a.y * s, a.z * s) end
mock_engine.vec3 = vec3

local function copy(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for k, v in pairs(value) do result[k] = copy(v) end
	return setmetatable(result, getmetatable(value))
end
mock_engine.copy = copy

--- Creates a fresh world and installs the globals `api` and `debugPrint`.
function mock_engine.new(options)
	options = options or {}
	local world = {
		nodes = {},
		edges = {},
		next_id = 1000,
		proposals = {},
		applied = {},
		script_events = {},
		active_tools = { "EntityDetailsTool" }, -- observed: the idle game reports the selection tool
		log = {},
	}

	function world.new_id()
		world.next_id = world.next_id + 1
		return world.next_id
	end

	function world.add_node(x, y, z)
		local id = world.new_id()
		world.nodes[id] = { position = vec3(x, y, z) }
		return id
	end

	--- Straight edge unless tangents are given; tangent length = chord length (TF convention).
	function world.add_edge(node0, node1, edge_type, type_index, tangent0, tangent1)
		local p0, p1 = world.nodes[node0].position, world.nodes[node1].position
		local chord = p1 - p0
		local id = world.new_id()
		world.edges[id] = {
			node0 = node0,
			node1 = node1,
			position0 = p0,
			position1 = p1,
			tangent0 = tangent0 or chord,
			tangent1 = tangent1 or chord,
			type = edge_type or NORMAL,
			typeIndex = type_index or (edge_type == TUNNEL and 7 or 0),
			objects = {},
		}
		return id
	end

	--- Straight track along +x at lateral offset y from x0 to x1, made of `count` edges of
	-- `edge_type`. Returns the list of edge ids and the list of node ids.
	function world.straight_track(y, x0, x1, count, edge_type)
		count = count or 1
		local nodes, edges = {}, {}
		for i = 0, count do
			nodes[#nodes + 1] = world.add_node(x0 + (x1 - x0) * i / count, y)
		end
		for i = 1, count do
			edges[#edges + 1] = world.add_edge(nodes[i], nodes[i + 1], edge_type)
		end
		return edges, nodes
	end

	function world.node_edges(node)
		local result = {}
		for id, edge in pairs(world.edges) do
			if edge.node0 == node or edge.node1 == node then result[#result + 1] = id end
		end
		table.sort(result)
		return result
	end

	--- Applies a SimpleProposal: removes, then adds with negative ids mapped to new entities.
	-- Returns the StreetProposal the game hands to onPostBuildProposal.
	function world.apply(simple_proposal)
		local sp = simple_proposal.streetProposal
		for _, edge in ipairs(sp.edgesToRemove or {}) do
			assert(world.edges[edge], "proposal removes unknown edge " .. tostring(edge))
			world.edges[edge] = nil
		end
		for _, node in ipairs(sp.nodesToRemove or {}) do
			assert(world.nodes[node], "proposal removes unknown node " .. tostring(node))
			assert(#world.node_edges(node) == 0, "proposal removes node " .. node .. " that still has edges")
			world.nodes[node] = nil
		end

		local new_ids = {}
		local function resolve(id)
			if id >= 0 then return id end
			return assert(new_ids[id], "unresolved new entity " .. id)
		end
		for _, node in ipairs(sp.nodesToAdd or {}) do
			new_ids[node.entity] = world.new_id()
			world.nodes[new_ids[node.entity]] = { position = copy(node.comp.position) }
		end

		local added = {}
		for _, segment in ipairs(sp.edgesToAdd or {}) do
			local comp = copy(segment.comp)
			comp.node0, comp.node1 = resolve(comp.node0), resolve(comp.node1)
			assert(world.nodes[comp.node0] and world.nodes[comp.node1], "edge references a missing node")
			comp.position0, comp.position1 = world.nodes[comp.node0].position, world.nodes[comp.node1].position
			comp.objects = comp.objects or {}
			local id = world.new_id()
			world.edges[id] = comp
			added[#added + 1] = { entity = id, type = segment.type, comp = copy(comp) }
		end
		return { addedSegments = added }
	end

	local function edges_in_circle(center, radius, component_type)
		assert(component_type == "edge", "mock octree only supports BASE_EDGE")
		local function within(p) return (p.x - center.x) ^ 2 + (p.y - center.y) ^ 2 <= radius ^ 2 end
		local result = {}
		for id, edge in pairs(world.edges) do
			if within(edge.position0) or within(edge.position1) then result[#result + 1] = id end
		end
		table.sort(result)
		return result
	end

	-- Installs the engine global.
	api = { -- luacheck: ignore 121
		type = {
			["enum"] = { BaseEdgeType = { NORMAL = NORMAL, BRIDGE = BRIDGE, TUNNEL = TUNNEL } },
			ComponentType = { BASE_NODE = "node", BASE_EDGE = "edge", PLAYER_OWNED = "owned", BASE_PARALLEL_STRIP = "strip" },
			Vec2f = { new = function(x, y) return { x = x, y = y } end },
			Vec3f = { new = vec3 },
			NodeAndEntity = { new = function() return { comp = {} } end },
			SegmentAndEntity = { new = function() return { comp = {} } end },
			SimpleProposal = { new = function() return { streetProposal = {} } end },
			Context = { new = function() return {} end },
		},
		engine = {
			entityExists = function(entity) return world.nodes[entity] ~= nil or world.edges[entity] ~= nil end,
			getComponent = function(entity, component_type)
				-- observed: getComponent returns a copy; the mod relies on that.
				if component_type == "node" then return copy(world.nodes[entity]) end
				if component_type == "edge" then return copy(world.edges[entity]) end
				return nil
			end,
			system = {
				streetSystem = { getNodeTrackSegments = world.node_edges },
				baseParallelStripSystem = { getStrips = function() return {} end },
			},
			util = {
				getPlayer = function() return 42 end,
				octree = { findEntitiesInCircle = edges_in_circle },
			},
		},
		gui = { contextHelper = { getIdsOfActiveTool = function() return copy(world.active_tools) end } },
		cmd = {
			makeWorldBuildProposalCmd = function(proposal, context, _ignore_errors, player_initiated)
				return { proposal = proposal, context = context, player_initiated = player_initiated }
			end,
			makeScriptingSendEventCmd = function(src, id, name, param)
				return { event = { src = src, id = id, name = name, param = param } }
			end,
			sendCommand = function(command, callback)
				-- observed: game scripts may not pass callbacks ("Callbacks are currently disallowed").
				assert(callback == nil, "Callbacks are currently disallowed")
				if command.event then
					world.script_events[#world.script_events + 1] = command.event
				else
					world.proposals[#world.proposals + 1] = command
				end
			end,
		},
	}

	-- Installs the engine global.
	debugPrint = function(...) -- luacheck: ignore 121
		local parts = {}
		for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
		world.log[#world.log + 1] = table.concat(parts, " ")
		if options.verbose then print("    log: " .. world.log[#world.log]) end
	end

	return world
end

--- Game script state with event subscriptions.
function mock_engine.new_state()
	local stored
	return {
		subscriptions = {},
		subscribeToEvent = function(self, name) self.subscriptions[name] = true end,
		hasEventSubscriptions = function(self) return next(self.subscriptions) ~= nil end,
		get = function() return copy(stored) end,
		set = function(_, value) stored = copy(value) end,
	}
end

--- Drives a game script like the game does: update, guiUpdate, then script events and proposals.
-- Proposals are applied to the world, which fires onPostBuildProposal again.
function mock_engine.new_game(world, script)
	local game = { state = mock_engine.new_state(), gui_state = mock_engine.new_state() }

	function game.post_build(street_proposal, player_initiated)
		if game.state.subscriptions.onPostBuildProposal then
			script.handleEvent({}, game.state, "", "apply_command", "onPostBuildProposal",
				{ { proposal = street_proposal }, {}, {}, player_initiated ~= false })
		end
	end

	--- The player built the given edges (already present in the world).
	function game.player_built(edge_ids)
		local segments = {}
		for _, id in ipairs(edge_ids) do
			segments[#segments + 1] = { entity = id, type = TRACK, comp = copy(world.edges[id]) }
		end
		game.post_build({ addedSegments = segments })
	end

	function game.frame()
		script.update({}, game.state, 0.2)
		if script.guiUpdate then script.guiUpdate({}, game.state, game.gui_state) end

		local events = world.script_events
		world.script_events = {}
		for _, event in ipairs(events) do
			if game.state.subscriptions[event.name] then
				script.handleEvent({}, game.state, event.src, event.id, event.name, event.param)
			end
		end

		local proposals = world.proposals
		world.proposals = {}
		for _, command in ipairs(proposals) do
			world.applied[#world.applied + 1] = command
			game.post_build(world.apply(command.proposal), command.player_initiated)
		end
	end

	function game.run(frames)
		for _ = 1, frames or 10 do game.frame() end
	end

	return game
end

--- Loads a resource file of the mod the way the engine does: run it, then call its data().
-- `path` is relative to the mod's content folder, e.g. "/ux_overhaul/main.script.lua".
function mock_engine.load_resource(path)
	data = nil
	assert(loadfile(mod_paths.content .. path))()
	local resource = assert(data, path .. " does not define data()")()
	data = nil
	return resource
end

return mock_engine
