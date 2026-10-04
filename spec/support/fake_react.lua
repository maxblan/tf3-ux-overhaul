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

---@class spec.Packed: { [integer]: any } table.pack's result: a recipe's arguments, which can be anything
---@field n integer

---@class spec.FakeNode: react.TreeNodeId the fake's tree node
---@field recipe function the recipe that made the node
---@field name string
---@field args spec.Packed
---@field ref react.RefWrap? the node ref it was made with
---@field original function? the recipe a react.CallOriginalRecipe node calls

---@class spec.FakeSlot
---@field kind string the hook that declared it
---@field value any what the recipe stores in the state or ref, which can be anything

---@class spec.FakeState<T>: react.State<T>
---@field get fun(): T

---@class spec.FakeRefInfo
---@field is_react_ref_info true
---@field data react.RefWrap|react.RefWrap[]

---@return spec.Fake
function fake_react.new()
	---@class spec.Fake
	---@field bodies table<function, function> recipe -> body
	---@field names table<function, string> recipe -> name
	---@field by_name table<string, function[]> name -> recipes, in the order registered
	local fake = { bodies = {}, names = {}, by_name = {} }
	local current ---@type spec.FakeInstance? instance being rendered

	--- Records hook `name` in the instance being rendered.
	---@param name string
	---@return integer index the hook's position in this render
	---@return spec.FakeInstance instance
	local function hook(name)
		local instance = assert(current, "hook " .. name .. " outside a render")
		instance.hooks[#instance.hooks + 1] = name
		instance.index = instance.index + 1
		return instance.index, instance
	end
	fake.hook = hook

	---@param name string
	---@param make fun(): any the hook's initial value, which can be anything
	---@return spec.FakeSlot
	---@return spec.FakeInstance
	local function slot(name, make)
		local index, instance = hook(name)
		local slots = instance.slots
		if slots[index] == nil then
			slots[index] = { kind = name, value = make() }
		end
		assert(slots[index].kind == name, "hook " .. index .. " was " .. slots[index].kind .. ", now " .. name)
		return slots[index], instance
	end

	---@generic T
	---@param name string
	---@param make fun(): T
	---@return spec.FakeState<T>
	local function state(name, make)
		local s, instance = slot(name, make)
		return {
			old = function() return s.value end,
			set = function(_self, v) s.value = v instance.dirty = true end,
			transform = function(_self, fn) s.value = fn(s.value) instance.dirty = true end,
			hasExpired = function() return instance.unmounted end,
			get = function() return s.value end,
		}
	end

	--- The instance being rendered, for the react functions that write to it.
	---@param what string
	---@return spec.FakeInstance
	local function rendering(what)
		return assert(current, what .. " outside a render")
	end

	--- The stand-in react module: what the mod's recipes use.
	---@class spec.FakeReact
	---@field setName fun(name: string)
	---@field setStyleClasses fun(...: string)
	---@field setDisableFocusable fun(disableFocusable: boolean)
	---@field setMouseTransparent fun(transparent: boolean)
	---@field setPreferredFocusChild fun(childNodeRef: react.RefWrap)
	local react = {}
	fake.react = react

	-- a node: a leading react.ref(...) is the node's ref, as in react.lua's splitParams
	---@param recipe function
	---@param name string
	---@param ... any the recipe's arguments
	---@return spec.FakeNode
	local function node(recipe, name, ...)
		local args = table.pack(...) ---@type spec.Packed
		local result = { recipe = recipe, name = name, args = args } ---@type spec.FakeNode
		local first = args[1]
		if type(first) == "table" and first.is_react_ref_info then
			result.ref = first.data
			result.args = table.pack(table.unpack(args, 2, args.n))
		end
		return result
	end

	---@param name string
	---@param body function
	---@return fun(...: any): spec.FakeNode recipe
	function react.RegisterRecipe(name, body)
		local recipe ---@type fun(...: any): spec.FakeNode
		recipe = function(...) return node(recipe, name, ...) end
		fake.bodies[recipe] = body
		fake.names[recipe] = name
		fake.by_name[name] = fake.by_name[name] or {}
		table.insert(fake.by_name[name], recipe)
		return recipe
	end
	---@param recipe function
	---@return string
	function react.GetRecipeName(recipe) return fake.names[recipe] end
	---@param recipe function
	---@param ... any the recipe's arguments
	---@return spec.FakeNode
	function react.CallOriginalRecipe(recipe, ...)
		local result = node(recipe, "original", ...)
		result.original = recipe
		return result
	end
	---@param r react.RefWrap|react.RefWrap[]
	---@return spec.FakeRefInfo
	function react.ref(r) return { is_react_ref_info = true, data = r } end

	---@generic T
	---@param initial T
	---@return spec.FakeState<T>
	function react.useState(initial) return state("useState", function() return initial end) end
	---@generic T
	---@param make fun(old: nil): T
	---@return spec.FakeState<T>
	function react.useStateLazy(make) return state("useStateLazy", function() return make(nil) end) end
	---@generic T
	---@param initial T
	---@return react.Ref<T>
	function react.useRef(initial)
		local s = slot("useRef", function() return initial end)
		return { get = function() return s.value end, set = function(_self, v) s.value = v end,
			hasExpired = function() return false end }
	end
	---@return react.Ref<react.NodeRef?>
	function react.useNodeRef() return react.useRef(nil) end
	---@return react.Ref<react.NodeRef?>
	function react.useSelfRef() return react.useRef(nil) end
	---@param fn fun()
	function react.onStep(fn) local _, instance = hook("onStep") instance.on_step[#instance.on_step + 1] = fn end
	---@param fn fun()
	function react.onStepTimer(fn)
		local _, instance = hook("onStepTimer")
		instance.on_step[#instance.on_step + 1] = fn
	end
	---@param fn fun()
	function react.onMount(fn) local _, instance = hook("onMount") instance.on_mount[#instance.on_mount + 1] = fn end
	---@param fn fun()
	function react.onUnmount(fn)
		local _, instance = hook("onUnmount")
		instance.on_unmount[#instance.on_unmount + 1] = fn
	end
	---@param name string
	function react.onEvent(name) hook("onEvent:" .. tostring(name)) end
	---@param ia string
	---@param what any the handler, or a forward (react.iaForward)
	function react.useInputAction(ia, what)
		local _, instance = hook("useInputAction:" .. tostring(ia))
		instance.input_actions[ia] = what
	end
	---@param target any the node ref the action goes to
	---@param action? string
	---@return { forward: any, action: string? }
	function react.iaForward(target, action) return { forward = target, action = action } end
	function react.onMouseEvent() hook("onMouseEvent") end
	function react.useAction() hook("useAction") end
	---@generic F
	---@param fn F
	---@return F
	function react.iaHandler(fn) return fn end
	---@param api table the recipe's api, any functions it offers
	function react.provideApi(api) rendering("provideApi").api = api end
	-- component internals: not hooks
	---@param name string
	---@return fun(...: any)
	local function internal(name)
		return function(...) rendering(name).internals[name] = { ... } end
	end
	react.setName = internal("setName")
	react.setStyleClasses = internal("setStyleClasses")
	react.setDisableFocusable = internal("setDisableFocusable")
	react.setMouseTransparent = internal("setMouseTransparent")
	react.setPreferredFocusChild = internal("setPreferredFocusChild")
	---@return string?
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
		---@class spec.FakeInstance
		---@field name string the recipe's name
		---@field hooks string[] hook names of the last render
		---@field index integer hooks declared so far in this render
		---@field slots spec.FakeSlot[] state and ref values by hook position
		---@field renders integer
		---@field dirty boolean a state of the instance was set since the last render
		---@field unmounted boolean?
		---@field api any what the last render passed to provideApi: the recipe's own api, whatever it offers
		---@field internals table<string, any[]> the arguments of the last call to each component internal
		---@field on_step fun()[]
		---@field on_mount fun()[]
		---@field on_unmount fun()[]
		---@field input_actions table<string, any> what the last render declared for each input action
		local instance = { slots = {}, hooks = {}, renders = 0, dirty = false, name = fake.names[recipe],
			on_step = {}, on_mount = {}, on_unmount = {}, internals = {}, input_actions = {} }
		--- Renders the recipe's body with `...` and returns what it returned.
		---@param ... any the recipe's arguments
		---@return any node what the body returned, a node or a spec's own value
		function instance.render(...)
			instance.hooks, instance.index, instance.dirty = {}, 0, false
			instance.on_step, instance.on_mount, instance.on_unmount = {}, {}, {}
			instance.input_actions = {}
			local saved = current
			current = instance
			local result = table.pack(pcall(body, ...)) ---@type spec.Packed
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
---@return any stand_in any field and any call works on it, as on the module it stands in for
function fake_react.any()
	local mt = {}
	---@param t table
	---@param k any
	---@return any
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
---@param stand_ins table<string, any> module path -> stand-in module, of any shape
---@return any module the loaded module, of whichever type `path` returns
function fake_react.load(path, stand_ins)
	local loaded = package.loaded ---@type table<string, any> module name -> module, of any type
	local before = {} ---@type table<string, true>
	for name in pairs(loaded) do before[name] = true end
	local saved_gui = {} ---@type table<string, any>
	for name, module in pairs(loaded) do
		if type(name) == "string" and name:find("^/ui_overhaul/gui/") then saved_gui[name] = module end
	end
	for name in pairs(saved_gui) do loaded[name] = nil end
	local saved = {} ---@type table<string, any>
	for name, module in pairs(stand_ins) do
		saved[name] = loaded[name]
		loaded[name] = module
	end
	---@param name string
	---@return (fun(): any)?
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
	for name in pairs(stand_ins) do loaded[name] = saved[name] end
	for name in pairs(loaded) do
		if not before[name] or saved_gui[name] then loaded[name] = nil end
	end
	for name, module in pairs(saved_gui) do loaded[name] = module end
	assert(ok, result)
	return result
end

return fake_react
