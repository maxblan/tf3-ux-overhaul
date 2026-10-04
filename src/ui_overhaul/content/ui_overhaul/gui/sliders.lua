--- Sliders on the gameplay screens:
--   * the mouse wheel moves a slider under the cursor: to the next snap point, or one step while
--     the game's precision key is held
--   * snap points every few percent of the range (core/slider_snap.lua), drawn as ticks; a dragged
--     slider sticks to one when it comes close, and the precision key turns that off
--   * a value can be typed: double-click a slider, or click the value next to a construction
--     slider (a number spin box, as the Line Manager's wait times have)
-- Construction sliders (and all other script parameters) move through a list of values, which their
-- label shows (height "2.5 m", incline "3 %"); a typed value picks the entry whose label is nearest,
-- so it is always one the game offers. Evenly spaced lists (incline in 1 % steps, bend in 0.05
-- steps) get snap points every few positions, anchored at the neutral value (0 % incline, no bend),
-- drawn as ticks; the wheel moves from one to the next.
--
-- Two hooks, both installed before the UI starts (sliders.script.lua):
--   * the module field builtin.Slider is wrapped: base recipes look it up when they render, so every
--     slider is reached. The wrapper renders the base slider inside the recipe UioSlider, which adds
--     the wheel and typing; the base slider keeps its parameters and classes.
--   * script_param_util.buildScriptParamCompSimple is wrapped for sliders: the slider row is this
--     module's Lua copy of the base recipe ScriptParamSliderAndText (registered under its name, so
--     the base stylesheet applies), with the value label as a button to type a value.
-- The settings menu keeps vanilla sliders (design rule: gameplay screens only). Any error falls back
-- to the plain base slider.
-- @module ui_overhaul.gui.sliders
local builtin = require("::/gui/main/builtin.lua")
local react = require("::/gui/main/react.lua")
local script_param_util = require("::/gui/main/script_param_util.tl")
local lang_util = require("::/scripts/lang_util.tl")
local slider_snap = require("/ui_overhaul/core/slider_snap.lua")
local builtin_wraps = require("ui_overhaul_1::/ui_overhaul/gui/builtin_wraps.lua")

local sliders = {}

---A builtin.Slider call's params as this module reads and writes them. Lua 5.2 has one number type:
---the base's integer fields (builtin.SliderParam) are numbers here, and what this module sets is on
---the slider's grid.
---@class uo.sliders.SliderParam: react.Param
---@field min? number
---@field max? number
---@field step? number
---@field pageStep? number
---@field horizontal? boolean
---@field disableGamepadNavigation? boolean
---@field withTicks? boolean
---@field initialValue? number
---@field value? number
---@field onValueChange? fun(value: number)
---@field uioPlain? boolean keeps the plain base slider

---@class uo.sliders.UioSliderParams
---@field p uo.sliders.SliderParam

-- ScriptParamSliderAndTextParam of script_param_util.tl.
---@class uo.sliders.ParamSliderParams: react.Param
---@field scriptParam game.gui.main.script_param_util.ParamForUi
---@field currentValue number
---@field onValueChange fun(value: number)
---@field disableGamepadNavigation? boolean
---@field allowCoalesce? boolean


-- Recipes whose sliders stay vanilla: the in-game settings menu.
---@type table<string, boolean>
local VANILLA_IN = { SettingsPage = true }

---@type table<string, boolean>
local reported = {}
---@param key string
---@param err any the pcall error, any value
local function report(key, err)
	if reported[key] then return end
	reported[key] = true
	debugPrint("[ui_overhaul] sliders: ", key, ": ", tostring(err))
end

---@return boolean
local function precise()
	local ok, active = pcall(api.gui.inputAction.modifierOnlyActionIsActive, "IA_PRECISION_MODE")
	return ok and active or false
end

---@param evt Gui.Mouse.Event
---@return integer
local function wheel_dir(evt)
	return evt.yrel > 0 and 1 or -1
end

---@generic T: table
---@param t T
---@return T
local function copy(t)
	-- keys and values of any type are copied as they are
	---@type table<any, any>, table<any, any>
	local result, source = {}, t
	for k, v in pairs(source) do result[k] = v end
	return result
end

---@return number?
local function clock()
	local ok, t = pcall(os.clock)
	return ok and t or nil
end

-- The wheel moves a slider only when the player is pointing at it: the mouse moved over it in the
-- last moments, or the wheel already turned it just before. A panel that scrolls a slider under a
-- resting cursor keeps scrolling instead of changing the slider.
local HOVER_SECONDS, WHEEL_SECONDS = 1.5, 0.5

---@return uo.sliders.WheelIntent
local function use_wheel_intent()
	---@type react.Ref<number?>
	local last_move = react.useRef(nil)
	---@type react.Ref<number?>
	local last_wheel = react.useRef(nil)
	---@class uo.sliders.WheelIntent
	local intent = {}
	-- the mouse moved over the slider
	function intent.moved() last_move:set(clock()) end
	---@return boolean
	function intent.allows_wheel()
		local now = clock()
		if not now then return true end
		local ok = (last_move:get() and now - last_move:get() <= HOVER_SECONDS)
			or (last_wheel:get() and now - last_wheel:get() <= WHEEL_SECONDS)
		if ok then last_wheel:set(now) end
		return ok and true or false
	end
	return intent
end

-- After a drag that ended next to a snap point, the base slider's thumb rests where the mouse let go
-- while the value is the snap point (its value did not change, so nothing re-rendered it). The
-- slider is then mounted anew on release, which puts the thumb on the value.
---@return uo.sliders.ThumbSync
local function use_thumb_sync()
	local key = react.useState(0)
	local pending = react.useRef(false)
	---@class uo.sliders.ThumbSync
	local sync = {}
	-- a dragged value `raw` was set to `snapped`
	---@param raw number
	---@param snapped number
	function sync.after(raw, snapped) pending:set(raw ~= snapped) end
	function sync.released()
		if pending:get() then
			pending:set(false)
			key:set(key:old() + 1)
		end
	end
	-- the slider's localKey
	---@return string
	function sync.key() return "uio-slider-" .. tostring(key:old()) end
	return sync
end

-- The base Slider (set by install), and the wrapper that replaces it.
---@type fun(p: uo.sliders.SliderParam, ...: any): react.TreeNodeId
local base_slider

-- Any slider ------------------------------------------------------------------------------------

---@param params uo.sliders.UioSliderParams
---@return react.TreeNodeId
local function render_slider(params)
	local p = params.p
	-- The hooks come first, before anything that can fail: UioSlider shows the base slider after a
	-- failed render, and a recipe has to declare the same hooks on every render (fallback.lua).
	-- Sliders that only set initialValue keep their own value; here it is held so the wheel can
	-- move them too.
	local own = react.useState(p.initialValue or p.value or p.min or 0)
	local editing = react.useState(false)
	local intent = use_wheel_intent()
	local sync = use_thumb_sync()
	-- set below; the mouse listener is set with the hooks and reads them when an event comes
	---@type number, number, number, number?, number, number, fun(v: number)
	local min, max, step, detent, anchor, value, commit

	react.onMouseEvent(function(evt)
		local ok, consumed = pcall(function()
			local types = api.gui.mouse.Event.Type
			if evt.type == types.Moved then intent.moved() end
			if evt.type == types.Released and evt.button == 0 then sync.released() end
			if evt.handled then return false end
			if evt.type == types.Wheel and evt.yrel ~= 0 then
				if not intent.allows_wheel() then return false end
				commit(slider_snap.wheel(value, min, max, step, detent, wheel_dir(evt), precise(), anchor))
				return true
			end
			-- typing makes sense where the slider's number is what it shows (not for short lists)
			if evt.type == api.gui.mouse.Event.Type.DoubleClicked and evt.button == 0 and (max - min) / step > 4 then
				editing:set(true)
				return true
			end
			return false
		end)
		if ok then return consumed end
		report("mouse", consumed)
		return false
	end)

	min, max = p.min or 0, p.max or 100
	step = (p.step and p.step > 0) and p.step or 1
	detent = slider_snap.detent(min, max, step)
	anchor = slider_snap.anchor(min, step)
	value = p.value ~= nil and p.value or own:old()

	commit = function(v)
		v = slider_snap.on_grid(v, min, max, step)
		if v == value then return end
		if p.value == nil then own:set(v) end
		if p.onValueChange then p.onValueChange(v) end
	end

	if editing:old() then
		return builtin.BoxLayout{ children = {
			builtin.DoubleSpinBox{
				meta = { class = "uio-slider-input" },
				min = min, max = max, step = step, value = value,
				startInEditMode = true,
				onValueChange = commit,
				onStopEditMode = function() editing:set(false) end,
			},
		} }
	end

	local q = copy(p)
	q.value = value
	q.initialValue = nil
	q.meta = copy(p.meta or {})
	q.meta.localKey = sync.key()
	q.onValueChange = function(raw)
		local v = raw
		if not precise() then v = slider_snap.on_grid(slider_snap.snap(raw, min, max, detent, anchor), min, max, step) end
		sync.after(raw, v)
		commit(v)
	end
	-- the base slider draws ticks from its minimum: only when they fall on the snap points
	if detent and ((min - anchor) % detent) == 0 then
		if q.withTicks == nil then q.withTicks = true end
		if q.pageStep == nil then q.pageStep = detent end
	end
	return builtin.BoxLayout{ children = { base_slider(q) } }
end

---@param params uo.sliders.UioSliderParams
---@return react.TreeNodeId
local UioSlider = react.RegisterRecipe("UioSlider", function(params)
	local ok, node = pcall(render_slider, params)
	if ok then return node end
	report("render", node)
	return builtin.BoxLayout{ children = { base_slider(params.p) } }
end)

--- Whether a builtin.Slider call can get the additions: a plain parameter table with a callback,
-- outside the settings menu. `recipe` is the name of the recipe that is rendering.
---@param args any[] the call's arguments, as base recipes and other mods pass them
---@param recipe string?
---@return boolean
function sliders.enhance(args, recipe)
	if #args ~= 1 or type(args[1]) ~= "table" then return false end
	local p = args[1]
	if type(p.onValueChange) ~= "function" or p.uioPlain then return false end
	return not VANILLA_IN[recipe or ""]
end

---@param ... any the builtin.Slider call's arguments
---@return react.TreeNodeId
local function wrapped_slider(...)
	local args = { ... }
	-- outside a render (a callback, another mod) getCurrentRecipeName asserts: the call stays the base one
	local ok, enhance = pcall(function() return sliders.enhance(args, react.getCurrentRecipeName()) end)
	if ok and enhance then return UioSlider{ p = args[1] } end
	return base_slider(...)
end

-- Script parameters (construction tools and built stations) ----------------------------------------

---@param scriptParam game.gui.main.script_param_util.ParamForUi
---@return integer
local function choices(scriptParam)
	return scriptParam.numbers ~= nil and #scriptParam.numbers or #scriptParam.values
end

---@param scriptParam game.gui.main.script_param_util.ParamForUi
---@param index number a position, 1 to choices(scriptParam)
---@return number
local function value_of(scriptParam, index)
	return scriptParam.numbers ~= nil and scriptParam.numbers[index] or index
end

---@param scriptParam game.gui.main.script_param_util.ParamForUi
---@param value number
---@return integer
local function index_of(scriptParam, value)
	if scriptParam.numbers ~= nil then
		local best, best_distance = 1, math.abs(scriptParam.numbers[1] - value)
		for i = 2, #scriptParam.numbers do
			local distance = math.abs(scriptParam.numbers[i] - value)
			if distance < best_distance then best, best_distance = i, distance end
		end
		return best
	end
	return value >= 1 and math.floor(value) or 1
end

-- The label of a value, as the base slider shows it.
---@param scriptParam game.gui.main.script_param_util.ParamForUi
---@param value number
---@return string
local function label(scriptParam, value)
	if scriptParam.formatValueFn ~= nil then return scriptParam.formatValueFn(value) end
	if scriptParam.values ~= nil then return scriptParam.values[index_of(scriptParam, value)] end
	return lang_util.formatNumber(value, 3)
end

-- Snap points of a value-list slider: detent interval (positions) and anchor position, or nil.
---@param scriptParam game.gui.main.script_param_util.ParamForUi
---@return integer? detent
---@return integer? anchor
local function param_detents(scriptParam)
	local numbers = scriptParam.numbers
	if not numbers or not slider_snap.evenly_spaced(numbers) then return nil end
	local anchor = index_of(scriptParam, 0)
	if math.abs(numbers[anchor]) > math.abs(numbers[2] - numbers[1]) * 0.01 then anchor = 1 end
	local detent = slider_snap.index_detent(#numbers, anchor)
	return detent, anchor
end

---@param param uo.sliders.ParamSliderParams
---@return react.TreeNodeId
local function render_param_slider(param)
	local scriptParam = param.scriptParam
	-- the hooks first, as in render_slider
	---@type react.State<number?>
	local pending = react.useState(nil) -- value while dragging (coalesced: sent on release)
	---@type react.State<number?>
	local shown = react.useState(nil) -- value the label shows while dragging
	local mouse_pressed = react.useRef(false)
	local editing = react.useState(false)
	local intent = use_wheel_intent()
	local sync = use_thumb_sync()
	---@type integer?, integer?
	local detent, anchor -- set below, after the mouse listener
	local current = pending:old() or param.currentValue

	---@param value number
	local function send(value)
		param.onValueChange(value)
		pending:set(nil)
		shown:set(nil)
	end

	react.onMouseEvent(function(evt)
		local ok, consumed = pcall(function()
			if evt.type == api.gui.mouse.Event.Type.Moved then intent.moved() end
			if evt.button == 0 then
				if evt.type == api.gui.mouse.Event.Type.Released then
					mouse_pressed:set(false)
					sync.released()
					local held = pending:old()
					if held ~= nil then
						send(held)
						return true
					end
				elseif evt.type == api.gui.mouse.Event.Type.Pressed then
					mouse_pressed:set(true)
					pending:set(nil)
				end
			end
			if evt.handled then return false end
			if evt.type == api.gui.mouse.Event.Type.Wheel and evt.yrel ~= 0 then
				if not intent.allows_wheel() then return false end
				local dir = wheel_dir(evt)
				---@type number?
				local value
				if detent and not precise() then
					local index = slider_snap.wheel(index_of(scriptParam, param.currentValue), 1, choices(scriptParam), 1,
						detent, dir, false, anchor)
					value = value_of(scriptParam, index)
				elseif scriptParam.stepValueFn ~= nil then
					value = scriptParam.stepValueFn(param.currentValue, dir, precise())
				else
					local index = math.max(1, math.min(choices(scriptParam), index_of(scriptParam, param.currentValue) + dir))
					value = value_of(scriptParam, index)
				end
				if value ~= nil and value ~= param.currentValue then send(value) end
				return true
			end
			if evt.type == api.gui.mouse.Event.Type.DoubleClicked and evt.button == 0 then
				editing:set(true)
				return true
			end
			return false
		end)
		if ok then return consumed end
		report("param mouse", consumed)
		return false
	end)
	detent, anchor = param_detents(scriptParam)

	local value_text = label(scriptParam, shown:old() or current)
	---@type react.TreeNodeId
	local value_node
	if editing:old() then
		-- the number the label shows (in its unit); the typed number picks the nearest label
		value_node = builtin.DoubleSpinBox{
			meta = { class = "uio-slider-input" },
			value = slider_snap.parse_number(value_text) or 0,
			step = 0.5,
			startInEditMode = true,
			onValueChange = function(typed)
				---@type string[]
				local labels = {}
				for i = 1, choices(scriptParam) do labels[i] = label(scriptParam, value_of(scriptParam, i)) end
				local index = slider_snap.nearest_label(labels, tostring(typed))
				if index then send(value_of(scriptParam, index)) end
			end,
			onStopEditMode = function() editing:set(false) end,
		}
	else
		value_node = builtin.Button{
			meta = { class = "uio-slider-value", tooltip = _("Click to type a value") },
			content = builtin.TextView{ meta = { class = "slider-label-right, font-scale-body" }, text = value_text },
			onClick = function() editing:set(true) end,
		}
	end

	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			base_slider{
				meta = { localKey = sync.key() },
				value = index_of(scriptParam, current),
				onValueChange = function(raw)
					local index = raw
					if detent and not precise() then index = slider_snap.snap(raw, 1, choices(scriptParam), detent, anchor) end
					sync.after(raw, index)
					local value = value_of(scriptParam, index)
					if not param.allowCoalesce or not mouse_pressed:get() then
						send(value)
					else
						pending:set(value)
						shown:set(value)
					end
				end,
				min = 1,
				max = choices(scriptParam),
				step = 1,
				pageStep = detent or 10,
				withTicks = detent ~= nil,
				disableGamepadNavigation = param.disableGamepadNavigation,
			},
			value_node,
		},
	}
end

-- Registered under the base name: the base stylesheet sizes it (R::ScriptParamSliderAndText).
-- The plain base slider over the positions of the value list, for a row whose render failed. The data
-- that made it fail may be odd, so nothing here may raise: an unreadable list is a slider of one.
---@param param uo.sliders.ParamSliderParams
---@return react.TreeNodeId
local function plain_param_slider(param)
	local scriptParam = param.scriptParam
	local ok_count, count = pcall(choices, scriptParam)
	local ok_index, index = pcall(index_of, scriptParam, param.currentValue)
	count = ok_count and type(count) == "number" and count >= 1 and count or 1
	index = ok_index and type(index) == "number" and math.max(1, math.min(count, index)) or 1
	return base_slider{
		value = index,
		min = 1, max = count, step = 1,
		onValueChange = function(i)
			local ok, err = pcall(function() param.onValueChange(value_of(scriptParam, i)) end)
			if not ok then report("plain slider", err) end
		end,
	}
end

---@param param uo.sliders.ParamSliderParams
---@return react.TreeNodeId
local ScriptParamSliderAndText = react.RegisterRecipe("ScriptParamSliderAndText", function(param)
	local ok, node = pcall(render_param_slider, param)
	if ok then return node end
	report("param render", node)
	return builtin.BoxLayout{ children = { plain_param_slider(param) } }
end)

-- The slider branch of the base buildScriptParamCompSimple (script_param_util.tl), with this
-- module's slider row; everything else goes to the base function.
---@param original fun(param: game.gui.main.script_param_util.CompSimpleParam, ...: any): react.TreeNodeId
---@return fun(param: game.gui.main.script_param_util.CompSimpleParam, ...: any): react.TreeNodeId
local function wrap_build(original)
	return function(param, ...)
		local scriptParam = param and param.scriptParam
		if not scriptParam or param.compact or scriptParam.uiType ~= api.type.enum.ScriptParamType.Slider then
			return original(param, ...)
		end
		if scriptParam.numbers ~= nil and #scriptParam.numbers == 0 then scriptParam.numbers = nil end
		if choices(scriptParam) < 1 then return original(param, ...) end
		local right = ScriptParamSliderAndText{
			meta = {
				class = "right-parameters, ui-type-" .. tostring(scriptParam.uiType),
				onAttention = param.onHover,
				tag = "scriptParams.rightParameters." .. scriptParam.name,
			},
			scriptParam = scriptParam,
			currentValue = param.currentValue,
			onValueChange = param.onValueChange,
			disableGamepadNavigation = param.disableGamepadNavigation,
			allowCoalesce = scriptParam.allowCoalesce,
		}
		if param.vertical == nil then return right end
		return script_param_util.wrap(scriptParam.name, param.vertical, right, param.addSpacer, param.onHover, nil)
	end
end

--- Called from the react-replacement-config before the UI starts.
---@param _replacement_api react.ReplacementApi
function sliders.install(_replacement_api)
	local build = script_param_util.buildScriptParamCompSimple
	builtin_wraps.wrap("Slider", function(base)
		base_slider = base
		return wrapped_slider
	end)
	if type(build) == "function" and type(script_param_util.wrap) == "function" then
		script_param_util.buildScriptParamCompSimple = wrap_build(build)
	end
	debugPrint("[ui_overhaul] slider wheel, snap points and typing installed")
end

return sliders
