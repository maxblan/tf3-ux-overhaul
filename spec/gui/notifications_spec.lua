-- notifications.lua: installs over the base ridge, falls back to it when rendering fails (fallback.lua)
-- and plays Resolve as the base does. The base modules are stand-ins (fake_react.load).
local fake_react = require("fake_react")

local BASE = function() return "base ridge" end
local fake = fake_react.new()
local util = { useFn = function() return nil end }
local builtin = fake_react.any()
builtin.BoxLayout = function(t) return { layout = t } end

local notifications = fake_react.load("/ui_overhaul/gui/notifications.lua", {
	["::/gui/main/react.lua"] = fake.react,
	["::/gui/main/builtin.lua"] = builtin,
	["::/game_mechanics/notifications/notification_util.tl"] = {
		getGuiTypeFromNotificationType = function() return "Info" end,
	},
	["::/scripts/util.tl"] = util,
	["::/game_mechanics/notifications/gui/notification_popups.tl"] = BASE,
})
local groups = require("/ui_overhaul/core/notification_groups.lua")
local PARENT_HOOKS = { "useState", "onStep", "useRef", "useRef" }

describe("notifications", function()
	local saved_debug_print = _G.debugPrint
	before_each(function() _G.debugPrint = function() end end)
	after_each(function() _G.debugPrint = saved_debug_print end)

	it("registers under the base recipe names so the base stylesheet applies", function()
		for _i, name in ipairs({ "NotificationPopups", "NotificationIcon", "NotificationInfo", "NotificationPopup",
			"NotificationPopupContent" }) do
			assert.are.equal("function", type(fake.recipe(name)), name)
		end
	end)

	-- the child (the mod's ridge) is registered first, the parent (the replacement) second
	local parent_recipe = fake.recipe("NotificationPopups", 2)

	it("replaces the base ridge", function()
		local calls = {}
		notifications.install({ ReplaceRecipe = function(old, new) calls[#calls + 1] = { old, new } end })
		assert.are.equal(1, #calls)
		assert.are.equal(BASE, calls[1][1])
		assert.are.equal(parent_recipe, calls[1][2])
	end)

	it("renders the ridge in a child that owns the hooks; the ridge node stays mouse transparent", function()
		local parent = fake.mount(parent_recipe)
		local node = parent.render()
		assert.are.same(PARENT_HOOKS, parent.hooks)
		assert.are.same({ true }, parent.internals.setMouseTransparent)
		assert.are.same({ true }, parent.internals.setDisableFocusable)
		assert.are.equal(fake.recipe("NotificationPopups", 1), node.layout.children[1].recipe)
	end)

	it("shows the base ridge once rendering fails, and keeps the child's hooks until then", function()
		local parent = fake.mount(parent_recipe)
		local list = builtin.List
		builtin.List = function() error("builtin changed") end -- a game update, say
		local child = fake.render_node(parent.render().layout.children[1])
		assert.is_true(notifications.switch.failed)
		local hooks = child.hooks
		assert.is_true(#hooks > 0)
		builtin.List = list
		child.render()
		assert.are.same(hooks, child.hooks)
		-- the ridge's unmount and step handlers are declared before anything that can fail
		assert.are.equal(1, #child.on_unmount)
		parent.step()
		local node = parent.render()
		assert.are.same(PARENT_HOOKS, parent.hooks)
		assert.are.equal(BASE, node.layout.children[1].original)
	end)

	it("declares a member's sound handlers even when its data state fails", function()
		local use_fn = util.useFn
		util.useFn = function() return function() fake.hook("useDataState") error("type changed") end end
		local member = fake.mount(fake.recipe("UioNotificationMember"))
		local node = member.render({ notificationId = 1, notification = { type = "x" } })
		util.useFn = use_fn
		assert.are.same({ "onMount", "onUnmount", "useDataState" }, member.hooks)
		assert.are.same({ layout = {} }, node)
	end)

	it("shows the base hover card when its additions fail", function()
		local popup = fake.mount(fake.recipe("NotificationPopup"))
		-- no group position: the "2 of 3" text is left out instead of raising
		local node = popup.render({ notification = { type = "x" }, index = 1 })
		assert.are.equal("table", type(node.layout))
	end)

	it("names the state of subsidy icons", function()
		local subsidy = "::/game_mechanics/notifications/types/subvention_notification.script"
		local missed = "::/game_mechanics/notifications/types/subvention_missed.script"
		assert.are.equal("uio-subsidy-offer", notifications.subsidy_class(subsidy, 1))
		assert.are.equal("uio-subsidy-active", notifications.subsidy_class(subsidy, 2))
		assert.are.equal("uio-subsidy-complete", notifications.subsidy_class(subsidy, 3))
		assert.are.equal("uio-subsidy-missed", notifications.subsidy_class(missed, nil))
		assert.are.equal("uio-subsidy-failed",
			notifications.subsidy_class("::/game_mechanics/notifications/types/subvention.script", nil))
		assert.is_nil(notifications.subsidy_class("::/other.script", 1))
		assert.is_nil(notifications.subsidy_class(subsidy, 7))
	end)

	describe("Resolve sound", function()
		local SUBSIDY = "::/game_mechanics/notifications/types/subvention_notification.script"
		local saved_api = _G.api
		local sounds ---@type any[]
		before_each(function()
			sounds = {}
			_G.api = { gui = {
				genericRep = { find = function() return 1 end, get = function() return { data = { Resolve = "resolve" } } end },
				sound = { playRandomSoundEffect = function(effect) sounds[#sounds + 1] = effect end },
			} }
		end)
		after_each(function() _G.api = saved_api end)

		local function subsidy(id, status)
			return { id = id, timestamp = id, notification = { type = SUBSIDY, params = { uid = id, status = status } } }
		end

		-- Renders the icon member of notification `id` and returns its unmount callback.
		local function mount_member(id)
			local member = fake.mount(fake.recipe("UioNotificationMember"))
			member.render({ notificationId = id, notification = subsidy(id, 1).notification })
			assert.are.equal(1, #member.on_unmount)
			return member.on_unmount[1]
		end

		-- The ridge rendered `items` after showing subsidies 1 and 2.
		local function ridge_shows(items)
			local _placed, state = groups.place(groups.build({ subsidy(1, 1), subsidy(2, 1) }))
			notifications.tiles = select(2, groups.place(groups.build(items), state))
		end

		before_each(function()
			notifications.switch.failed = false
			notifications.lifecycle.step()
		end)
		after_each(function() notifications.switch.failed = false end)

		it("plays nothing when a member's icon is rebuilt after a status change", function()
			local unmount = mount_member(1)
			ridge_shows({ subsidy(1, 2), subsidy(2, 1) })
			unmount()
			assert.are.same({}, sounds)
			-- the ridge stays: the next step forgets the move, a later unmount of the ridge resolves only what goes
			notifications.lifecycle.step()
			ridge_shows({})
			notifications.lifecycle.unmount()
			assert.are.same({}, sounds)
		end)

		it("plays when the notification leaves the ridge", function()
			local unmount = mount_member(1)
			ridge_shows({ subsidy(2, 1) })
			unmount()
			assert.are.same({ "resolve" }, sounds)
		end)

		it("plays when the ridge unmounts before its icons, as the base does", function()
			local unmount = mount_member(1)
			ridge_shows({ subsidy(1, 1), subsidy(2, 1) })
			notifications.lifecycle.unmount()
			unmount()
			assert.are.same({ "resolve" }, sounds)
		end)

		it("plays when the icons unmount before the ridge, as the base does", function()
			local unmount = mount_member(1)
			ridge_shows({ subsidy(1, 1), subsidy(2, 1) })
			unmount()
			assert.are.same({}, sounds)
			notifications.lifecycle.unmount()
			assert.are.same({ "resolve" }, sounds)
		end)

		it("plays nothing when the base ridge takes over after a failure", function()
			local first, second = mount_member(1), mount_member(2)
			ridge_shows({ subsidy(1, 1), subsidy(2, 1) })
			first()
			notifications.switch.failed = true
			notifications.lifecycle.unmount()
			second()
			assert.are.same({}, sounds)
		end)

		it("plays once per step for a group", function()
			local first, second = mount_member(1), mount_member(2)
			ridge_shows({})
			first()
			second()
			assert.are.same({ "resolve" }, sounds)
		end)
	end)
end)
