--- Every window with a title bar and a close button (entity windows, Statistics, Finances, Company,
-- the vehicle store, layers, the notification log, mods' windows ...) can be minimized: a
-- button in the title bar, in the design of the title bar's other buttons (pin,
-- locate), folds the window to its title bar; a second click
-- unfolds it. The content stays mounted while folded (tabs, open sections and scroll positions are
-- kept) and the window keeps its place. A window that is closed opens unfolded next time.
--
-- The module field builtin.Window, which base recipes look up when they render, is wrapped:
--   * header: the engine draws the window's header slot in the title bar, but before the title, so
--     a button there would sit left of the title and cut long titles short. The slot therefore holds
--     the whole title row (UioWindowHeader): the rename button of a renamable window, the title (or
--     the rename text field) and the minimize button, right-aligned before the title bar's own
--     buttons (locate, pin, close; the engine places the header before them). The engine shows the
--     pin button only while the mouse is over the window, and everything right-aligned before it
--     moves left by the pin's width then (observed in game): a rename button there moved away under
--     the cursor as it came in, and the minimize button took the click. At the left edge, before the
--     title, the rename button stays where it is. The title fills the row and is cut short where it
--     is long; at its natural width, with the rename button after it, a long title ran over the title
--     bar's buttons (observed in game). The engine's title and rename button are switched off (class
--     uio-minimizable, titleEditable = false);
--   * content: wrapped in UioMinimizable, whose component is hidden by id while minimized
--     (api.gui.byId.setVisible; it also carries the class uio-folded);
--   * a window built by a wrapper recipe of builtin.Window (Finances, Company, Statistics ...) also
--     gets the class uio-window-folded while minimized, so the CSS can drop the fixed height some of
--     them have. Such a recipe returns exactly one window on every render (react.lua checks it), so
--     the fold state can be declared there as hooks of that recipe; elsewhere it can not.
-- The field is replaced through builtin_wraps.lua, which keeps window recipes registered later
-- (react.RegisterWrapperRecipe) on the base builtin; without that the game crashes when such a
-- window opens (observed in game). The Line Manager has no title bar (a compact window: only the
-- engine's round close button at its corner), so it gets a title row of its own at the top of its
-- content, with its name (the game's term) and the minimize button; folded, only that row stays.
-- Other compact windows, windows without a close button, with a header of their own, dialogs and
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
-- compact windows (no title bar) that get a title row of their own, by their id: the Line Manager
-- (manager_window.tl, managerToolWindowId)
local COMPACT_IDS = { ["menu.management"] = true }

local minimized = {} ---@type table<string, true?> window key -> true while minimized
local mounted = {} ---@type table<string, integer?> window key -> open windows with that key
local instances = 0 -- windows keyed by instance so far

local report = guard.reporter("minimize: ")

--- Whether a window's parameters get the minimize button.
---@param p any what the window builtin got first: its params, or a ref, or anything a mod passes
---@return boolean
function minimize.eligible(p)
	if type(p) ~= "table" or p.content == nil or p.header ~= nil then return false end
	if p.closable ~= true or SKIPPED_TOOLS[p.tool or ""] then return false end
	local class = p.meta and p.meta.class ---@type any whatever a mod passes; checked below
	if type(class) == "string" then
		for _i, skipped in ipairs(SKIPPED_CLASSES) do
			if class:find(skipped, 1, true) then return false end
		end
	end
	if p.compact then return COMPACT_IDS[p.id or ""] == true end
	return type(p.title) == "string" and p.title ~= ""
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

-- testbench: where a rendered node lies on the screen, in pixels ("left,top-right,bottom"), and its
-- centre; nil where it is not rendered
---@param ref react.RefWrap
---@return string?, integer?, integer?
local function pixels_of(ref)
	local node = ref:get()
	if not node then return nil end
	local screen = api.gui.camera.getSize()
	local top_left, bottom_right = node:getPosition(0, 0), node:getPosition(1, 1)
	local l, t = top_left.x * screen.x, top_left.y * screen.y
	local r, b = bottom_right.x * screen.x, bottom_right.y * screen.y
	return string.format("%.0f,%.0f-%.0f,%.0f", l, t, r, b), math.floor((l + r) / 2 + 0.5), math.floor((t + b) / 2 + 0.5)
end

---The node refs of the title row.
---@class uo.minimize.HeaderRefs
---@field field react.RefWrap the rename text field
---@field rename react.RefWrap
---@field minimize react.RefWrap

--- The title row's content; `editing` is the rename state.
---@param params uo.minimize.WindowHeaderParams
---@param folded boolean
---@param editing react.State<boolean>
---@param focus_pending react.Ref<boolean>
---@param refs uo.minimize.HeaderRefs
---@return react.TreeNodeId
local function render_header(params, folded, editing, focus_pending, refs)
	local title ---@type react.TreeNodeId
	if params.editable and editing:old() then
		local function stop() editing:set(false) end
		title = builtin.TextInputField(react.ref(refs.field), {
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
	local children = {} ---@type react.TreeNodeId[]
	if params.editable then
		-- before the title, at the left edge: it keeps its place when the engine shows the pin button
		children[1] = builtin.Button(react.ref(refs.rename), {
			meta = { class = "rename, uio-window-rename", tooltip = _("Rename") },
			content = builtin.ImageView{ path = ICON_RENAME, scaling = builtin.type.ImageViewScaling.AutoFit },
			onClick = function()
				focus_pending:set(true)
				editing:set(true)
			end,
		})
	end
	children[#children + 1] = title
	children[#children + 1] = builtin.Button(react.ref(refs.minimize), {
		-- no component id: a window can be rendered twice, and ids must be unique
		meta = { class = "uio-minimize",
			tooltip = folded and _("Restore") or _("Minimize") },
		content = builtin.ImageView{ path = folded and ICON_RESTORE or ICON_MINIMIZE,
			scaling = builtin.type.ImageViewScaling.AutoFit },
		onClick = function() minimize.toggle(params.key) end,
	})
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
	-- one hook per statement: the order of a table constructor's fields is not fixed
	local field = react.useNodeRef(builtin.TextInputField)
	local rename = react.useNodeRef(builtin.Button)
	local minimize_button = react.useNodeRef(builtin.Button)
	local refs = { field = field, rename = rename, minimize = minimize_button } ---@type uo.minimize.HeaderRefs
	react.onStep(function()
		-- the rename field exists one step after the rename click: give it the keyboard
		if not focus_pending:get() then return end
		local node = refs.field:get()
		if not node then return end
		focus_pending:set(false)
		local ok, err = pcall(function() node:focus() end)
		if not ok then report("rename focus", err) end
	end)
	-- testbench: "uio.debug.header" logs where the title row's buttons are and its state; with
	-- { click = "rename" } it also asks run.sh for a real click on the rename button's centre (the
	-- testbench runs in another Lua state and reads neither this module nor the node positions)
	react.onEvent("uio.debug.header", function(_e, param)
		local ok, err = pcall(function()
			local at, x, y = pixels_of(refs.rename)
			debugPrint(string.format("[ui_overhaul] title row %q: rename %s minimize %s editing=%s folded=%s",
				tostring(params.title), tostring(at), tostring((pixels_of(refs.minimize))),
				tostring(editing:old() == true), tostring(folded)))
			if type(param) == "table" and param.click == "rename" and x and y then
				debugPrint(string.format("[testbench] CLICK %d %d", x, y))
			end
		end)
		if not ok then report("debug", err) end
	end)
	local ok, node = pcall(render_header, params, folded, editing, focus_pending, refs)
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
---@param class? string nil: the meta copied as it is
---@return react.Meta
local function with_class(meta, class)
	local copy = meta and guard.shallow_copy(meta) or {} ---@type react.Meta
	if class == nil then return copy end
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
			local content = Minimizable{ key = key, id = "uio.minimize." .. id, content = window_params.content }
			if window_params.compact then
				-- no title bar: the title row goes above the content, and stays when the content folds
				copy.content = builtin.BoxLayout{
					orientation = builtin.type.Orientation.Vertical,
					children = {
						-- a Component's layout must be a layout builtin, not a recipe: the engine crashes
						-- natively otherwise ("Item of Component must be a layout", observed in game)
						builtin.Component{
							meta = { class = "uio-compact-header" },
							layout = builtin.BoxLayout{ children = {
								WindowHeader{ key = key, title = _("Line Manager"), editable = false },
							} },
						},
						content,
					},
				}
				copy.meta = with_class(window_params.meta, folded and "uio-window-folded" or nil)
				return copy
			end
			copy.content = content
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
