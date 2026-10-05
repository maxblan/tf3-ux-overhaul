_G.debugPrint = _G.debugPrint or function() end

local settings = require("/ui_overhaul/gui/settings.lua")

--- The content of a file (fengari: read_file from tools/lua/run_specs.js; native Lua: io.open).
---@param path string
---@return string
local function read(path)
	local globals = _G ---@type table<string, any>
	local read_file = globals.read_file ---@type (fun(path: string): string)? tools/lua/run_specs.js
	if read_file then return read_file(path) end
	local file = assert(io.open(path, "r"))
	local content = file:read("*a")
	file:close()
	return content
end

---@param params table<string, number>?
local function with_params(params)
	settings.reset()
	local globals = _G ---@type table<string, any>
	globals.api = { engine = { config = { getModParams = function() return { ui_overhaul_1 = params } end } } }
end

describe("settings", function()
	it("lists the same features, in the same order, as the params in mod.json", function()
		local keys = {} ---@type string[]
		for key in read("src/ui_overhaul/mod.json"):gmatch('"key": "uio_([%w_]+)"') do keys[#keys + 1] = key end
		assert.are.same(settings.FEATURES, keys)
	end)

	it("gives every param the values On and Off, On first", function()
		local json = read("src/ui_overhaul/mod.json")
		local _n, params = json:gsub('"key": "uio_', "")
		local _m, values = json:gsub('"values": %[%s*"On",%s*"Off"%s*%]', "")
		local _k, defaults = json:gsub('"defaultIndex": 0', "")
		assert.are.equal(params, values)
		assert.are.equal(params, defaults)
	end)

	it("keeps a feature on unless the player chose Off (index 2)", function()
		with_params({ uio_finances = 2, uio_statistics = 1 })
		assert.is_false(settings.enabled("finances"))
		assert.is_true(settings.enabled("statistics"))
		assert.is_true(settings.enabled("minimize")) -- no value: the default
		assert.is_true(settings.enabled("not_a_feature"))
		assert.are.equal("switched off: finances", settings.describe())
	end)

	it("keeps everything on where the game has no params for the mod or cannot give them", function()
		with_params(nil)
		assert.is_true(settings.enabled("finances"))
		assert.are.equal("all features on", settings.describe())
		settings.reset()
		local globals = _G ---@type table<string, any>
		globals.api = { engine = { config = { getModParams = function() error("not in this state") end } } }
		assert.is_true(settings.enabled("finances"))
	end)
end)
