--- Minimal Busted-compatible test API (describe/it/before_each/after_each and the luassert
-- subset used by the specs), for running specs where Busted is not installed.
-- @module busted
local busted = { passed = 0, failed = 0 }

local lua_assert = assert
---@class uo.tools.busted.Block
---@field name string
---@field before_each fun()[]
---@field after_each fun()[]

local stack = {} ---@type uo.tools.busted.Block[] the open describe blocks, outermost first

---@param test_name string
---@return string
local function full_name(test_name)
	local parts = {} ---@type string[]
	for _, block in ipairs(stack) do parts[#parts + 1] = block.name end
	parts[#parts + 1] = test_name
	return table.concat(parts, " ")
end

---@param name string
---@param fn fun()
function describe(name, fn)
	stack[#stack + 1] = { name = name, before_each = {}, after_each = {} }
	fn()
	stack[#stack] = nil
end

---@param fn fun()
function before_each(fn)
	local hooks = stack[#stack].before_each
	hooks[#hooks + 1] = fn
end

---@param fn fun()
function after_each(fn)
	local hooks = stack[#stack].after_each
	hooks[#hooks + 1] = fn
end

---@param name string
---@param fn fun()
function it(name, fn)
	local ok, err = xpcall(function()
		for _, block in ipairs(stack) do
			for _, hook in ipairs(block.before_each) do hook() end
		end
		fn()
		for i = #stack, 1, -1 do
			for _, hook in ipairs(stack[i].after_each) do hook() end
		end
	end, debug.traceback)
	if ok then
		busted.passed = busted.passed + 1
		print("  ok   " .. full_name(name))
	else
		busted.failed = busted.failed + 1
		print("  FAIL " .. full_name(name) .. "\n" .. tostring(err))
	end
end

---@param message string
---@param level? integer
local function fail(message, level)
	error(message, (level or 1) + 2)
end

-- any: the assertions take values of every type, as luassert's do.
---@param expected any
---@param actual any
---@param message? string
local function equal(expected, actual, message)
	if expected ~= actual then
		fail(string.format("%sexpected %s, got %s", message and message .. ": " or "", tostring(expected), tostring(actual)))
	end
end

---@param value any
---@param seen? table<table, boolean> tables on the current path (cycle check)
---@return string
local function serialize(value, seen)
	if type(value) == "string" then return string.format("%q", value) end
	if type(value) ~= "table" then return tostring(value) end
	---@cast value table<any, any> -- checked above; LuaLS narrows `any` to a bare `table` with unknown keys
	seen = seen or {}
	if seen[value] then return "<cycle>" end
	seen[value] = true
	local keys = {} ---@type any[] the table's keys, of any type
	for key in pairs(value) do keys[#keys + 1] = key end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	local parts = {} ---@type string[]
	for _, key in ipairs(keys) do parts[#parts + 1] = tostring(key) .. "=" .. serialize(value[key], seen) end
	seen[value] = nil
	return "{" .. table.concat(parts, ", ") .. "}"
end

---@param a any
---@param b any
---@return boolean
local function deep_equal(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then return a == b end
	---@cast a table<any, any> -- checked above; LuaLS narrows `any` to a bare `table` with unknown keys
	---@cast b table<any, any> -- the same
	for key, value in pairs(a) do
		if not deep_equal(value, b[key]) then return false end
	end
	for key in pairs(b) do
		if a[key] == nil then return false end
	end
	return true
end

-- Deep equality of tables (luassert's are.same).
---@param expected any
---@param actual any
---@param message? string
local function same(expected, actual, message)
	if not deep_equal(expected, actual) then
		fail(string.format("%sexpected %s, got %s", message and message .. ": " or "", serialize(expected),
			serialize(actual)))
	end
end

---@param expected number
---@param actual any
---@param tolerance number
---@param message? string
local function near(expected, actual, tolerance, message)
	if type(actual) ~= "number" or math.abs(actual - expected) > tolerance then
		fail(string.format("%sexpected %s +/- %s, got %s", message and message .. ": " or "", tostring(expected),
			tostring(tolerance), tostring(actual)))
	end
end

---@param value any
---@param message? string
local function truthy(value, message)
	if not value then fail(message or ("expected a truthy value, got " .. tostring(value))) end
end

---@param value any
---@param message? string
local function falsy(value, message)
	if value then fail(message or ("expected a falsy value, got " .. tostring(value))) end
end

---@param value any
---@param message? string
local function is_nil(value, message)
	if value ~= nil then fail(message or ("expected nil, got " .. tostring(value))) end
end

-- `assert` stays callable like Lua's assert and gains the luassert forms used by the specs.
assert = setmetatable({ -- luacheck: ignore 121
	are = { equal = equal, same = same },
	equal = equal,
	same = same,
	equals = equal,
	near = near,
	truthy = truthy,
	is_truthy = truthy,
	falsy = falsy,
	is_falsy = falsy,
	is_nil = is_nil,
	is_true = function(value, message) equal(true, value, message) end,
	is_false = function(value, message) equal(false, value, message) end,
}, {
	__call = function(_, ...) return lua_assert(...) end,
})

return busted
