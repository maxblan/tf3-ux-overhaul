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
	are = { equal = equal },
	equal = equal,
	equals = equal,
	near = near,
	truthy = truthy,
	is_truthy = truthy,
	falsy = falsy,
	is_falsy = falsy,
	is_nil = is_nil,
	is_true = function(value, message) equal(true, value, message) end,
}, {
	__call = function(_, ...) return lua_assert(...) end,
})

return busted
