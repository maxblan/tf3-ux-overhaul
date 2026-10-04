-- lvm_tweaks.lua: the VehicleList replacement (focus, the Line Manager params it keeps), the Shift
-- selection wrapper and the replace confirmation. The base modules are stand-ins (fake_react.load).
local fake_react = require("fake_react")

-- What the specs' stand-in for `api` provides: only what the replace confirmation reads.
---@class spec.lvm_tweaks.Api
---@field engine { util: { vehicle: spec.lvm_tweaks.VehicleUtil } }
---@field util { formatMoney: fun(cost: number): string }

---@class spec.lvm_tweaks.VehicleUtil
---@field getPartPrice fun(part: any): number
---@field getDepreciatedValue fun(v: integer): number

---A recorded call of a stand-in function: its arguments.
---@class spec.lvm_tweaks.Call: spec.Packed

---@class spec.lvm_tweaks.Setup
---@field fake spec.Fake
---@field handled spec.lvm_tweaks.Call[] calls of the base HandleVehicleChanges
---@field vehicle_react_util { HandleVehicleChanges: fun(changes: table, ...: any) }
---@field lvm_models { shift: boolean, selected_model: integer[] }

---@return spec.lvm_tweaks.Setup
local function setup()
	local fake = fake_react.new()
	local react_stand_in = fake.react --[[@as table<string, any>]] -- plus what lvm_tweaks wraps
	react_stand_in.fireEvent = function() end
	local handled = {} ---@type spec.lvm_tweaks.Call[]
	local vehicle_react_util = {
		HandleVehicleChanges = function(...) handled[#handled + 1] = table.pack(...) end,
	}
	local models = { shift = false, selected_model = {} } ---@type { shift: boolean, selected_model: integer[] }
	local builtin = fake_react.any()
	builtin.BoxLayout = function(t) return { layout = t } end
	---@type table<string, any>
	local stand_ins = {
		["::/gui/main/react.lua"] = fake.react,
		["::/gui/main/builtin.lua"] = builtin,
		["::/gui/line_vehicle_mgmt/vehicle_react_util.tl"] = vehicle_react_util,
		["::/scripts/table_util.tl"] = {
			---@param t table
			---@return table
			shallowCopy = function(t)
				local copy = {} ---@type table<any, any>
				---@diagnostic disable-next-line: no-unknown
				for k, v in pairs(t) do copy[k] = v end
				return copy
			end,
		},
		["::/scripts/lang_util.tl"] = {
			---@param text string
			---@param values table<string, any>
			---@return string
			format = function(text, values)
				return (text:gsub("{(%w+)}", function(k) return tostring(values[k]) end))
			end,
		},
		["/ui_overhaul/gui/tool_stack.lua"] = { on_pop = {} },
		["/ui_overhaul/gui/lvm_models.lua"] = {
			live = { params = nil },
			shift_held = function() return models.shift end,
			---@param entity integer
			---@return boolean
			select_same_model = function(entity)
				models.selected_model[#models.selected_model + 1] = entity
				return true
			end,
			update = function() return nil end,
			line_count = function() return 1 end,
		},
	}
	local lvm_tweaks = fake_react.load("/ui_overhaul/gui/lvm_tweaks.lua", stand_ins)
	lvm_tweaks.install({ ReplaceRecipe = function() end })
	return { fake = fake, handled = handled, vehicle_react_util = vehicle_react_util, lvm_models = models }
end

-- Changes that replace two vehicles.
---@return table[]
local function two_replaces()
	return {
		{ vehicleEntity = 1, config = { vehicles = { "part" } } },
		{ vehicleEntity = 2, config = { vehicles = { "part" } } },
	}
end

describe("lvm_tweaks", function()
	local globals = _G ---@type table<string, any> global name -> value, of any type
	local saved = {} ---@type table<string, any>
	before_each(function()
		for _i, name in ipairs({ "debugPrint", "_", "api" }) do saved[name] = globals[name] end
		---@param text string
		---@return string
		local function tr(text) return text end
		local quiet = function() end ---@type fun(...: any)
		_G._, _G.debugPrint = tr, quiet
		---@type spec.lvm_tweaks.Api
		local mock = {
			engine = { util = { vehicle = {
				getPartPrice = function() return 0 end,
				getDepreciatedValue = function() return 0 end,
			} } },
			util = { formatMoney = function(cost) return tostring(cost) end },
		}
		_G.api = mock --[[@as api]]
	end)
	after_each(function()
		for name, value in pairs(saved) do globals[name] = value end
	end)

	---@param s spec.lvm_tweaks.Setup
	---@param questions table[] where addFeedback records its questions
	---@return spec.FakeInstance list the mounted VehicleList replacement
	---@return table params the list's params
	local function mount_list(s, questions)
		---@param _text string
		---@param _kind string
		---@param question table
		local function add_feedback(_text, _kind, question) questions[#questions + 1] = question end
		local params = { commonParams = { addFeedback = add_feedback } }
		local list = s.fake.mount(s.fake.recipe("VehicleList"))
		list.render(params)
		return list, params
	end

	it("asks before replacing several vehicles and passes every argument on, also after a nil", function()
		local s = setup()
		local questions = {} ---@type table[]
		mount_list(s, questions)
		local on_fail = function() end
		s.vehicle_react_util.HandleVehicleChanges(two_replaces(), "protected", nil, on_fail)
		assert.are.equal(0, #s.handled)
		assert.are.equal(1, #questions)
		questions[1].onAccept()
		assert.are.equal(1, #s.handled)
		assert.are.equal(4, s.handled[1].n)
		assert.are.equal(on_fail, s.handled[1][4])
	end)

	it("replaces directly once the Line Manager that would ask is closed", function()
		local s = setup()
		local questions = {} ---@type table[]
		local list = mount_list(s, questions)
		list.unmount()
		s.vehicle_react_util.HandleVehicleChanges(two_replaces())
		assert.are.equal(0, #questions)
		assert.are.equal(1, #s.handled)
	end)

	it("hands the Line Manager's focus on to the vehicle list, not the model row", function()
		local s = setup()
		local list = mount_list(s, {})
		local node = list.render({ commonParams = { addFeedback = function() end } })
		local preferred = list.internals.setPreferredFocusChild[1]
		local children = node.layout.children ---@type spec.FakeNode[]
		local inner = children[#children] ---@type spec.FakeNode
		assert.are.equal("original", inner.name)
		assert.truthy(preferred ~= nil)
		assert.are.equal(preferred, inner.ref)
	end)

	it("Shift selects a vehicle's model, but a deselection stays one vehicle", function()
		local s = setup()
		local vm_api = {} ---@type table<string, function>
		local seen = {} ---@type spec.lvm_tweaks.Call[]
		vm_api.selectVehicles = function(...) seen[#seen + 1] = table.pack(...) end
		local manager = { getApi = function() return vm_api end }
		local list = s.fake.mount(s.fake.recipe("VehicleList"))
		list.render({
			managerRef = { get = function() return manager end },
			commonParams = { vehicleManagerStateRef = { get = function() return {} end } },
		})
		s.lvm_models.shift = true
		vm_api.selectVehicles({ 7 }, false)
		assert.are.equal(1, #seen)
		assert.is_false(seen[1][2])
		assert.are.same({}, s.lvm_models.selected_model)
		vm_api.selectVehicles({ 7 }, true)
		assert.are.same({ 7 }, s.lvm_models.selected_model)
		assert.are.equal(1, #seen)
	end)
end)
