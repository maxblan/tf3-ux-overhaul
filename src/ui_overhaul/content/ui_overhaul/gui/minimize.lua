--- Every window with a title bar and a close button (entity windows, Statistics, Finances, Company,
-- the vehicle store, layers, the notification log, mods' windows ...) can be minimized: a round
-- button in the title bar, in the design of the close button (the game's
-- fake-builtin-window-close-button style), folds the window to its title bar; a second click
-- unfolds it. The content stays mounted while folded (tabs, open sections and scroll positions are
-- kept) and the window keeps its place. A window that is closed opens unfolded next time.
--
-- The module field builtin.Window, which base recipes look up when they render, is wrapped:
--   * header: the engine draws the window's header slot in the title bar, but before the title, so
--     a button there would sit left of the title and cut long titles short. The slot therefore holds
--     the whole title row (UioWindowHeader): the title, the rename button of a renamable window
--     with its own text field, and the minimize button, right-aligned before the title bar's own
--     buttons (locate, pin, close; the engine places the header before them). The engine's title
--     and rename button are switched off (class uio-minimizable, titleEditable = false);
--   * content: wrapped in UioMinimizable, whose component is hidden by id while minimized
--     (api.gui.byId.setVisible; it also carries the class uio-folded);
--   * a window built by a wrapper recipe of builtin.Window (Finances, Company, Statistics ...) also
--     gets the class uio-window-folded while minimized, so the CSS can drop the fixed height some of
--     them have. Such a recipe returns exactly one window on every render (react.lua checks it), so
--     the fold state can be declared there as hooks of that recipe; elsewhere it can not.
-- The field is replaced through builtin_wraps.lua, which keeps window recipes registered later
-- (react.RegisterWrapperRecipe) on the base builtin; without that the game crashes when such a
-- window opens (observed in game). Windows without a title bar
-- (compact: the Line Manager), without a close button, with a header of their own, dialogs and
-- popovers stay as they are.
-- Installed by installer.lua.
-- @module ui_overhaul.gui.minimize
local builtin = require("::/gui/main/builtin.lua")
local react = require("::/gui/main/react.lua")
local builtin_wraps = require("ui_overhaul_1::/ui_overhaul/gui/builtin_wraps.lua")
local guard = require("ui_overhaul_1::/ui_overhaul/gui/guard.lua")

---@class uo.gui.minimize
local minimize = {}

local EVENT = "uio.minimize"
local ICON_MINIMIZE = "gui/builtin/window/icons/symbol_minimize_18.tga" -- the game's own (statistics.tl)
local ICON_RESTORE = "gui/builtin/window/icons/symbol_maximize_18.tga"
local ICON_RENAME = "gui/builtin/window/icons/symbol_pencil_18.tga"
local SKIPPED_CLASSES = { "popover", "dialog", "no-close-button", "construct-" }
local SKIPPED_TOOLS = { pause = true }

local minimized = {} ---@type table<string, true?> window key -> true while minimized
local mounted = {} ---@type table<string, integer?> window key -> open windows with that key
local instances = 0 -- windows keyed by instance so far

local report = guard.reporter("minimize: ")

--- Whether a window's parameters get the minimize button.
---@param p any what the window builtin got first: its params, or a ref, or anything a mod passes
---@return boolean
function minimize.eligible(p)
	if type(p) ~= "table" or p.content == nil or p.header ~= nil or p.compact then return false end
	if p.closable ~= true or SKIPPED_TOOLS[p.tool or ""] then return false end
	if type(p.title) ~= "string" or p.title == "" then return false end
	local class = p.meta and p.meta.class ---@type any whatever a mod passes; checked below
	if type(class) == "string" then
		for _i, skipped in ipairs(SKIPPED_CLASSES) do
			if class:find(skipped, 1, true) then return false end
		end
	end
	return true
end

--- A key that tells the window apart from the others open at the same time, for windows that are
-- not built by a window wrapper recipe (those are keyed per instance). Two such windows with the
-- same title and neither id nor tool share it.
---@param p builtin.WindowParam
---@return string
function minimize.key(p)
	if type(p.id) == "string" and p.id ~= "" then return "id:" .. p.id end
	if type(p.tool) == "string" and p.tool ~= "" and p.tool ~= "entityWindow" then return "tool:" .. p.tool end
	return "title:" .. tostring(p.title)
end

--- Minimizes or restores the window `key`.
---@param key string
function minimize.toggle(key)
	minimized[key] = not minimized[key] or nil
	react.fireEvent(nil, EVENT, key)
end

--- Whether window `key` is minimized.
---@param key string
---@return boolean
function minimize.is_minimized(key)
	return minimized[key] == true
end

-- Re-renders the caller when window `key` folds or unfolds; returns whether it is folded.
---@param key string
---@return boolean
local function use_folded(key)
	local state = react.useState(minimized[key] == true)
	react.onEvent(EVENT, function(_e, changed)
		if changed == key then state:set(minimized[changed] == true) end
	end)
	return state:old()
end

---@class uo.minimize.MinimizableParams: react.Param
---@field key string
---@field id string component id of the content: "uio.minimize." and the window's id, or its key
---@field content? react.TreeNodeId

---@param params uo.minimize.MinimizableParams
---@return react.TreeNodeId
local Minimizable = react.RegisterRecipe("UioMinimizable", function(params)
	local key = params.key
	local folded = use_folded(key)
	-- a class change does not hide a component that is already shown (observed in game): its
	-- visibility is set by id, once the component exists, whenever the state changes
	local applied = react.useRef(false)
	react.onStep(function()
		if applied:get() == folded then return end
		local ok, err = pcall(api.gui.byId.setVisible, params.id, not folded)
		if not ok then report("visibility", err) end
		applied:set(folded)
	end)
	-- testbench: "uio.debug.minimize_all" folds or unfolds every window
	react.onEvent("uio.debug.minimize_all", function() minimize.toggle(key) end)
	react.onMount(function() mounted[key] = (mounted[key] or 0) + 1 end)
	react.onUnmount(function()
		local open = (mounted[key] or 1) - 1
		mounted[key] = open > 0 and open or nil
		-- a closed window opens unfolded next time; another open window with the same key keeps its state
		if open <= 0 then minimized[key] = nil end
	end)
	-- class and id on a component: on a layout they have no effect (observed in game); the recipe's
	-- root stays a layout. The id is the handle for setVisible above and for the testbench.
	return builtin.BoxLayout{ children = {
		builtin.Component{
			meta = { class = folded and "uio-folded" or "uio-unfolded", id = params.id },
			layout = builtin.BoxLayout{ orientation = builtin.type.Orientation.Vertical, children = { params.content } },
		},
	} }
end)

---@class uo.minimize.WindowHeaderParams: react.Param
---@field key string
---@field title string
---@field editable boolean the window's title can be renamed
---@field onTitleChange? fun(title: string)
---@field emptyNameAllowed? boolean as the window's own parameter: nil means allowed

--- The title row's content; `editing` is the rename state, `field` the text field's node ref.
---@param params uo.minimize.WindowHeaderParams
---@param folded boolean
---@param editing react.State<boolean>
---@param focus_pending react.Ref<boolean>
---@param field react.RefWrap
---@return react.TreeNodeId
local function render_header(params, folded, editing, focus_pending, field)
	local title ---@type react.TreeNodeId
	if params.editable and editing:old() then
		local function stop() editing:set(false) end
		title = builtin.TextInputField(react.ref(field), {
			meta = { class = "font-scale-title-2, uio-window-title" },
			value = params.title,
			acceptOnFocusLoss = true,
			focusOnStartEditing = true,
			onValueChange = function(value)
				stop()
				if value == params.title or (value == "" and params.emptyNameAllowed == false) then return end
				if type(params.onTitleChange) ~= "function" then return end
				local ok, err = pcall(params.onTitleChange, value)
				if not ok then report("rename", err) end
			end,
			onCancel = stop,
			onEditingModeChange = function(active) if not active then stop() end end,
		})
	else
		title = builtin.TextView{
			meta = { class = "font-scale-title-2, uio-window-title" },
			text = params.title,
			tooltipWhenClipped = params.title,
		}
	end
	local children = { title } ---@type react.TreeNodeId[]
	if params.editable then
		children[#children + 1] = builtin.Button{
			meta = { class = "rename, uio-window-rename", tooltip = _("Rename") },
			content = builtin.ImageView{ path = ICON_RENAME, scaling = builtin.type.ImageViewScaling.AutoFit },
			onClick = function()
				focus_pending:set(true)
				editing:set(true)
			end,
		}
	end
	children[#children + 1] = builtin.Button{
		-- no component id: a window can be rendered twice, and ids must be unique
		meta = { class = "fake-builtin-window-close-button, uio-minimize",
			tooltip = folded and _("Restore") or _("Minimize") },
		content = builtin.ImageView{ path = folded and ICON_RESTORE or ICON_MINIMIZE,
			scaling = builtin.type.ImageViewScaling.AutoFit },
		onClick = function() minimize.toggle(params.key) end,
	}
	return builtin.BoxLayout{
		meta = { class = "uio-window-header" },
		orientation = builtin.type.Orientation.Horizontal,
		children = children,
	}
end

---@param params uo.minimize.WindowHeaderParams
---@return react.TreeNodeId
local WindowHeader = react.RegisterRecipe("UioWindowHeader", function(params)
	-- the hooks first, the same on every render
	local folded = use_folded(params.key)
	local editing = react.useState(false)
	local focus_pending = react.useRef(false)
	local field = react.useNodeRef(builtin.TextInputField)
	react.onStep(function()
		-- the rename field exists one step after the rename click: give it the keyboard
		if not focus_pending:get() then return end
		local node = field:get()
		if not node then return end
		focus_pending:set(false)
		local ok, err = pcall(function() node:focus() end)
		if not ok then report("rename focus", err) end
	end)
	local ok, node = pcall(render_header, params, folded, editing, focus_pending, field)
	if ok then return node end
	report("header", node)
	-- the engine's title is hidden on this window: keep at least the title
	return builtin.TextView{ meta = { class = "font-scale-title-2, uio-window-title" }, text = tostring(params.title) }
end)

-- Whether the recipe now rendering is a wrapper recipe of builtin.Window: it returns exactly one
-- window on every render (react.lua checks its result), so hooks declared while it builds the window
-- keep their position.
---@return boolean
local function in_window_wrapper()
	if type(_react) ~= "table" or type(react.getCurrentRecipeId) ~= "function" then return false end
	local ok, id = pcall(react.getCurrentRecipeId)
	if not ok or id == nil then return false end
	local metas, ids = _react.recipeMetas, _react.builtin
	local meta = type(metas) == "table" and metas[id] or nil
	return meta ~= nil and type(ids) == "table" and ids.Window ~= nil and meta.innerRecipeId == ids.Window
end

-- `class` appended to the window's own classes (a copy of its meta).
---@param meta? react.Meta
---@param class string
---@return react.Meta
local function with_class(meta, class)
	local copy = meta and guard.shallow_copy(meta) or {} ---@type react.Meta
	local own = copy.class
	copy.class = (type(own) == "string" and own ~= "") and own .. ", " .. class or class
	return copy
end

---@param base function builtin.Window, or another mod's wrap of it
---@return function
local function wrap_window(base)
	---@param p any what the window builtin gets first: its params, or a ref
	---@param ... any the rest, passed on unchanged
	---@return react.TreeNodeId
	return function(p, ...)
		if select("#", ...) ~= 0 then return base(p, ...) end
		-- the hooks first, in a window wrapper recipe only, and whether or not the window is eligible
		local instance_key, folded ---@type string?, boolean
		if in_window_wrapper() then
			local instance = react.useRef(nil) ---@type react.Ref<string?>
			if instance:get() == nil then
				instances = instances + 1
				instance:set("instance:" .. instances)
			end
			instance_key = instance:get()
			folded = use_folded(instance_key --[[@as string]])
		end
		local ok, eligible = pcall(minimize.eligible, p)
		if not ok then report("eligible", eligible) end
		if not (ok and eligible) then return base(p) end
		local window_params = p ---@type builtin.WindowParam eligible() checked the table
		local built, window = pcall(function()
			local key = instance_key or minimize.key(window_params)
			if instance_key == nil then folded = minimized[key] == true end
			local copy = guard.shallow_copy(window_params) ---@type builtin.WindowParam
			local id = type(window_params.id) == "string" and window_params.id ~= "" and window_params.id or key
			copy.content = Minimizable{ key = key, id = "uio.minimize." .. id, content = window_params.content }
			copy.header = WindowHeader{
				key = key,
				title = window_params.title or "",
				editable = window_params.titleEditable == true,
				onTitleChange = window_params.onTitleChange,
				emptyNameAllowed = window_params.emptyNameAllowed,
			}
			copy.titleEditable = false -- the header brings its own rename button and field
			copy.meta = with_class(window_params.meta,
				folded and "uio-minimizable, uio-window-folded" or "uio-minimizable")
			return copy
		end)
		if built then return base(window) end
		report("window", window)
		return base(p)
	end
end

--- Called by installer.lua before the UI starts.
---@param _replacement_api react.ReplacementApi
function minimize.install(_replacement_api)
	-- builtin_wraps also keeps window recipes registered later on the base builtin
	builtin_wraps.wrap("Window", wrap_window)
	debugPrint("[ui_overhaul] window minimize installed")
end

return minimize
