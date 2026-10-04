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
---@class spec.MockVec3
---@field x number
---@field y number
---@field z number
---@operator add(spec.MockVec3): spec.MockVec3
---@operator sub(spec.MockVec3): spec.MockVec3
---@operator mul(number): spec.MockVec3
local Vec3 = {}
Vec3.__index = Vec3

---@param x number
---@param y number
---@param z? number default 0
---@return spec.MockVec3
local function vec3(x, y, z)
	return setmetatable({ x = x, y = y, z = z or 0 }, Vec3)
end

---@param a spec.MockVec3
---@param b spec.MockVec3
---@return spec.MockVec3
Vec3.__add = function(a, b) return vec3(a.x + b.x, a.y + b.y, a.z + b.z) end
---@param a spec.MockVec3
---@param b spec.MockVec3
---@return spec.MockVec3
Vec3.__sub = function(a, b) return vec3(a.x - b.x, a.y - b.y, a.z - b.z) end
---@param a spec.MockVec3
---@param s number
---@return spec.MockVec3
Vec3.__mul = function(a, s) return vec3(a.x * s, a.y * s, a.z * s) end
mock_engine.vec3 = vec3

--- A deep copy of `value`, keeping the metatables.
---@generic T
---@param value T
---@return T
local function copy(value)
	if type(value) ~= "table" then return value end
	local result = {} ---@type table<any, any> a copy of any table
	-- type() above narrowed `value`, which LuaLS cannot see for a generic
	for k, v in pairs(value --[[@as table<any, any>]]) do result[k] = copy(v) end
	return setmetatable(result, getmetatable(value))
end
mock_engine.copy = copy

---@class spec.MockNode
---@field position spec.MockVec3

---@class spec.MockEdge
---@field node0 integer
---@field node1 integer
---@field position0 spec.MockVec3
---@field position1 spec.MockVec3
---@field tangent0 spec.MockVec3
---@field tangent1 spec.MockVec3
---@field type integer mock_engine.NORMAL, BRIDGE or TUNNEL
---@field typeIndex integer
---@field objects table edge objects; the mock keeps whatever the proposal sent

---@class spec.MockNodeAndEntity
---@field entity integer negative for a new node
---@field comp spec.MockNode

---@class spec.MockSegmentAndEntity
---@field entity integer negative for a new edge
---@field type integer 1 = track
---@field comp spec.MockEdge

---@class spec.MockStreetProposal
---@field edgesToRemove integer[]?
---@field nodesToRemove integer[]?
---@field nodesToAdd spec.MockNodeAndEntity[]?
---@field edgesToAdd spec.MockSegmentAndEntity[]?

---@class spec.MockSimpleProposal
---@field streetProposal spec.MockStreetProposal

--- What the game hands to onPostBuildProposal as the proposal's result.
---@class spec.MockAppliedProposal
---@field addedSegments spec.MockSegmentAndEntity[]

---@class spec.MockBuildCommand
---@field proposal spec.MockSimpleProposal
---@field context table
---@field player_initiated boolean?

---@class spec.MockScriptEvent
---@field src string
---@field id string
---@field name string
---@field param any the event's payload, any value

---@class spec.MockSendEventCommand
---@field event spec.MockScriptEvent

---@class spec.MockOptions
---@field verbose boolean? print every debugPrint line

--- The parts of the engine API the mock provides. The component types are strings here.
---@class spec.MockApi
---@field type spec.MockApi.Type
---@field engine spec.MockApi.Engine
---@field gui { contextHelper: spec.MockApi.ContextHelper }
---@field cmd spec.MockApi.Cmd

---@class spec.MockApi.Type
---@field enum { BaseEdgeType: { NORMAL: integer, BRIDGE: integer, TUNNEL: integer } }
---@field ComponentType { BASE_NODE: string, BASE_EDGE: string, PLAYER_OWNED: string, BASE_PARALLEL_STRIP: string }
---@field Vec2f { new: (fun(x: number, y: number): { x: number, y: number }) }
---@field Vec3f { new: (fun(x: number, y: number, z?: number): spec.MockVec3) }
---@field NodeAndEntity { new: (fun(): { comp: table }) } a blank one, which the caller fills in
---@field SegmentAndEntity { new: (fun(): { comp: table }) } a blank one, which the caller fills in
---@field SimpleProposal { new: (fun(): spec.MockSimpleProposal) }
---@field Context { new: (fun(): table) }

---@class spec.MockApi.Engine
---@field entityExists fun(entity: integer): boolean
---@field getComponent fun(entity: integer, component_type: string): spec.MockNode|spec.MockEdge|nil
---@field system spec.MockApi.Systems
---@field util spec.MockApi.Util

---@class spec.MockApi.Systems
---@field streetSystem { getNodeTrackSegments: (fun(node: integer): integer[]) }
---@field baseParallelStripSystem { getStrips: (fun(): integer[]) }

---@class spec.MockApi.Util
---@field getPlayer fun(): integer
---@field octree { findEntitiesInCircle: spec.MockApi.FindInCircle }

---@alias spec.MockApi.FindInCircle fun(center: spec.MockVec3, radius: number, component_type: string): integer[]

---@class spec.MockApi.ContextHelper
---@field getIdsOfActiveTool fun(): string[]

---@class spec.MockApi.Cmd
---@field makeWorldBuildProposalCmd fun(proposal: spec.MockSimpleProposal, context: table, ignore_errors: boolean,
---	player_initiated: boolean): spec.MockBuildCommand
---@field makeScriptingSendEventCmd fun(src: string, id: string, name: string, param: any): spec.MockSendEventCommand
---@field sendCommand fun(command: spec.MockBuildCommand|spec.MockSendEventCommand, callback: function?)

--- Creates a fresh world and installs the globals `api` and `debugPrint`.
---@param options spec.MockOptions?
---@return spec.MockWorld
function mock_engine.new(options)
	options = options or {}
	---@class spec.MockWorld
	---@field nodes table<integer, spec.MockNode>
	---@field edges table<integer, spec.MockEdge>
	---@field next_id integer
	---@field proposals spec.MockBuildCommand[] sent, not applied yet
	---@field applied spec.MockBuildCommand[]
	---@field script_events spec.MockScriptEvent[]
	---@field active_tools string[]
	---@field log string[] the debugPrint lines
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

	---@return integer
	function world.new_id()
		world.next_id = world.next_id + 1
		return world.next_id
	end

	---@param x number
	---@param y number
	---@param z? number
	---@return integer
	function world.add_node(x, y, z)
		local id = world.new_id()
		world.nodes[id] = { position = vec3(x, y, z) }
		return id
	end

	--- Straight edge unless tangents are given; tangent length = chord length (TF convention).
	---@param node0 integer
	---@param node1 integer
	---@param edge_type? integer
	---@param type_index? integer
	---@param tangent0? spec.MockVec3
	---@param tangent1? spec.MockVec3
	---@return integer
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
	---@param y number
	---@param x0 number
	---@param x1 number
	---@param count? integer
	---@param edge_type? integer
	---@return integer[] edges
	---@return integer[] nodes
	function world.straight_track(y, x0, x1, count, edge_type)
		count = count or 1
		local nodes, edges = {}, {} ---@type integer[], integer[]
		for i = 0, count do
			nodes[#nodes + 1] = world.add_node(x0 + (x1 - x0) * i / count, y)
		end
		for i = 1, count do
			edges[#edges + 1] = world.add_edge(nodes[i], nodes[i + 1], edge_type)
		end
		return edges, nodes
	end

	---@param node integer
	---@return integer[]
	function world.node_edges(node)
		local result = {} ---@type integer[]
		for id, edge in pairs(world.edges) do
			if edge.node0 == node or edge.node1 == node then result[#result + 1] = id end
		end
		table.sort(result)
		return result
	end

	--- Applies a SimpleProposal: removes, then adds with negative ids mapped to new entities.
	-- Returns the StreetProposal the game hands to onPostBuildProposal.
	---@param simple_proposal spec.MockSimpleProposal
	---@return spec.MockAppliedProposal
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

		local new_ids = {} ---@type table<integer, integer> negative id -> new entity
		---@param id integer
		---@return integer
		local function resolve(id)
			if id >= 0 then return id end
			return assert(new_ids[id], "unresolved new entity " .. id)
		end
		for _, node in ipairs(sp.nodesToAdd or {}) do
			new_ids[node.entity] = world.new_id()
			world.nodes[new_ids[node.entity]] = { position = copy(node.comp.position) }
		end

		local added = {} ---@type spec.MockSegmentAndEntity[]
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

	---@param center spec.MockVec3
	---@param radius number
	---@param component_type string
	---@return integer[]
	local function edges_in_circle(center, radius, component_type)
		assert(component_type == "edge", "mock octree only supports BASE_EDGE")
		---@param p spec.MockVec3
		---@return boolean
		local function within(p) return (p.x - center.x) ^ 2 + (p.y - center.y) ^ 2 <= radius ^ 2 end
		local result = {} ---@type integer[]
		for id, edge in pairs(world.edges) do
			if within(edge.position0) or within(edge.position1) then result[#result + 1] = id end
		end
		table.sort(result)
		return result
	end

	---@type spec.MockApi
	local mock_api = {
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
					---@cast command spec.MockBuildCommand -- no event: the other kind of command
					world.proposals[#world.proposals + 1] = command
				end
			end,
		},
	}
	-- Installs the engine global. The mock provides only what the mod's track code uses, not the whole api.
	api = mock_api --[[@as api]] -- luacheck: ignore 121

	-- Installs the engine global.
	---@param ... any
	debugPrint = function(...) -- luacheck: ignore 121
		local parts = {} ---@type string[]
		for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
		world.log[#world.log + 1] = table.concat(parts, " ")
		if options.verbose then print("    log: " .. world.log[#world.log]) end
	end

	return world
end

--- Game script state with event subscriptions.
---@return spec.MockScriptState
function mock_engine.new_state()
	local stored ---@type any the script's state, any value
	---@class spec.MockScriptState
	---@field subscriptions table<string, true>
	---@field subscribeToEvent fun(self: spec.MockScriptState, name: string)
	---@field hasEventSubscriptions fun(self: spec.MockScriptState): boolean
	---@field get fun(): any
	---@field set fun(self: spec.MockScriptState, value: any)
	local state = {
		subscriptions = {},
		subscribeToEvent = function(self, name) self.subscriptions[name] = true end,
		hasEventSubscriptions = function(self) return next(self.subscriptions) ~= nil end,
		get = function() return copy(stored) end,
		set = function(_, value) stored = copy(value) end,
	}
	return state
end

--- A game script (a .gs.lua's data()) as the mock drives it.
---@class spec.MockGameScript
---@field handleEvent fun(filename: table, state: spec.MockScriptState, src: string, id: string, name: string,
---	param: any)
---@field update fun(filename: table, state: spec.MockScriptState, dt: number)
---@field guiUpdate (fun(filename: table, state: spec.MockScriptState, gui_state: spec.MockScriptState))?

--- Drives a game script like the game does: update, guiUpdate, then script events and proposals.
-- Proposals are applied to the world, which fires onPostBuildProposal again.
---@param world spec.MockWorld
---@param script spec.MockGameScript
---@return spec.MockGame
function mock_engine.new_game(world, script)
	---@class spec.MockGame
	---@field state spec.MockScriptState
	---@field gui_state spec.MockScriptState
	local game = { state = mock_engine.new_state(), gui_state = mock_engine.new_state() }

	---@param street_proposal spec.MockAppliedProposal
	---@param player_initiated? boolean
	function game.post_build(street_proposal, player_initiated)
		if game.state.subscriptions.onPostBuildProposal then
			script.handleEvent({}, game.state, "", "apply_command", "onPostBuildProposal",
				{ { proposal = street_proposal }, {}, {}, player_initiated ~= false })
		end
	end

	--- The player built the given edges (already present in the world).
	---@param edge_ids integer[]
	function game.player_built(edge_ids)
		local segments = {} ---@type spec.MockSegmentAndEntity[]
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

	---@param frames? integer
	function game.run(frames)
		for _ = 1, frames or 10 do game.frame() end
	end

	return game
end

--- Loads a resource file of the mod the way the engine does: run it, then call its data().
-- `path` is relative to the mod's content folder, e.g. "/ui_overhaul/main.script.lua".
---@param path string
---@return table resource the resource table, whose shape depends on the resource type
function mock_engine.load_resource(path)
	data = nil
	assert(loadfile(mod_paths.content .. path))()
	local resource = assert(data, path .. " does not define data()")()
	data = nil
	return resource
end

return mock_engine
