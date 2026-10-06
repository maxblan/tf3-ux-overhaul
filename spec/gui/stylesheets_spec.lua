-- The mod's stylesheets (*.css.lua) and the window classes they select by (styles.lua). The game runs
-- the stylesheets once, before it knows the settings or the load order (observed in game), so every
-- rule must select something only this mod puts there while the feature is shown: a uio- class or an
-- R::Uio recipe somewhere in the selector.
_G.debugPrint = _G.debugPrint or function() end

local builtin = { Window = function(...) return { window = table.pack(...) } end }
package.loaded["::/gui/main/builtin.lua"] = builtin
package.loaded["::/gui/main/react.lua"] = package.loaded["::/gui/main/react.lua"] or {}
local styles = require("ui_overhaul_1::/ui_overhaul/gui/styles.lua")

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

-- Any colour of the game's colour tables: a stand-in table.
local colours = setmetatable({}, { __index = function() return { 1, 1, 1, 1 } end })

--- The selectors of every rule of every stylesheet, each part of a selector list on its own, with the
-- game's stylesheet helpers and colour tables stood in.
---@return { file: string, selector: string }[]
local function selectors()
	local loaded = package.loaded ---@type table<string, any>
	local saved = { loaded["::/gui/main/stylesheetutil.lua"], loaded["::/gui/main/color_util.tl"] }
	loaded["::/gui/main/stylesheetutil.lua"] = {
		---@param result { selector: string }[]
		---@return fun(selector: string, props: table)
		makeAdder = function(result)
			return function(selector) result[#result + 1] = { selector = selector } end
		end,
	}
	loaded["::/gui/main/color_util.tl"] = setmetatable({}, {
		__index = function() return function(colour) return colour end end,
	})
	local globals = _G ---@type table<string, any>
	local saved_api = globals.api
	globals.api = { gui = { genericRep = { find = function(path) return path end,
		get = function() return { data = colours } end } } }
	local list = {} ---@type { file: string, selector: string }[]
	for file in read("src/ui_overhaul/_content.json"):gmatch('"(ui_overhaul/gui/[%w_]+%.css%.lua)"') do
		globals.data = nil
		dofile("src/ui_overhaul/content/" .. file)
		local rules = globals.data() ---@type { selector: string }[]
		for _i, rule in ipairs(rules) do
			for part in rule.selector:gmatch("[^,]+") do list[#list + 1] = { file = file, selector = part } end
		end
	end
	globals.api = saved_api
	loaded["::/gui/main/stylesheetutil.lua"], loaded["::/gui/main/color_util.tl"] = saved[1], saved[2]
	return list
end

describe("stylesheets", function()
	it("select only inside what this mod puts there", function()
		local foreign = {} ---@type string[]
		for _i, rule in ipairs(selectors()) do
			if not rule.selector:lower():find("uio", 1, true) then foreign[#foreign + 1] = rule.file .. ": " .. rule.selector end
		end
		assert.are.same({}, foreign)
	end)

	it("select a builtin.Component as R::Component (a bare Component matches nothing, observed in game)", function()
		local bare = {} ---@type string[]
		for _i, rule in ipairs(selectors()) do
			local padded = " " .. rule.selector
			if padded:find("[^:]Component[!#:]") or padded:find("[^:]Component$") then
				bare[#bare + 1] = rule.file .. ": " .. rule.selector
			end
		end
		assert.are.same({}, bare)
	end)

	it("use no underscore in a class name (the game's selector parser stops there, observed in game)", function()
		local bad = {} ---@type string[]
		for _i, rule in ipairs(selectors()) do
			for class in rule.selector:gmatch("![%w_%-]+") do
				if class:find("_", 1, true) then bad[#bad + 1] = rule.file .. ": " .. class end
			end
		end
		assert.are.same({}, bad)
	end)

	it("use only the window classes styles.lua sets", function()
		local known = {} ---@type table<string, true>
		for _i, entry in ipairs(styles.CLASSES) do
			known[entry[2] == "on" and styles.on(entry[1]) or styles.own(entry[1])] = true
		end
		local unknown = {} ---@type string[]
		for _i, rule in ipairs(selectors()) do
			for class in rule.selector:gmatch("uio%-o[nw]n?%-[%w_%-]+") do
				if not known[class] then unknown[#unknown + 1] = rule.file .. ": " .. class end
			end
		end
		assert.are.same({}, unknown)
	end)
end)

describe("styles", function()
	it("names only the classes the stylesheets select, of the features shown, the most needed first", function()
		local classes = styles.classes(
			function(key) return key == "construction" or key == "terminals" or key == "station_terminals" end,
			function(key) return key == "terminals" end)
		-- terminals is outranked: no uio-own-terminals; no class a stylesheet does not select
		-- an underscore of a feature key becomes a hyphen: the game's selectors take no underscore
		assert.are.equal("uio-on-station-terminals, uio-on-construction", classes)
		assert.is_nil(styles.classes(function() return false end, function() return false end))
	end)

	it("adds the classes to a window's own, without changing the caller's params", function()
		local p = { meta = { class = "popover" }, title = "x" }
		local copy = styles.with_classes(p, "uio-on-terminals")
		assert.are.equal("popover, uio-on-terminals", copy.meta.class)
		assert.are.equal("x", copy.title)
		assert.are.equal("popover", p.meta.class)
		assert.are.equal("uio-on-terminals", styles.with_classes({}, "uio-on-terminals").meta.class)
	end)

	it("leaves windows alone until the order is decided, then classes each, also after a ref", function()
		local wrapped = styles.wrap_window(builtin.Window)
		local p = { meta = { class = "popover" } }
		assert.are.equal(p, wrapped(p).window[1])
		local priority = package.loaded["ui_overhaul_1::/ui_overhaul/gui/priority.lua"] ---@type uo.gui.priority
		local active, outranked = priority.active, priority.outranked
		priority.active = function(key) return key == "terminals" end
		priority.outranked = function() return false end
		styles.decide()
		priority.active, priority.outranked = active, outranked
		assert.are.equal("popover, uio-own-terminals", wrapped(p).window[1].meta.class)
		local ref = { is_react_ref_info = true }
		local node = wrapped(ref, p).window ---@type table[] the stand-in's arguments
		assert.are.equal(ref, node[1])
		assert.are.equal("popover, uio-own-terminals", node[2].meta.class)
	end)
end)
