-- finances.lua: the balance sheet's figures. The base modules it requires are stand-ins, restored
-- after loading so other specs keep theirs.
---@type table<string, table|function>
local stand_ins = {
	["::/gui/main/builtin.lua"] = {},
	["::/gui/main/content_card.tl"] = {},
	["::/gui/main/engine_react_util.tl"] = {},
	["::/gui/main/gui_react_util.tl"] = {},
	["::/gui/main/react.lua"] = {
		---@param _name string
		---@param fn function
		---@return function
		RegisterRecipe = function(_name, fn) return fn end,
	},
	["::/game_mechanics/finance/finances_table.tl"] = function() end,
}
-- the loaded modules, of the paths above: tables and functions
---@type table<string, table|function|nil>
local loaded = package.loaded
---@type table<string, table|function|nil>
local saved = {}
for path, module in pairs(stand_ins) do
	saved[path] = loaded[path]
	loaded[path] = module
end
local finances = require("/ui_overhaul/gui/finances.lua")
for path in pairs(stand_ins) do loaded[path] = saved[path] end

local PLAYER, OTHER = 42, 7

-- What the spec's stand-in for `api` provides: only what finances.read_balance reads.
---@class spec.finances.Api
---@field type { ComponentType: { TRANSPORT_VEHICLE: string, PLAYER_OWNED: string } }
---@field engine spec.finances.Engine

---@class spec.finances.Engine
---@field getEntitiesWithComponent fun(kind: string, filters?: Engine.EntityFilters): integer[]
---@field getComponent fun(id: integer, kind: string): { player: integer }?
---@field util spec.finances.Util

---@class spec.finances.Util
---@field getPlayer fun(): integer
---@field headquarters { getCompaniesValue: fun(): { totalAssets: integer, debt: integer } }
---@field finance { getPlayersBalance: fun(player: integer): integer }
---@field vehicle { getDepreciatedValue: fun(id: integer): integer }

describe("finances", function()
	---@type api
	local saved_api
	---@type integer
	local component_reads

	before_each(function()
		saved_api = api
		component_reads = 0
		-- vehicle -> owner and depreciated value
		local vehicles = {
			[1] = { owner = PLAYER, value = 100 },
			[2] = { owner = OTHER, value = 1000 },
			[3] = { owner = PLAYER, value = 50 },
		}
		---@type spec.finances.Api
		local mock = {
			type = { ComponentType = { TRANSPORT_VEHICLE = "vehicle", PLAYER_OWNED = "owned" } },
			engine = {
				-- as apidef EntityFilters: requireOwnedByPlayer keeps the entities that player owns
				getEntitiesWithComponent = function(kind, filters)
					assert(kind == "vehicle")
					---@type integer[]
					local result = {}
					for id = 1, #vehicles do
						if not (filters and filters.requireOwnedByPlayer)
							or vehicles[id].owner == filters.requireOwnedByPlayer then
							result[#result + 1] = id
						end
					end
					return result
				end,
				getComponent = function(id, kind)
					component_reads = component_reads + 1
					if kind == "owned" then return { player = vehicles[id].owner } end
					return nil
				end,
				util = {
					getPlayer = function() return PLAYER end,
					headquarters = { getCompaniesValue = function() return { totalAssets = 5000, debt = 300 } end },
					finance = { getPlayersBalance = function(player) return player == PLAYER and 900 or 0 end },
					vehicle = { getDepreciatedValue = function(id) return vehicles[id].value end },
				},
			},
		}
		-- A partial stand-in (spec.finances.Api). The cast keeps LuaLS from merging the mock's types into
		-- the global `api` everywhere else; a plain assignment would.
		api = mock --[[@as api]] -- luacheck: ignore 121
	end)
	after_each(function() api = saved_api end) -- luacheck: ignore 121

	it("values only the player's vehicles, without reading every vehicle's owner", function()
		local balance = finances.read_balance()
		assert.are.same({ cash = 900, vehicles = 150, assets = 5000, debt = 300 }, balance)
		assert.are.equal(0, component_reads)
	end)
end)
