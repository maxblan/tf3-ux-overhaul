--- Window behaviour. The game manages its big windows on a "tool stack" where only
-- the top tool's window is visible and opening a window closes the others. This replacement keeps
-- the vanilla stack and changes three rules:
--   * the "window tools" (Statistics, Line Manager, Finances, Company, notification log) and entity
--     windows can be open next to each other: none of them hides the others
--   * closing all tools (a click on the map, pinning a window, opening another tool) keeps the window
--     tools open; they close with their own close button or Esc
--   * opening a window tool keeps the entity windows open, so "Manage Line" in a line window no longer
--     closes that line window
-- While another tool is on top (construction, bulldozer, layers ...), window tools and entity windows
-- are hidden as before and come back afterwards.
-- A copy of the vanilla builtin.ToolStack (gui/main/builtin.lua) with these rules marked "UIO";
-- installed through a react-replacement-config (tool_stack.script.lua). If rendering fails, the
-- vanilla tool stack is used for the rest of the session (fallback.lua).
-- @module ui_overhaul.gui.tool_stack
local react = require("::/gui/main/react.lua")
local builtin = require("::/gui/main/builtin.lua")
local fallback = require("/ui_overhaul/gui/fallback.lua")

---@class uo.gui.tool_stack
local tool_stack = {}

--- A stack entry's context: what the tool's handlers get (builtin.ToolStackContext) and the stack's
--- own bookkeeping (the vanilla ToolStack in builtin.lua keeps the same fields).
---@class uo.gui.tool_stack.Context: builtin.ToolStackContext
---@field shelved boolean
---@field key2? string
---@field localKey string
---@field isTop? boolean
---@field discardNodeIdentity? boolean
---@field actionFn? fun(): react.TreeNodeId
---@field variantOverride? string
---@field propagateActionFn fun(actionFn?: (fun(): react.TreeNodeId), key2?: string)

---@class uo.gui.tool_stack.Entry
---@field toolDef builtin.ToolDefinition
---@field key string
---@field params any the tool's params, whatever its pusher passed (builtin.ToolDefinition)
---@field ctx uo.gui.tool_stack.Context
---@field propagateActionFn nil never set: makeContext reads it as the vanilla one does (builtin.lua:1315)

--- Functions called with the stack entry whenever a tool is popped (e.g. lvm_tweaks.lua).
---@type (fun(entry: uo.gui.tool_stack.Entry))[]
tool_stack.on_pop = {}

---@param entry uo.gui.tool_stack.Entry
local function notify_pop(entry)
	for _i, hook in ipairs(tool_stack.on_pop) do
		local ok, err = pcall(hook, entry)
		if not ok then debugPrint("[ui_overhaul] tool pop hook failed: ", tostring(err)) end
	end
end

-- UIO: tools whose windows may stay open next to each other and survive clear().
---@type table<string, boolean>
local WINDOW_TOOLS = { Statistics = true, Manager = true, Finances = true, Company = true, NotificationLog = true }
local ENTITY_TOOL = "EntityDetailsTool"

---@param entry? uo.gui.tool_stack.Entry
---@return string?
local function tool_name(entry)
	return entry and entry.toolDef and entry.toolDef.name or nil
end

---@param entry? uo.gui.tool_stack.Entry
---@return boolean
local function is_window_tool(entry)
	return WINDOW_TOOLS[tool_name(entry)] == true
end

---@param entry? uo.gui.tool_stack.Entry
---@return boolean
local function is_entity_window(entry)
	return tool_name(entry) == ENTITY_TOOL
end

---@param oldStack uo.gui.tool_stack.Entry[]
---@param toolDef builtin.ToolDefinition
---@param toolKey string
---@return uo.gui.tool_stack.Entry[] newStack, uo.gui.tool_stack.Entry? skipped
local function copyToolStackExcept(oldStack, toolDef, toolKey)
	---@type uo.gui.tool_stack.Entry?
	local skipped = nil
	---@type uo.gui.tool_stack.Entry[]
	local newStack = {}
	for _i, entry in ipairs(oldStack) do
		if entry.toolDef ~= toolDef or entry.key ~= toolKey then
			newStack[#newStack + 1] = entry
		else
			skipped = entry
		end
	end
	return newStack, skipped
end

--- The action function shown for an entry and its key2.
---@class uo.gui.tool_stack.Action
---@field [1] (fun(): react.TreeNodeId)?
---@field [2] string?

---@class uo.gui.tool_stack.EntryWrapParam: react.Param
---@field ctx uo.gui.tool_stack.Context
---@field propagateActionFn nil never set: makeContext reads it as the vanilla one does (builtin.lua:1315)
---@field rendererComponent react.RefWrapApi<builtin.RenderComponentAPI>

-- Copy of the vanilla ToolStackEntryWrap (local in builtin.lua).
---@param param uo.gui.tool_stack.EntryWrapParam
---@return react.TreeNodeId?
local ToolStackEntryWrap = react.RegisterRecipe("ToolStackEntryWrap", function(param)
	react.setName("ToolStackEntryWrap")
	local ctx = param.ctx
	---@type react.State<uo.gui.tool_stack.Action>
	local actionFnState = react.useState({ ctx.actionFn, ctx.key2 })
	---@param actionFn? fun(): react.TreeNodeId
	---@param key2? string
	local propagateActionFn = function(actionFn, key2)
		if actionFnState:hasExpired() then return end
		actionFnState:transform(function(cur)
			if cur[2] ~= key2 then
				ctx.discardNodeIdentity = true
			elseif actionFn == cur[1] then
				return cur
			end
			return { actionFn, key2 }
		end)
	end
	local selfRef = react.useAction(param.rendererComponent, actionFnState:old()[1], actionFnState:old()[2])
	react.onMount(function()
		ctx.propagateActionFn = propagateActionFn
		if ctx.isTop then
			param.rendererComponent:get():getApi().setActiveOwner(selfRef)
		end
	end)
	if ctx.isTop then
		if param.rendererComponent:get():getIdentity() then
			param.rendererComponent:get():getApi().setActiveOwner(selfRef)
		end
	end
end)

---@param params builtin.ToolStackParam
---@return react.TreeNodeId
local function render(params)
	react.setName("ToolStack")
	react.setDisableFocusable(true)
	---@type react.State<uo.gui.tool_stack.Entry[]>
	local stack = react.useState({})
	---@type react.Ref<table<string, boolean>>
	local dropChildIds = react.useRef({})
	---@type react.Ref<uo.gui.tool_stack.Entry?>
	local top = react.useRef(nil)

	---@return builtin.RenderComponentAPI?
	local function getRendererComponentApi()
		if params.rendererComponent:hasExpired() then return nil end
		if not params.rendererComponent:get():getIdentity() then return nil end
		return params.rendererComponent:get():getApi()
	end

	local function setTopActionToRc()
		local tool = top:get() or nil
		if not tool then
			getRendererComponentApi().setActiveOwner(nil)
		end
	end

	---@param newStack uo.gui.tool_stack.Entry[]
	local function updateTop(newStack)
		---@type uo.gui.tool_stack.Entry?
		local last = nil
		for _i, entry in ipairs(newStack) do
			entry.ctx.isTop = false
			last = entry
		end
		if last then last.ctx.isTop = true end
		top:set(newStack[#newStack])
		setTopActionToRc()
	end

	---@param entry? uo.gui.tool_stack.Entry
	---@return boolean?
	local function is_default(entry)
		return entry and entry.toolDef == params.defaultTool and entry.key == params.defaultToolKey
	end

	-- UIO: window tools and entity windows below the top stay visible while the top is one of them (or
	-- the default tool); below any other tool they are shelved, as in vanilla.
	---@param entry uo.gui.tool_stack.Entry
	---@param desired? uo.gui.tool_stack.Entry
	---@return boolean
	local function shouldShelve(entry, desired)
		if not (is_window_tool(entry) or is_entity_window(entry)) then return true end
		return not (desired == nil or is_default(desired) or is_window_tool(desired) or is_entity_window(desired))
	end

	---@param entry uo.gui.tool_stack.Entry
	---@param shelved boolean
	local function setShelved(entry, shelved)
		if entry.ctx.shelved == shelved then return end
		entry.ctx.shelved = shelved
		local handler = entry.toolDef.shelve
		if handler then handler(entry.ctx, entry.params, shelved) end
	end

	---@param newStack uo.gui.tool_stack.Entry[]
	local function shelveNonTop(newStack)
		local desired = newStack[#newStack]
		for _i, entry in ipairs(newStack) do
			if entry ~= desired then setShelved(entry, shouldShelve(entry, desired)) end
		end
		if desired then setShelved(desired, false) end
	end

	---@param toolDef builtin.ToolDefinition
	---@param toolKey string
	local function pop(toolDef, toolKey)
		stack:transform(function(curStack)
			local newStack, removed = copyToolStackExcept(curStack, toolDef, toolKey)
			if removed and (removed.toolDef == params.defaultTool and removed.key == params.defaultToolKey) then
				table.insert(newStack, 1, removed)
				shelveNonTop(newStack)
			else
				shelveNonTop(newStack)
				if removed then notify_pop(removed) end
				if removed and removed.toolDef.pop then
					removed.toolDef.pop(removed.ctx, removed.params)
				end
				if removed then
					dropChildIds:get()[removed.ctx.localKey] = true
					removed.ctx.setActionFn(nil, nil)
				end
			end
			updateTop(newStack)
			return newStack
		end)
	end

	local debugUpdate = react.useState(0)
	---@param toolDef builtin.ToolDefinition
	---@param key string
	---@param old? uo.gui.tool_stack.Entry
	---@return uo.gui.tool_stack.Context
	local function makeContext(toolDef, key, old)
		local localKey = toolDef.name .. "/" .. tostring(key)
		-- one table literal (vanilla assigns the three functions after it), so it has all the fields
		---@type uo.gui.tool_stack.Context
		local result
		result = {
			shelved = false,
			key2 = old and old.ctx.key2 or nil,
			localKey = localKey,
			propagateActionFn = (old and old.propagateActionFn) or function()
				dropChildIds:get()[localKey] = true
			end,
			setActionFn = function(actionFn, key2)
				if params.showDebugVisualization and key2 ~= result.key2 then
					debugUpdate:transform(function(cur) return cur + 1 end)
				end
				result.actionFn = actionFn
				result.key2 = key2
				result.propagateActionFn(actionFn, key2)
			end,
			popSelf = function() pop(toolDef, key) end,
			setVariantOverride = function(variant) result.variantOverride = variant end,
		}
		return result
	end

	---@param toolDef builtin.ToolDefinition
	---@param toolKey string
	---@param toolParams any the tool's params, whatever the caller passes
	local function push(toolDef, toolKey, toolParams)
		stack:transform(function(curStack)
			local newStack, old = copyToolStackExcept(curStack, toolDef, toolKey)
			newStack[#newStack + 1] = { toolDef = toolDef, key = toolKey, params = toolParams,
				ctx = makeContext(toolDef, toolKey, old) }
			shelveNonTop(newStack)
			local entry = newStack[#newStack]
			if entry.toolDef.push then entry.toolDef.push(entry.ctx, entry.params) end
			updateTop(newStack)
			return newStack
		end)
	end

	-- UIO: window tools always survive; entity windows survive when `keep_entity_windows` is set.
	---@param keep_entity_windows boolean
	local function clear(keep_entity_windows)
		---@param curStack uo.gui.tool_stack.Entry[]
		---@return uo.gui.tool_stack.Entry[]
		stack:transform(function(curStack)
			---@type uo.gui.tool_stack.Entry[]
			local newStack = {}
			for _i, entry in ipairs(curStack) do
				if is_default(entry) or is_window_tool(entry) or (keep_entity_windows and is_entity_window(entry)) then
					newStack[#newStack + 1] = entry
				else
					notify_pop(entry)
					if entry.toolDef.pop then entry.toolDef.pop(entry.ctx, entry.params) end
					dropChildIds:get()[entry.ctx.localKey] = true
					entry.ctx.setActionFn(nil, nil)
				end
			end
			shelveNonTop(newStack)
			updateTop(newStack)
			return newStack
		end)
	end

	react.onMount(function()
		if params.defaultTool then push(params.defaultTool, params.defaultToolKey, params.defaultToolParam) end
	end)

	---@type builtin.ToolStackAPI
	local stack_api = {
		push = function(toolDef, toolKey, toolParams, allowStacking)
			if allowStacking then
				push(toolDef, toolKey, toolParams)
			else
				clear(WINDOW_TOOLS[toolDef and toolDef.name] == true) -- UIO: opening a window tool keeps entity windows
				push(toolDef, toolKey, toolParams)
			end
		end,
		pop = pop,
		clear = function() clear(false) end,
		setActionsDisabled = function(block)
			if block then
				getRendererComponentApi().setActiveOwnerOverride(nil)
			else
				getRendererComponentApi().setActiveOwnerOverride(false)
			end
		end,
		getActiveTool = function()
			local tool = top:get() or nil
			if not tool then return nil, nil end
			local toolDef = tool.toolDef
			local variant = tool.ctx.variantOverride
				or toolDef.getActiveVariant and tool.toolDef.getActiveVariant(tool.ctx, tool.params) or nil
			return toolDef, variant
		end,
	}
	react.provideApi(stack_api)

	---@type react.TreeNodeId[]
	local children = {}
	local numEntries = #stack:old()
	-- reverse order, so the top is created last (its push handler runs last)
	for i = numEntries, 1, -1 do
		local entry = stack:old()[i]
		local discardNodeIdentity = entry.ctx.discardNodeIdentity or dropChildIds:get()[entry.ctx.localKey]
		entry.ctx.discardNodeIdentity = false
		children[#children + 1] = ToolStackEntryWrap{
			meta = { localKey = entry.ctx.localKey, discardNodeIdentity = discardNodeIdentity,
				disableFocusableRecursive = true },
			ctx = entry.ctx,
			rendererComponent = params.rendererComponent,
		}
	end
	dropChildIds:set({})
	react.setMouseTransparent(true)
	if params.showDebugVisualization then
		children[#children + 1] = builtin.TextView{ text = "Tool stack (debug, UI Overhaul)" }
		for i = numEntries, 1, -1 do
			local entry = stack:old()[i]
			children[#children + 1] = builtin.TextView{
				text = (entry.ctx.shelved and "[SHELVED] " or "") .. entry.toolDef.name .. " - " .. tostring(entry.key),
			}
		end
	end
	return builtin.BoxLayout{ orientation = builtin.type.Orientation.Vertical, children = children }
end

--- Marked failed once rendering failed: the vanilla tool stack is used for the rest of the session.
-- Never per render: the stack's state (the open tools) lives in the shown recipe, so every switch
-- closes them.
tool_stack.switch = fallback.switch("tool stack")

-- The game holds a ref to this node (game.tl) and pushes and pops tools through its api, so the node
-- provides the api of the stack it shows, and keeps the vanilla stack's own settings.
local Replacement = fallback.replacement(tool_stack.switch, "ToolStack", render, builtin.ToolStack, {
	api = { "push", "pop", "clear", "setActionsDisabled", "getActiveTool" },
	internals = function()
		react.setName("ToolStack")
		react.setDisableFocusable(true)
		react.setMouseTransparent(true)
	end,
})

--- Called from the react-replacement-config before the UI starts.
---@param replacement_api react.ReplacementApi
function tool_stack.install(replacement_api)
	replacement_api.ReplaceRecipe(builtin.ToolStack, Replacement)
end

return tool_stack
