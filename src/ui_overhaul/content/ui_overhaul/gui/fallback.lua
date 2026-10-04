--- Replacement recipes that fall back to the base recipe for the rest of the session, without a recipe
-- instance ever changing the hooks it declares. The engine keeps hook state by position
-- (callingRecipeCtx:declareState, react.lua:468ff), so a recipe has to declare the same hooks in the
-- same order on every render. A recipe that pcalls a render and returns the base recipe on failure
-- breaks that: the failed render stops at the error, and later renders declare none.
--   * The mod's render runs in a child recipe that owns all of its hooks. The child runs the render
--     under pcall on every render, so it declares the same hooks again. After a failure it logs one
--     line, marks the switch failed and renders an empty layout.
--   * The parent always declares the same hooks: a state and an onStep that render it again on the
--     GUI step after the failure (from then on it renders the base recipe, so the child unmounts), and
--     a node ref each for the child and the base, plus one input-action forward per
--     options.input_actions entry. A parent without hooks would leave the empty child
--     until an ancestor happens to render again (the game bar or the ridge root rarely do); a child
--     that showed the base itself would remount it at that later switch, which closes the open tools
--     and plays Resolve for every base notification icon.
-- @module ui_overhaul.gui.fallback
local react = require("::/gui/main/react.lua")
local builtin = require("::/gui/main/builtin.lua")

---@class uo.gui.fallback
local fallback = {}

-- The parent's layout around the shown node. fallback.css.lua makes it layout-neutral: no spacing from
-- the base rules that select every BoxLayout under the replaced recipe, and it and the shown node fill
-- the replaced node, as the base root did.
local WRAPPER = { class = "uio-fallback" }

---@class uo.gui.fallback.Switch
---@field label string what failed, for the log line
---@field failed boolean true once the mod's render failed: the base is shown for the session

---@param label string
---@return uo.gui.fallback.Switch
function fallback.switch(label)
	return { label = label, failed = false }
end

--- Marks the switch failed and logs the first error.
---@param switch uo.gui.fallback.Switch
---@param err any
function fallback.fail(switch, err)
	if switch.failed then return end
	switch.failed = true
	debugPrint("[ui_overhaul] ", switch.label, " failed, showing the base one: ", tostring(err))
end

--- The child recipe: `render(...)` under pcall on every render; an empty layout once the switch failed.
--- Register it under the base recipe name where the base stylesheet selects the recipe.
---@generic T
---@param switch uo.gui.fallback.Switch
---@param name string
---@param render fun(params: T): react.TreeNodeId?
---@return react.Recipe<T> recipe
function fallback.child(switch, name, render)
	return react.RegisterRecipe(name, function(...)
		local ok, node = pcall(render, ...)
		if not ok then fallback.fail(switch, node) end
		-- empty and unspaced (fallback.css.lua): the base stylesheet may space every BoxLayout here
		if switch.failed or node == nil then return builtin.BoxLayout{ meta = WRAPPER } end
		return node
	end)
end

--- The parent's two hooks, declared on every render. Returns true when the parent renders the base.
---@param switch uo.gui.fallback.Switch
---@return boolean
function fallback.use_base(switch)
	local shown = react.useState(switch.failed)
	react.onStep(function()
		if switch.failed and not shown:old() then shown:set(true) end
	end)
	return switch.failed
end

--- The forwarded methods of the replaced recipe's Api; their arguments and results are that recipe's
--- own, passed through unchanged, so they are `any` here.
---@alias uo.gui.fallback.Api table<string, fun(...: any): any>

---@class uo.gui.fallback.Options
---@field child_name? string the child's recipe name (default: the replacement's, for the base stylesheet)
---@field api? string[] methods the replaced recipe provides (react.provideApi); the parent provides them
---  and calls the shown node's, since whoever holds a ref to the replaced recipe holds the parent
---@field focus? boolean the parent's preferred focus child is the shown node (the base tab sets one)
---@field internals? fun() sets the replaced recipe's component internals on the parent (react.setName ...)
---@field render_base? fun(params: any): react.TreeNodeId? the base node, where the base is not one fixed
---  recipe (nil: nothing)
---@field input_actions? string[] input actions the game forwards to the replaced node (react.iaForward); the
---  parent forwards them on to the shown node, whose recipe handles them
---@field nothing? fun(params: any): boolean true where the base renders nothing (returns nil): the parent then
---  renders nothing either, instead of an empty wrapper that a stylesheet could still space

--- The replacement recipe `name` for `base`: the child (`render`) until it fails, then the base
--- (react.CallOriginalRecipe, or options.render_base).
--- The parent's hooks: the two of use_base, a node ref each for the child and the base, then one
--- useInputAction per options.input_actions entry.
--- Returns the parent recipe and the child recipe.
---@generic T
---@param switch uo.gui.fallback.Switch
---@param name string
---@param render fun(params: T): react.TreeNodeId?
---@param base react.Recipe<T>? the replaced recipe (nil with options.render_base)
---@param options? uo.gui.fallback.Options
---@return react.Recipe<T> parent, react.Recipe<T> child
function fallback.replacement(switch, name, render, base, options)
	options = options or {}
	local child = fallback.child(switch, options.child_name or name, render)
	local parent = react.RegisterRecipe(name, function(...)
		if options.internals then options.internals() end
		local use_base = fallback.use_base(switch)
		---@type react.RefWrapApi<uo.gui.fallback.Api>
		local child_ref = react.useNodeRef()
		---@type react.RefWrapApi<uo.gui.fallback.Api>
		local base_ref = react.useNodeRef()
		local shown = use_base and base_ref or child_ref
		if options.api then
			---@type uo.gui.fallback.Api
			local forwarded = {}
			for _i, method in ipairs(options.api) do
				forwarded[method] = function(...)
					-- the base once it is mounted; until then the child, which still provides its own
					local ref = (switch.failed and base_ref:get()) and base_ref or child_ref
					local node = ref:get()
					local node_api = node and node:getApi()
					if node_api and node_api[method] then return node_api[method](...) end
				end
			end
			react.provideApi(forwarded)
		end
		if options.focus then react.setPreferredFocusChild(shown) end
		for _i, action in ipairs(options.input_actions or {}) do
			react.useInputAction(action, react.iaForward(shown))
		end
		if options.nothing then
			local ok, nothing = pcall(options.nothing, ...)
			if ok and nothing then return nil end
		end
		if use_base then
			---@type react.TreeNodeId?
			local node
			if options.render_base then
				node = options.render_base(...)
			else
				---@cast base -nil -- replacement() takes base or options.render_base
				node = react.CallOriginalRecipe(base, react.ref(base_ref), ...)
			end
			return builtin.BoxLayout{ meta = WRAPPER, children = { node } }
		end
		return builtin.BoxLayout{ meta = WRAPPER, children = { child(react.ref(child_ref), ...) } }
	end)
	return parent, child
end

return fallback
