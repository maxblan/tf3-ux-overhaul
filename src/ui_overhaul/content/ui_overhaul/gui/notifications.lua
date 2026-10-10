--- Notification ridge (the row of icons at the top centre) with one icon per kind of notification.
-- Notifications of the same kind (core/notification_groups.lua) share an icon with a count badge:
--   * the icon shows the newest notification of its group; in a group of subsidies, the one whose
--     time (offer, time limit or effect) runs out first
--   * left-click does what a click on the shown notification does in the base game, then shows
--     the next one of the group (in that order, wrapping), so repeated clicks visit each
--   * right-click (gamepad: IA_OPTION2) dismisses the whole group
--   * the hover card is the base card of the shown notification, with "2 of 3" next to the title;
--     for a group of subsidies it lists the others below it (icon, text and time bar of each, as
--     their own cards show them), in the order the clicks show them
-- A group of one looks and behaves like the base icon. An icon follows its notifications, as the
-- base keys icons by id (groups.place): it keeps its node and place while one of them is shown, and
-- Resolve plays only when a notification leaves the ridge or the ridge itself goes, as in the base.
-- Subsidy icons show their state in colours with at least 7:1 contrast to the white symbol (WCAG
-- AAA): available blue, in progress orange, effect active green, failed red, a missed offer grey;
-- the timer ring is drawn in plain white (notifications.css.lua). The hover card's icon matches.
-- A Lua conversion of the base ridge (game_mechanics/notifications/gui/notification_popups.tl),
-- registered under the base recipe names so the base stylesheet applies, installed through a
-- react-replacement-config (installer.lua). If rendering fails, the base ridge is shown for
-- the rest of the session (fallback.lua), without a Resolve for the icons it takes over.
-- Which notifications exist, are hidden or are dismissed is left to the game: this module only
-- sends the base "dismiss" and "initialSound" events, as the base ridge does.
-- @module ui_overhaul.gui.notifications
local builtin = require("::/gui/main/builtin.lua")
local engine_react_util = require("::/gui/main/engine_react_util.tl")
local gui_react_util = require("::/gui/main/gui_react_util.tl")
local lang_util = require("::/scripts/lang_util.tl")
local math_util = require("::/scripts/mathutil.lua")
local notification_react_util = require("::/game_mechanics/notifications/types/notification_react_util.tl")
local notification_util = require("::/game_mechanics/notifications/notification_util.tl")
local react = require("::/gui/main/react.lua")
local table_util = require("::/scripts/table_util.tl")
local util = require("::/scripts/util.tl")
local base_popups = require("::/game_mechanics/notifications/gui/notification_popups.tl")
local subvention_util = require("::/game_mechanics/subventions/subvention_util.tl")
local groups = require("/ui_overhaul/core/notification_groups.lua")
local fallback = require("/ui_overhaul/gui/fallback.lua")
local guard = require("ui_overhaul_1::/ui_overhaul/gui/guard.lua")

---@class uo.gui.notifications
local notifications = {}

---@alias uo.gui.notifications.Notification uo.core.notification_groups.AnyNotification
---@alias uo.gui.notifications.GuiData game.game_mechanics.notifications.notifications.NotificationGuiData
---@alias uo.gui.notifications.GuiType game.game_mechanics.notifications.notifications.NotificationGuiData.Type
---@alias uo.gui.notifications.OnClick fun(stack: boolean, dryRun?: boolean): boolean

--- The sound table of notification_sfx.gres: sound files by event.
---@class uo.gui.notifications.Sfx
---@field Initialize? FilePath[]
---@field Resolve? FilePath[]

--- A notification on the ridge, as the base ridge reads it (GuiNotification in notification_popups.tl).
---@class uo.gui.notifications.GuiNotification
---@field entry game.game_mechanics.notifications.notifications.NotificationsState.Entry
---@field id integer
---@field type uo.gui.notifications.GuiType
---@field ends? number game ms when a subsidy's current time runs out (groups.subsidy_ends)

--- Counts of the last render, for the in-game checks: raw notifications shown, icons, largest group.
---@type { raw: integer, groups: integer, largest: integer }
notifications.stats = { raw = 0, groups = 0, largest = 0 }

--- Marked failed once rendering failed: the base ridge is shown for the rest of the session.
notifications.switch = fallback.switch("notification ridge")

--- The icons of the last render (groups.place): which notifications are on the ridge, read when an
-- icon member unmounts. There is one ridge.
---@type uo.core.notification_groups.Tiles?
notifications.tiles = nil

local SFX_PATH = "::/game_mechanics/notifications/gui/sound/notification_sfx.gres"

local report = guard.reporter("notification ridge: ", " failed: ")

--- `fn` wrapped so that an error in an engine callback is logged once instead of escaping.
---@generic F: function
---@param what string
---@param fn F
---@param default? any what the wrapper returns after an error, a value of fn's own result type
---@return F
local function safe(what, fn, default)
	return function(...)
		local ok, result = pcall(fn, ...)
		if ok then return result end
		report(what, result)
		return default
	end
end

---@return react.TreeNodeId
local function empty()
	return builtin.BoxLayout{}
end

---@type uo.gui.notifications.Sfx|false|nil false: the sound table could not be read
local sfx_data
---@return uo.gui.notifications.Sfx?
local function sfx()
	if sfx_data == nil then
		local ok, data = pcall(function() return api.gui.genericRep.get(api.gui.genericRep.find(SFX_PATH)).data end)
		sfx_data = ok and data or false
	end
	return sfx_data or nil
end

-- Members of a group mount and unmount together (a group is dismissed at once, a saved game loads
-- several), so each sound plays at most once per GUI step.
---@type table<string, boolean>
local played = {}
---@param kind string
---@param sounds? FilePath[]
local function play(kind, sounds)
	if not sounds or played[kind] then return end
	played[kind] = true
	api.gui.sound.playRandomSoundEffect(sounds)
end

-- The click action of each mounted member, by notification id. Ids are unique and there is one ridge.
---@type table<integer, uo.gui.notifications.OnClick|false>
local click_handlers = {}

-- Hover card (1:1 from the base, plus the position in the group) ---------------------------------

-- `node` (an icon) inside a component of class uio-notification-icon, and of the subsidy state class
-- `class` if given (notifications.css.lua: the icon colours apply only inside it).
---@param node? react.TreeNodeId
---@param class? string
---@return react.TreeNodeId?
local function with_state(node, class)
	if not node then return nil end
	return builtin.Component{
		meta = { class = class and ("uio-notification-icon, " .. class) or "uio-notification-icon" },
		layout = builtin.BoxLayout{ children = { node } },
	}
end

-- The card's body: icon, text and progress bars, as a button that does what a click on the icon does.
---@param params uo.gui.notifications.GuiData
---@param guiType uo.gui.notifications.GuiType
---@param subsidyClass? string
---@return react.TreeNodeId
local function card_body(params, guiType, subsidyClass)
	return builtin.Button {
		content = builtin.BoxLayout{
			orientation = builtin.type.Orientation.Horizontal,
			children = {
				params.previewImage and builtin.ImageView {
					meta = { class = "preview-image" },
					path = params.previewImage,
					scaling = builtin.type.ImageViewScaling.AutoFit,
				} or with_state(notification_react_util.NotificationSimpleIcon{
					icon = params.icon,
					status = params.status,
					type = guiType,
				}, subsidyClass) or nil,
				notification_react_util.NotificationProgressContent{
					meta = { class = params.previewImage and "beside-preview-image" or nil },
					progress = params.progress,
					progresses = params.progresses,
					description = params.description,
					status = params.status,
					type = guiType,
				},
			},
		},
		onClick = params.onClick
	}
end

---@param params uo.gui.notifications.GuiData
---@param guiType uo.gui.notifications.GuiType
---@param position? string "2 of 3"
---@param subsidyClass? string
---@return react.TreeNodeId
local NotificationPopupContent = react.RegisterRecipe("NotificationPopupContent", function(params, guiType, position,
		subsidyClass)
	local mainContent = card_body(params, guiType, subsidyClass)

	return builtin.BoxLayout {
		orientation = builtin.type.Orientation.Vertical,
		children = {
			builtin.BoxLayout {
				orientation = builtin.type.Orientation.Horizontal,
				children = {
					builtin.TextView {
						meta = { class = "popup-title, font-scale-title-4" },
						text = params.title
					},
					position and builtin.TextView {
						meta = { class = "font-scale-body" },
						text = position,
					} or nil,
				},
			},
			mainContent,
		},
	}
end)

---@class uo.gui.notifications.PopupParam: react.Param
---@field notification uo.gui.notifications.Notification
---@field index? integer position in the group
---@field count? integer members of the group
---@field others? uo.core.notification_groups.Item[] the group's other members to list below the card

-- Another member of the hovered group, below the card: the body of its own card. Registered under the
-- base name too, so the base stylesheet sizes it like the card above (R::NotificationPopupContent).
---@class uo.gui.notifications.OtherParam: react.Param
---@field notification uo.gui.notifications.Notification

---@param params uo.gui.notifications.OtherParam
---@return react.TreeNodeId
local function render_other(params)
	local notification = params.notification
	local dataStateFn = util.useFn(notification.type .. "@useDataState")
	local dataState = dataStateFn and dataStateFn(notification.params, notification.simParams) or nil
	if not dataState then return empty() end
	local guiType = notification_util.getGuiTypeFromNotificationType(notification.type)
	local status = type(notification.params) == "table" and notification.params.status or nil
	return builtin.BoxLayout{ children = {
		card_body(dataState, guiType, notifications.subsidy_class(notification.type, status)),
	} }
end

---@param params uo.gui.notifications.OtherParam
---@return react.TreeNodeId
local NotificationOther = react.RegisterRecipe("NotificationPopupContent", function(params)
	local ok, node = pcall(render_other, params)
	if ok then return node end
	report("hover card entry", node)
	return empty()
end)

---@param params uo.gui.notifications.PopupParam
---@return react.TreeNodeId
local NotificationPopup = react.RegisterRecipe("NotificationPopup", function(params)
	local dataStateFn = util.useFn(params.notification.type .. "@useDataState")
	local dataState = dataStateFn and dataStateFn(params.notification.params, params.notification.simParams) or nil
	local guiType = notification_util.getGuiTypeFromNotificationType(params.notification.type)
	local notification = params.notification
	-- the additions to the base card: without them it is the base card
	local ok, subsidyClass, position = pcall(function()
		local class = notifications.subsidy_class(notification.type,
			type(notification.params) == "table" and notification.params.status or nil)
		return class, (params.count or 1) > 1
			and lang_util.format(_("{index} of {count}"), { index = tostring(params.index), count = tostring(params.count) })
			or nil
	end)
	if not ok then
		report("hover card", subsidyClass)
		subsidyClass, position = nil, nil
	end
	local others = nil ---@type react.TreeNodeId?
	if dataState and params.others and #params.others > 0 then
		local rows = {} ---@type react.TreeNodeId[]
		for i, other in ipairs(params.others) do
			rows[i] = NotificationOther{ meta = { localKey = tostring(other.id) }, notification = other.notification }
		end
		others = builtin.BoxLayout{
			meta = { class = "uio-notification-others" },
			orientation = builtin.type.Orientation.Vertical,
			children = rows,
		}
	end

	return builtin.BoxLayout{orientation = builtin.type.Orientation.Vertical, children = {
		builtin.Component {
			meta = {
				class = "notification-popup",
				disableFocusableRecursive = true,
			},
			layout = builtin.BoxLayout{
				orientation = builtin.type.Orientation.Vertical,
				children = {
					dataState and NotificationPopupContent(dataState, guiType, position, subsidyClass) or nil,
					others,
				},
			},
		},
	}}
end)

---@class uo.gui.notifications.InfoGroup
---@field index? integer position of the shown member in the group
---@field count? integer members of the group
---@field others? uo.core.notification_groups.Item[] members to list below the card

---@param number number[] { list left, list right, icon left, icon right } (the base's name)
---@param notificationId integer
---@param notification? uo.gui.notifications.Notification
---@param group? uo.gui.notifications.InfoGroup
---@return react.TreeNodeId
local NotificationInfo = react.RegisterRecipe("NotificationInfo", function(number, notificationId, notification, group)
	react.setMouseTransparent(true)

	local notificationPopupRef = react.useNodeRef(builtin.Component)
	local offsetState = react.useState(0)
	react.onStep(safe("hover card position", function()
		if notificationPopupRef and notificationPopupRef:get() ~= nil and not notificationPopupRef:hasExpired() then
			local left = number[1]
			local right = number[2]
			local valueLeft = number[3]
			local valueRight = number[4]
			local popupWidth = notificationPopupRef:get():getPosition(1.0, 0.0).x
				- notificationPopupRef:get():getPosition(0.0, 0.0).x

			if left > right or valueLeft > valueRight or popupWidth < 0 then
				offsetState:set(0)
				return
			end

			local iconWidth = valueRight - valueLeft
			local innerMin = left + iconWidth / 2
			local innerMax = right - iconWidth / 2

			local a = 0.0
			if math.abs(innerMax - innerMin) >= 0.001 then
				local value = (valueLeft + valueRight) / 2
				a = math_util.invLerp(value, innerMin, innerMax)
			end
			local b = math_util.lerp(left, right, a)
			offsetState:set(b)
		end
	end))

	return notification and builtin.FloatingLayout {
		children = {
			builtin.FloatingLayoutChild {
				h = offsetState:old(),
				v = -1.0,
				item = NotificationPopup(react.ref(notificationPopupRef), {
					meta = {
						localKey = tostring(notificationId),
						class = offsetState:old() == 0 and "hide" or nil
					},
					notification = notification,
					index = group and group.index,
					count = group and group.count,
					others = group and group.others,
				})
			},
		},
	} or builtin.BoxLayout{}
end)

-- Icons -------------------------------------------------------------------------------------------

local SUBSIDY = "::/game_mechanics/notifications/types/subvention_notification.script"
local SUBSIDY_MISSED = "::/game_mechanics/notifications/types/subvention_missed.script"
local SUBSIDY_FAILED = "::/game_mechanics/notifications/types/subvention.script"
local SUBSIDY_STATUS = { "uio-subsidy-offer", "uio-subsidy-active", "uio-subsidy-complete" }

--- css class of a subsidy icon: its state (offer, active, effect active, failed, missed); nil for
-- other icons.
---@param notification_type? string
---@param status? integer the subsidy's status: 1 offer, 2 active, 3 effect active
---@return string?
function notifications.subsidy_class(notification_type, status)
	if notification_type == SUBSIDY_MISSED then return "uio-subsidy-missed" end
	if notification_type == SUBSIDY_FAILED then return "uio-subsidy-failed" end
	if notification_type ~= SUBSIDY then return nil end
	return SUBSIDY_STATUS[status]
end

--- The members of a group the hover card lists below the shown one (the one at `index`): for a
-- group of subsidies, the others in the order the clicks show them; nil for other groups.
---@param members uo.core.notification_groups.Item[]
---@param index integer
---@return uo.core.notification_groups.Item[]?
function notifications.others(members, index)
	if #members < 2 then return nil end
	for _i, member in ipairs(members) do
		if not (member.notification and member.notification.type == SUBSIDY) then return nil end
	end
	local list = {} ---@type uo.core.notification_groups.Item[]
	for k = 1, #members - 1 do list[k] = members[(index - 1 + k) % #members + 1] end
	return list
end

---@param dataState uo.gui.notifications.GuiData
---@param guiType uo.gui.notifications.GuiType
---@param notification? uo.gui.notifications.Notification
---@return react.TreeNodeId?
local function icon(dataState, guiType, notification)
	---@type react.TreeNodeId
	local node
	---@type number?
	local percentage
	if dataState.progress ~= nil or (dataState.progresses ~= nil and #dataState.progresses > 0) then
		percentage = dataState.progress and dataState.progress.percentage or dataState.progresses[1].percentage
		-- past a deadline the base value turns negative (a negative ring frame)
		percentage = percentage and math.max(0, math.min(1, percentage))
		node = notification_react_util.NotificationProgressIcon {
			icon = dataState.icon,
			status = dataState.status,
			type = guiType,
			percentage = percentage,
		}
	else
		node = notification_react_util.NotificationSimpleIcon{
			icon = dataState.icon,
			status = dataState.status,
			type = guiType,
		}
	end
	local status = notification and type(notification.params) == "table" and notification.params.status or nil
	return with_state(node, notifications.subsidy_class(notification and notification.type, status))
end

---@param notificationId integer
---@param dataState? uo.gui.notifications.GuiData
local function on_member_mount(notificationId, dataState)
	local native = notification_util.externalGetNotificationsStateNative()
	local entry = native and notification_util.getNotificationEntryFromNative(native, notificationId)
	if not entry or api.gui.mission.isCutscenePlaying() then
		return
	end
	if entry.playedInitialSound == nil or entry.playedInitialSound == false then
		local sounds = dataState and dataState.soundOnMount
		if sounds then
			play("mount", sounds)
		else
			local data = sfx()
			play("mount", data and data.Initialize)
		end
		api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "Notifications", "initialSound", {
			notificationId = notificationId
		}))
	end
end

---@param notificationId integer
local function resolve(notificationId)
	click_handlers[notificationId] = nil
	local data = sfx()
	play("resolve", data and data.Resolve)
end

-- Members that unmounted this step while their notification was still on the ridge.
---@type table<integer, boolean>
local kept = {}

---@param notificationId integer
local function on_member_unmount(notificationId)
	-- The mod's ridge failed and the base ridge takes over with the same notifications: nothing goes,
	-- so nothing plays (the base ridge plays Initialize only for a notification that has not had it).
	if notifications.switch.failed then
		click_handlers[notificationId] = nil
		return
	end
	-- Still on the ridge: either the member moved to another icon, which already holds its click
	-- action, or the whole ridge is going. The base plays Resolve when an icon goes, so for a move
	-- (the icon is rebuilt) nothing plays, and for the ridge its unmount decides (on_ridge_unmount).
	if groups.shown(notifications.tiles, notificationId) then
		kept[notificationId] = true
		return
	end
	resolve(notificationId)
end

-- The ridge unmounts: every icon goes, and the base plays Resolve for each. The engine's order of
-- parent and child unmount callbacks is not documented (react.lua leaves it to the native context),
-- so both orders resolve: members unmounted before this are in `kept`, members unmounted after it
-- find no notification on the ridge.
local function on_ridge_unmount()
	notifications.tiles = nil
	if notifications.switch.failed then
		kept = {}
		return
	end
	for notificationId in pairs(kept) do resolve(notificationId) end
	kept = {}
end

-- A new GUI step: sounds may play again, and members kept last step moved (the ridge stayed).
local function on_ridge_step()
	played = {}
	kept = {}
end

--- The ridge's step and unmount handlers, public for the specs.
notifications.lifecycle = { step = on_ridge_step, unmount = on_ridge_unmount }

-- One notification of a group: its data state (a hook, so one recipe per notification, keyed by
-- id), the base mount and unmount sounds, and the icon while it is the one the group shows.
---@class uo.gui.notifications.MemberParam: react.Param
---@field notificationId integer
---@field notification uo.gui.notifications.Notification
---@field current boolean the member the icon shows

---@param params uo.gui.notifications.MemberParam
---@return react.TreeNodeId
local function render_member(params)
	local id = params.notificationId
	-- The sound handlers come before the data state, whose hooks run the notification type's code:
	-- if that fails, the member still declares them (Member renders an empty layout then).
	---@type uo.gui.notifications.GuiData?
	local dataState
	react.onMount(safe("sound", function() on_member_mount(id, dataState) end))
	react.onUnmount(safe("sound", function() on_member_unmount(id) end))
	local dataStateFn = util.useFn(params.notification.type .. "@useDataState")
	dataState = dataStateFn and dataStateFn(params.notification.params, params.notification.simParams) or nil
	local guiType = notification_util.getGuiTypeFromNotificationType(params.notification.type)

	click_handlers[id] = dataState and dataState.onClick or false
	if not (params.current and dataState) then return empty() end
	return builtin.BoxLayout{ children = { icon(dataState, guiType, params.notification) } }
end

---@param params uo.gui.notifications.MemberParam
---@return react.TreeNodeId
local Member = react.RegisterRecipe("UioNotificationMember", function(params)
	local ok, node = pcall(render_member, params)
	if ok then return node end
	report("icon", node)
	return empty()
end)

-- The icon of a group. Registered as the base "NotificationIcon", which the base stylesheet sizes
-- and animates; the button stays the same node while the shown member changes.
---@class uo.gui.notifications.TileParam: react.Param
---@field members uo.core.notification_groups.Item[]
---@field currentId integer
---@field onDismiss fun()
---@field onAdvance fun()

---@param params uo.gui.notifications.TileParam
---@return react.TreeNodeId
local function render_tile(params)
	react.onMouseEvent(safe("right-click", function(evt)
		if evt.type == api.gui.mouse.Event.Type.Clicked and evt.button == 2 then
			params.onDismiss()
			return true
		end
		return false
	end, false))
	react.useInputAction("IA_OPTION2", react.iaHandler(safe("dismiss", function()
		params.onDismiss()
	end)))

	---@type react.TreeNodeId[]
	local members = {}
	for _i, member in ipairs(params.members) do
		members[#members + 1] = Member{
			meta = { localKey = tostring(member.id) },
			notificationId = member.id,
			notification = member.notification,
			current = member.id == params.currentId,
		}
	end
	local count = #params.members

	return builtin.BoxLayout{
		children = {
			builtin.Button{
				content = builtin.FloatingLayout{
					children = {
						builtin.FloatingLayoutChild{
							h = -1,
							v = -1,
							item = builtin.BoxLayout{
								meta = { class = "uio-notification-members" },
								orientation = builtin.type.Orientation.Horizontal,
								children = members,
							},
						},
						count > 1 and builtin.FloatingLayoutChild{
							overflowMode = builtin.type.FloatingLayoutOverflowMode.Overflow,
							item = builtin.TextView{
								meta = { class = "font-scale-annotation, bubble, uio-notification-count", mouseTransparent = true },
								text = tostring(count),
							},
						} or nil,
					},
				},
				onClick = safe("click", function()
					local onClick = click_handlers[params.currentId]
					if onClick then onClick(false) end
					if count > 1 then params.onAdvance() end
				end),
			},
		},
	}
end

---@param params uo.gui.notifications.TileParam
---@return react.TreeNodeId
local NotificationIcon = react.RegisterRecipe("NotificationIcon", function(params)
	local ok, node = pcall(render_tile, params)
	if ok then return node end
	report("icon group", node)
	return empty()
end)

-- Ridge -------------------------------------------------------------------------------------------

local SUBSIDY_SCRIPT = "::/game_mechanics/subventions/subventions.gs"

--- Game ms when the subsidy of notification `notification` runs out (offer, time limit or effect),
-- read from the subsidy game script as the subsidy notification reads it; nil for other notifications
-- or where it cannot be read. Runs in the ridge's timer: engine reads only.
---@param notification? uo.gui.notifications.Notification
---@return number?
local function subsidy_ends(notification)
	if not (notification and notification.type == SUBSIDY and type(notification.params) == "table") then return nil end
	local uid = notification.params.uid
	if type(uid) ~= "number" then return nil end
	local ok, ends = pcall(function()
		local script = api.engine.system.gameScriptSystem.getEntityForGameScript(SUBSIDY_SCRIPT)
		if not script then return nil end
		local subsidy = subvention_util.getSubventionAndStatusFromGameScript(script, uid)
		return subsidy and groups.subsidy_ends({
			spawnTime = subsidy.spawnTime, acceptedTime = subsidy.acceptedTime,
			completedTime = subsidy.completedTime, data = subsidy.data,
		})
	end)
	return ok and ends or nil
end

---@return uo.gui.notifications.GuiNotification[]
local function read_notifications()
	local notificationsStateNative = notification_util.externalGetNotificationsStateNative()
	if notificationsStateNative == nil then
		return {}
	end

	---@type uo.gui.notifications.GuiNotification[]
	local guiNotifications = {}
	local history = notification_util.getHistoryFromNative(notificationsStateNative)

	-- the base casts these two the same way (notification_popups.tl:253-255)
	local nativeNotifications = notificationsStateNative:find("notifications") --[[@as NativeLuaTable]]
	for _i, id in ipairs(history) do
		local notificationEntryNative = nativeNotifications:find(id) --[[@as NativeLuaTable?]]
		if notificationEntryNative ~= nil and not notificationEntryNative:find("dismissed") then
			local entry = notification_util.getNotificationEntryFromNative(notificationsStateNative, id)
			guiNotifications[#guiNotifications + 1] = {
				entry = entry,
				id = id,
				type = notification_util.getGuiTypeFromNotificationType(entry.notification.type),
				ends = subsidy_ends(entry.notification),
			}
		end
	end

	table.sort(guiNotifications, function(a, b)
		if a.entry.timestamp ~= b.entry.timestamp then
			return a.entry.timestamp < b.entry.timestamp
		end
		return a.id < b.id
	end)

	return guiNotifications
end

---@param guiNotifications uo.gui.notifications.GuiNotification[]
---@return uo.core.notification_groups.Group[]
local function make_groups(guiNotifications)
	---@type uo.core.notification_groups.Item[]
	local items = {}
	for _i, guiNotification in ipairs(guiNotifications) do
		local entry = guiNotification.entry
		if entry.notification and not entry.dismissed then
			items[#items + 1] = { id = guiNotification.id, timestamp = entry.timestamp, notification = entry.notification,
				ends = guiNotification.ends }
		end
	end
	local result = groups.build(items)
	local largest = 0
	for _i, group in ipairs(result) do largest = math.max(largest, #group.members) end
	local stats = notifications.stats
	if stats.raw ~= #items or stats.groups ~= #result or stats.largest ~= largest then
		-- One line per change, for the in-game check (the testbench runs in another Lua state).
		debugPrint(string.format("[ui_overhaul] notification ridge: %d notifications in %d icons, largest group %d",
			#items, #result, largest))
	end
	notifications.stats = { raw = #items, groups = #result, largest = largest }
	return result
end

---@return react.TreeNodeId
local function render()
	local focusableState = react.useState(false)
	local gamepadFocusedState = react.useState(false)
	local hoveredListIndexState = react.useState(-1)
	---@type react.State<table<string, integer>>
	local cursorState = react.useState({}) -- icon (group.tile) -> id of the notification it shows
	---@type react.Ref<uo.core.notification_groups.Tiles?>
	local tilesRef = react.useRef(nil)
	local animatedRef = react.useRef(false)
	local enteredListIndexRef = react.useRef(-1)
	local listRef = react.useNodeRef(builtin.Component)
	local notificationIconRef = react.useNodeRef(builtin.Component)
	-- declared before anything that can fail, so a failed render declares them too
	react.onUnmount(safe("sound", on_ridge_unmount))
	react.onStep(function()
		on_ridge_step()
		if hoveredListIndexState:old() < 1 then
			animatedRef:set(true)
		end
		if animatedRef:get() and hoveredListIndexState:old() > 0 and enteredListIndexRef:get() < 0 then
			enteredListIndexRef:set(hoveredListIndexState:old())
		end
		if enteredListIndexRef:get() > 0 and hoveredListIndexState:old() ~= enteredListIndexRef:get() then
			animatedRef:set(false)
			enteredListIndexRef:set(-1)
		end
	end)

	react.useInputAction("IA_NOTIFICATIONS_OPEN", react.iaHandler(safe("open", function()
		focusableState:set(not focusableState:old())
		if not focusableState:old() then
			listRef:get():focus()
		end
	end)))

	react.setStyleClasses(focusableState:old() and "focused" or "unfocused")

	react.useInputAction("IA_BACK", react.iaHandler(function()
		focusableState:set(false)
	end))

	local makeOffsetState = function()
		if notificationIconRef and notificationIconRef:get() and not notificationIconRef:hasExpired() then
			local listLeft = listRef:get():getPosition(0.0, 0.0).x
			local listRight = listRef:get():getPosition(1.0, 0.0).x
			local iconLeft = notificationIconRef:get():getPosition(0.0, 0.0).x
			local iconRight = notificationIconRef:get():getPosition(1.0, 0.0).x
			return {listLeft, listRight, iconLeft, iconRight}
		end
		return { 0.0, 0.0, 1.0, 0.0 }
	end
	local offsetState = engine_react_util.useStepState(safe("hover card position", makeOffsetState,
		{ 0.0, 0.0, 1.0, 0.0 }))

	local makeIsMouseInputState = function()
		return api.util.getInputMode() == api.type["enum"].InputMode.KeyboardMouse
	end
	local isMouseInputState = engine_react_util.useStepState(makeIsMouseInputState, nil, nil, function(_old, new)
		focusableState:set(false)
		if not new then
			hoveredListIndexState:set(-1)
		end
	end)

	local guiNotificationsState, commit = engine_react_util.useStepStateTimerWithCommit(read_notifications)

	react.setMouseTransparent(true)
	react.setDisableFocusable(not focusableState:old() or isMouseInputState:old())

	local groupList, tiles = groups.place(make_groups(guiNotificationsState:old()), tilesRef:get())
	tilesRef:set(tiles)
	notifications.tiles = tiles
	local cursor = cursorState:old() or {}

	---@param group uo.core.notification_groups.PlacedGroup
	---@return integer
	local function current_index(group)
		return groups.index(group, cursor[group.tile])
	end

	---@param group uo.core.notification_groups.PlacedGroup
	local function dismiss(group)
		local newGuiNotificationsState = table_util.copy(guiNotificationsState:old())
		---@type table<integer, boolean>
		local ids = {}
		for _i, member in ipairs(group.members) do ids[member.id] = true end
		for _i, guiNotification in ipairs(newGuiNotificationsState) do
			if ids[guiNotification.id] then guiNotification.entry.dismissed = true end
		end
		---@type Command[]
		local cmds = {}
		for i, member in ipairs(group.members) do
			cmds[i] = api.cmd.makeScriptingSendEventCmd("", "Notifications", "dismiss", { id = member.id })
		end
		-- Commands run in order: the committed one goes last, so the ridge reads the engine again only
		-- after all members are dismissed.
		for i = 2, #cmds do api.cmd.sendCommand(cmds[i]) end
		commit(newGuiNotificationsState, cmds[1])
	end

	---@param group uo.core.notification_groups.PlacedGroup
	---@param currentId integer
	local function advance(group, currentId)
		---@type table<string, integer>, table<string, integer>
		local old, newCursor = cursorState:old() or {}, {}
		-- only icons still shown: icon keys are never reused
		for _i, other in ipairs(groupList) do newCursor[other.tile] = old[other.tile] end
		newCursor[group.tile] = groups.next_id(group, currentId)
		cursorState:set(newCursor)
	end

	---@type react.TreeNodeId[]
	local children = {}
	for k, group in ipairs(groupList) do
		local currentId = group.members[current_index(group)].id
		local tileParams = {
			meta = { localKey = group.tile },
			members = group.members,
			currentId = currentId,
			onDismiss = function() dismiss(group) end,
			onAdvance = function() advance(group, currentId) end,
		}
		if hoveredListIndexState:old() == k then
			table.insert(children, NotificationIcon(react.ref(notificationIconRef), tileParams))
		else
			table.insert(children, NotificationIcon(tileParams))
		end
	end

	if hoveredListIndexState:old() > #groupList then
		hoveredListIndexState:set(-1)
	end

	local animated = animatedRef:get()

	if #children == 0 and focusableState:old() then
		focusableState:set(false)
	end

	---@type uo.core.notification_groups.PlacedGroup?
	local hovered = (hoveredListIndexState:old() and hoveredListIndexState:old() >= 0
			and (gamepadFocusedState:old() or isMouseInputState:old()))
		and groupList[hoveredListIndexState:old()]
		or nil
	local hoveredIndex = hovered and current_index(hovered) or nil
	local hoveredMember = hovered and hovered.members[hoveredIndex] or nil
	local hoveredCount = hovered and #hovered.members or nil
	local hoveredOthers = nil ---@type uo.core.notification_groups.Item[]?
	if hovered and hoveredIndex then
		local ok, others = pcall(notifications.others, hovered.members, hoveredIndex)
		hoveredOthers = ok and others or nil
		if not ok then report("hover card list", others) end
	end
	return builtin.BoxLayout {
		orientation = builtin.type.Orientation.Vertical,
		children = {
			gui_react_util.FocusTraversalScope{
				horizontal = true,
				vertical = true,
				meta = {
					class = "list-wrapper",
					mouseTransparent = true,
					disableFocusableRecursive = not focusableState:old() or isMouseInputState:old(),
					onFocusChange = function(focus)
						gamepadFocusedState:set(focus)
					end,
				},
				layout = builtin.BoxLayout{
					orientation = builtin.type.Orientation.Horizontal,
					children = {
						builtin.List(react.ref(listRef), {
							meta = {
								mouseTransparent = true,
								disableFocusableRecursive = not focusableState:old() or isMouseInputState:old(),
							},
							verticalScrollBarPolicy = builtin.type.ScrollBarPolicy.AlwaysOff,
							orientation = builtin.type.Orientation.Horizontal,
							children = children,
							deselectAllowed = true,
							onHover = function(key)
								hoveredListIndexState:set(key)
							end,
							onSelect = function(key)
								hoveredListIndexState:set(key)
							end,
							onActivate = function(key)
								hoveredListIndexState:set(key)
							end,
							behavior = builtin.type.ListBehavior.Navigational,
						}),
					},
				},
			},
			hoveredMember and gui_react_util.Clipper{
				meta = { class = animated and "notification-animated" or nil },
				layout = builtin.BoxLayout{
					children = {
						NotificationInfo(offsetState:old(), hoveredMember.id, hoveredMember.notification,
							{ index = hoveredIndex, count = hoveredCount, others = hoveredOthers }),
					},
				}
			} or nil,
		}
	}
end

-- The ridge node keeps what the base ridge sets on itself and the ridge root sets on it
-- (game.tl NotificationsRidge): mouse transparent, not focusable itself. The child, registered under
-- the base name too, sets its focus class and focusability as the base ridge does.
local Replacement = fallback.replacement(notifications.switch, "NotificationPopups", render, base_popups, {
	-- game.tl:389-390 forwards the notification key to this node; the shown ridge handles it
	input_actions = { "IA_NOTIFICATIONS_OPEN" },
	internals = function()
		react.setMouseTransparent(true)
		react.setDisableFocusable(true)
	end,
})

--- Called by installer.lua before the UI starts.
---@param replacement_api react.ReplacementApi
function notifications.install(replacement_api)
	replacement_api.ReplaceRecipe(base_popups, Replacement)
end

return notifications
