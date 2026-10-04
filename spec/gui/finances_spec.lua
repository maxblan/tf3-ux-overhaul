-- finances.lua: the balance sheet's figures. The base modules it requires are stand-ins, restored
-- after loading so other specs keep theirs.
local stand_ins = {
	["::/gui/main/builtin.lua"] = {},
	["::/gui/main/content_card.tl"] = {},
	["::/gui/main/engine_react_util.tl"] = {},
	["::/gui/main/gui_react_util.tl"] = {},
	["::/gui/main/react.lua"] = { RegisterRecipe = function(_name, fn) return fn end },
	["::/game_mechanics/finance/finances_table.tl"] = function() end,
}
local saved = {}
for path, module in pairs(stand_ins) do
	saved[path] = package.loaded[path]
	package.loaded[path] = module
end
local finances = require("/ui_overhaul/gui/finances.lua")
for path in pairs(stand_ins) do package.loaded[path] = saved[path] end

local PLAYER, OTHER = 42, 7

describe("finances", function()
	local saved_api
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
		api = { -- luacheck: ignore 121
			type = { ComponentType = { TRANSPORT_VEHICLE = "vehicle", PLAYER_OWNED = "owned" } },
			engine = {
				-- as apidef EntityFilters: requireOwnedByPlayer keeps the entities that player owns
				getEntitiesWithComponent = function(kind, filters)
					assert(kind == "vehicle")
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
	end)
	after_each(function() api = saved_api end) -- luacheck: ignore 121

	it("values only the player's vehicles, without reading every vehicle's owner", function()
		local balance = finances.read_balance()
		assert.are.same({ cash = 900, vehicles = 150, assets = 5000, debt = 300 }, balance)
		assert.are.equal(0, component_reads)
	end)
end)
