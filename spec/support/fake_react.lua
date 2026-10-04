--- A stand-in for the game's react.lua that records the hooks each recipe instance declares, so specs
-- can check that an instance declares the same hooks on every render.
--
-- As in the game, calling a registered recipe returns a node ({ recipe, name, args }); its body runs
-- only when a spec mounts and renders it. Hooks (useState, useRef, onStep ...) are recorded by name
-- in the order of the call; states and refs keep their value per instance by position.
--
--   local fake = require("fake_react").new()
--   package.loaded["::/gui/main/react.lua"] = fake.react
--   local instance = fake.mount(fake.recipe("ToolStack"))
--   local node = instance.render(params)  -- instance.hooks: the hook names of this render
--   instance.step()                       -- runs the onStep callbacks of the last render
local fake_react = {}

---@class spec.FakeNode
---@field recipe function the recipe that made the node
---@field name string
---@field args any[]
---@field ref table? the node ref it was made with

---@class spec.FakeInstance
---@field hooks string[] hook names of the last render
---@field renders integer
---@field dirty boolean a state of the instance was set since the last render
---@field api table? what the last render passed to provideApi
---@field render fun(...): any
---@field step fun()
---@field unmount fun()

---@return table
function fake_react.new()
	local fake = { bodies = {}, names = {}, by_name = {} }
	local current ---@type table? instance being rendered

	local function hook(name)
		assert(current, "hook " .. name .. " outside a render")
		current.hooks[#current.hooks + 1] = name
		current.index = current.index + 1
		return current.index
	end
	fake.hook = hook

	local function slot(name, make)
		local index = hook(name)
		local slots = current.slots
		if slots[index] == nil then
			slots[index] = { kind = name, value = make() }
		end
		assert(slots[index].kind == name, "hook " .. index .. " was " .. slots[index].kind .. ", now " .. name)
		return slots[index]
	end

	local function state(name, make)
		local instance = current
		local s = slot(name, make)
		return {
			old = function() return s.value end,
			set = function(_self, v) s.value = v instance.dirty = true end,
			transform = function(_self, fn) s.value = fn(s.value) instance.dirty = true end,
			hasExpired = function() return instance.unmounted end,
			get = function() return s.value end,
		}
	end

	local react = {}
	fake.react = react

	-- a node: a leading react.ref(...) is the node's ref, as in react.lua's splitParams
	local function node(recipe, name, ...)
		local args = table.pack(...)
		local result = { recipe = recipe, name = name, args = args }
		if type(args[1]) == "table" and args[1].is_react_ref_info then
			result.ref = args[1].data
			result.args = table.pack(table.unpack(args, 2, args.n))
		end
		return result
	end

	function react.RegisterRecipe(name, body)
		local recipe
		recipe = function(...) return node(recipe, name, ...) end
		fake.bodies[recipe] = body
		fake.names[recipe] = name
		fake.by_name[name] = fake.by_name[name] or {}
		table.insert(fake.by_name[name], recipe)
		return recipe
	end
	function react.GetRecipeName(recipe) return fake.names[recipe] end
	function react.CallOriginalRecipe(recipe, ...)
		local result = node(recipe, "original", ...)
		result.original = recipe
		return result
	end
	function react.ref(r) return { is_react_ref_info = true, data = r } end

	function react.useState(initial) return state("useState", function() return initial end) end
	function react.useStateLazy(make) return state("useStateLazy", function() return make(nil) end) end
	function react.useRef(initial)
		local s = slot("useRef", function() return initial end)
		return { get = function() return s.value end, set = function(_self, v) s.value = v end,
			hasExpired = function() return false end }
	end
	function react.useNodeRef() return react.useRef(nil) end
	function react.useSelfRef() return react.useRef(nil) end
	function react.onStep(fn) hook("onStep") current.on_step[#current.on_step + 1] = fn end
	function react.onStepTimer(fn) hook("onStepTimer") current.on_step[#current.on_step + 1] = fn end
	function react.onMount(fn) hook("onMount") current.on_mount[#current.on_mount + 1] = fn end
	function react.onUnmount(fn) hook("onUnmount") current.on_unmount[#current.on_unmount + 1] = fn end
	function react.onEvent(name) hook("onEvent:" .. tostring(name)) end
	function react.useInputAction(ia) hook("useInputAction:" .. tostring(ia)) end
	function react.onMouseEvent() hook("onMouseEvent") end
	function react.useAction() hook("useAction") end
	function react.iaHandler(fn) return fn end
	function react.provideApi(api) current.api = api end
	-- component internals: not hooks
	for _i, name in ipairs({ "setName", "setStyleClasses", "setDisableFocusable", "setMouseTransparent",
		"setPreferredFocusChild" }) do
		react[name] = function(...) current.internals[name] = { ... } end
	end
	function react.getCurrentRecipeName() return current and current.name end

	--- The recipe registered under `name` (the `n`-th one, for names registered twice).
	---@param name string
	---@param n? integer
	---@return function
	function fake.recipe(name, n)
		local list = assert(fake.by_name[name], "no recipe " .. name)
		return assert(list[n or 1], "no recipe " .. name .. " #" .. tostring(n or 1))
	end

	--- A mounted instance of `recipe`.
	---@param recipe function
	---@return spec.FakeInstance
	function fake.mount(recipe)
		local body = assert(fake.bodies[recipe], "not a registered recipe")
		local instance = { slots = {}, hooks = {}, renders = 0, dirty = false, name = fake.names[recipe],
			on_step = {}, on_mount = {}, on_unmount = {}, internals = {} }
		function instance.render(...)
			instance.hooks, instance.index, instance.dirty = {}, 0, false
			instance.on_step, instance.on_mount, instance.on_unmount = {}, {}, {}
			local saved = current
			current = instance
			local result = table.pack(pcall(body, ...))
			current = saved
			instance.renders = instance.renders + 1
			assert(result[1], result[2])
			return result[2]
		end
		function instance.step()
			for _i, fn in ipairs(instance.on_step) do fn() end
		end
		function instance.unmount()
			instance.unmounted = true
			for _i, fn in ipairs(instance.on_unmount) do fn() end
		end
		return instance
	end

	--- Mounts the recipe of `made` (a node) and renders it with the node's arguments.
	---@param made spec.FakeNode
	---@return spec.FakeInstance, any
	function fake.render_node(made)
		local instance = fake.mount(made.recipe)
		return instance, instance.render(table.unpack(made.args, 1, made.args.n))
	end

	return fake
end

--- A module stand-in that answers every field with another stand-in and can be called; for base
--- modules a spec does not care about. As a list it is empty.
---@return table
function fake_react.any()
	local mt = {}
	mt.__index = function(t, k)
		if type(k) == "number" then return nil end -- an empty list, so loops over it end
		local v = fake_react.any()
		rawset(t, k, v)
		return v
	end
	mt.__call = function() return fake_react.any() end
	return setmetatable({}, mt)
end

--- Loads `path` (a mod path, "/ui_overhaul/...") with `stand_ins` in package.loaded and every other
--- "::/" module answered by fake_react.any(); "ui_overhaul_1::/..." loads the mod's file. The mod's
--- gui modules load anew, so they see these stand-ins; package.loaded is restored afterwards.
---@param path string
---@param stand_ins table<string, any>
---@return any
function fake_react.load(path, stand_ins)
	local before = {}
	for name in pairs(package.loaded) do before[name] = true end
	local saved_gui = {}
	for name, module in pairs(package.loaded) do
		if type(name) == "string" and name:find("^/ui_overhaul/gui/") then saved_gui[name] = module end
	end
	for name in pairs(saved_gui) do package.loaded[name] = nil end
	local saved = {}
	for name, module in pairs(stand_ins) do
		saved[name] = package.loaded[name]
		package.loaded[name] = module
	end
	local function any_searcher(name)
		-- the mod's fully qualified paths are the mod's own files
		local own = name:match("^ui_overhaul_1::(/.*)$")
		if own then return function() return require(own) end end
		if name:sub(1, 3) ~= "::/" then return nil end
		return function() return fake_react.any() end
	end
	table.insert(package.searchers, 1, any_searcher)
	local ok, result = pcall(require, path)
	table.remove(package.searchers, 1)
	for name in pairs(stand_ins) do package.loaded[name] = saved[name] end
	for name in pairs(package.loaded) do
		if not before[name] or saved_gui[name] then package.loaded[name] = nil end
	end
	for name, module in pairs(saved_gui) do package.loaded[name] = module end
	assert(ok, result)
	return result
end

return fake_react
