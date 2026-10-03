--- Minimal Busted-compatible test API (describe/it/before_each/after_each and the luassert
-- subset used by the specs), for running specs where Busted is not installed.
-- @module busted
local busted = { passed = 0, failed = 0 }

local lua_assert = assert
local stack = {} -- describe blocks: { name, before_each = {}, after_each = {} }

local function full_name(test_name)
	local parts = {}
	for _, block in ipairs(stack) do parts[#parts + 1] = block.name end
	parts[#parts + 1] = test_name
	return table.concat(parts, " ")
end

function describe(name, fn)
	stack[#stack + 1] = { name = name, before_each = {}, after_each = {} }
	fn()
	stack[#stack] = nil
end

function before_each(fn)
	local hooks = stack[#stack].before_each
	hooks[#hooks + 1] = fn
end

function after_each(fn)
	local hooks = stack[#stack].after_each
	hooks[#hooks + 1] = fn
end

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

local function fail(message, level)
	error(message, (level or 1) + 2)
end

local function equal(expected, actual, message)
	if expected ~= actual then
		fail(string.format("%sexpected %s, got %s", message and message .. ": " or "", tostring(expected), tostring(actual)))
	end
end

local function serialize(value, seen)
	if type(value) == "string" then return string.format("%q", value) end
	if type(value) ~= "table" then return tostring(value) end
	seen = seen or {}
	if seen[value] then return "<cycle>" end
	seen[value] = true
	local keys = {}
	for key in pairs(value) do keys[#keys + 1] = key end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	local parts = {}
	for _, key in ipairs(keys) do parts[#parts + 1] = tostring(key) .. "=" .. serialize(value[key], seen) end
	seen[value] = nil
	return "{" .. table.concat(parts, ", ") .. "}"
end

local function deep_equal(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then return a == b end
	for key, value in pairs(a) do
		if not deep_equal(value, b[key]) then return false end
	end
	for key in pairs(b) do
		if a[key] == nil then return false end
	end
	return true
end

-- Deep equality of tables (luassert's are.same).
local function same(expected, actual, message)
	if not deep_equal(expected, actual) then
		fail(string.format("%sexpected %s, got %s", message and message .. ": " or "", serialize(expected),
			serialize(actual)))
	end
end

local function near(expected, actual, tolerance, message)
	if type(actual) ~= "number" or math.abs(actual - expected) > tolerance then
		fail(string.format("%sexpected %s +/- %s, got %s", message and message .. ": " or "", tostring(expected),
			tostring(tolerance), tostring(actual)))
	end
end

local function truthy(value, message)
	if not value then fail(message or "expected a truthy value, got " .. tostring(value)) end
end

local function falsy(value, message)
	if value then fail(message or "expected a falsy value, got " .. tostring(value)) end
end

local function is_nil(value, message)
	if value ~= nil then fail(message or "expected nil, got " .. tostring(value)) end
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
