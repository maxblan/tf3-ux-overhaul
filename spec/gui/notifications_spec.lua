-- notifications.lua: installs over the base ridge and falls back to it when rendering fails. The base
-- modules it requires are stand-ins (restored after loading, so other specs keep theirs).
local BASE = function() return "base ridge" end
local registered = {}
local renders = 0

local stand_ins = {
	["::/gui/main/builtin.lua"] = { BoxLayout = function(t) return { layout = t } end },
	["::/gui/main/engine_react_util.tl"] = {},
	["::/gui/main/gui_react_util.tl"] = {},
	["::/scripts/lang_util.tl"] = {},
	["::/scripts/mathutil.lua"] = {},
	["::/game_mechanics/notifications/types/notification_react_util.tl"] = {},
	["::/game_mechanics/notifications/notification_util.tl"] = {},
	["::/scripts/table_util.tl"] = {},
	["::/scripts/util.tl"] = {},
	["::/game_mechanics/notifications/gui/notification_popups.tl"] = BASE,
	["::/gui/main/react.lua"] = {
		RegisterRecipe = function(name, fn)
			registered[name] = fn
			return fn
		end,
		CallOriginalRecipe = function(recipe, ...) return { original = recipe, args = { ... } } end,
		useState = function()
			renders = renders + 1
			error("no react here")
		end,
	},
}

local saved = {}
for path, module in pairs(stand_ins) do
	saved[path] = package.loaded[path]
	package.loaded[path] = module
end
local notifications = require("/ui_overhaul/gui/notifications.lua")
for path in pairs(stand_ins) do package.loaded[path] = saved[path] end

describe("notifications", function()
	local saved_debug_print = _G.debugPrint
	before_each(function() _G.debugPrint = function() end end)
	after_each(function() _G.debugPrint = saved_debug_print end)

	it("registers under the base recipe names so the base stylesheet applies", function()
		for _i, name in ipairs({ "NotificationPopups", "NotificationIcon", "NotificationInfo", "NotificationPopup",
			"NotificationPopupContent" }) do
			assert.are.equal("function", type(registered[name]), name)
		end
	end)

	it("replaces the base ridge", function()
		local calls = {}
		notifications.install({ ReplaceRecipe = function(old, new) calls[#calls + 1] = { old, new } end })
		assert.are.equal(1, #calls)
		assert.are.equal(BASE, calls[1][1])
		assert.are.equal(registered.NotificationPopups, calls[1][2])
	end)

	it("shows the base ridge inside a layout once rendering fails, and keeps showing it", function()
		local first = registered.NotificationPopups()
		assert.are.equal(BASE, first.layout.children[1].original)
		local second = registered.NotificationPopups()
		assert.are.equal(BASE, second.layout.children[1].original)
		assert.are.equal(1, renders)
	end)
end)
