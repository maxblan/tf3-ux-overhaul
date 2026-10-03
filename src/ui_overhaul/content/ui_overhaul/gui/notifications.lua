--- Notification ridge (the row of icons at the top centre) with one icon per kind of notification.
-- Notifications of the same kind (core/notification_groups.lua) share an icon with a count badge:
--   * left-click does what a click on the shown notification does in the base game, then shows
--     the next one of the group (newest first, wrapping), so repeated clicks visit each
--   * right-click (gamepad: IA_OPTION2) dismisses the whole group
--   * the hover card is the base card of the shown notification, with "2 of 3" next to the title
-- A group of one looks and behaves like the base icon.
-- A Lua conversion of the base ridge (game_mechanics/notifications/gui/notification_popups.tl),
-- registered under the base recipe names so the base stylesheet applies, installed through a
-- react-replacement-config (notifications.script.lua). If rendering fails, the base ridge is shown.
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
local groups = require("/ui_overhaul/core/notification_groups.lua")

local notifications = {}

--- Counts of the last render, for the in-game checks: raw notifications shown, icons, largest group.
notifications.stats = { raw = 0, groups = 0, largest = 0 }

local SFX_PATH = "::/game_mechanics/notifications/gui/sound/notification_sfx.gres"

local reported = {}
local function report(what, err)
	if reported[what] then return end
	reported[what] = true
	debugPrint("[ui_overhaul] notification ridge: ", what, " failed: ", tostring(err))
end

--- `fn` wrapped so that an error in an engine callback is logged once instead of escaping.
local function safe(what, fn, fallback)
	return function(...)
		local ok, result = pcall(fn, ...)
		if ok then return result end
		report(what, result)
		return fallback
	end
end

local function empty()
	return builtin.BoxLayout{}
end

local sfx_data
local function sfx()
	if sfx_data == nil then
		local ok, data = pcall(function() return api.gui.genericRep.get(api.gui.genericRep.find(SFX_PATH)).data end)
		sfx_data = ok and data or false
	end
	return sfx_data or nil
end

-- Members of a group mount and unmount together (a group is dismissed at once, a saved game loads
-- several), so each sound plays at most once per GUI step.
local played = {}
local function play(kind, sounds)
	if not sounds or played[kind] then return end
	played[kind] = true
	api.gui.sound.playRandomSoundEffect(sounds)
end

-- The click action of each mounted member, by notification id. Ids are unique and there is one ridge.
local click_handlers = {}

-- Hover card (1:1 from the base, plus the position in the group) ---------------------------------

local NotificationPopupContent = react.RegisterRecipe("NotificationPopupContent", function(params, guiType, position)
	local mainContent = builtin.Button {
		content = builtin.BoxLayout{
			orientation = builtin.type.Orientation.Horizontal,
			children = {
				params.previewImage and builtin.ImageView {
					meta = { class = "preview-image" },
					path = params.previewImage,
					scaling = builtin.type.ImageViewScaling.AutoFit,
				} or notification_react_util.NotificationSimpleIcon{
					icon = params.icon,
					status = params.status,
					type = guiType,
				} or nil,
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

local NotificationPopup = react.RegisterRecipe("NotificationPopup", function(params)
	local dataStateFn = util.useFn(params.notification.type .. "@useDataState")
	local dataState = dataStateFn and dataStateFn(params.notification.params, params.notification.simParams) or nil
	local guiType = notification_util.getGuiTypeFromNotificationType(params.notification.type)
	local position = params.count > 1
		and lang_util.format(_("{index} of {count}"), { index = tostring(params.index), count = tostring(params.count) })
		or nil

	return builtin.BoxLayout{orientation = builtin.type.Orientation.Vertical, children = {
		builtin.Component {
			meta = {
				class = "notification-popup",
				disableFocusableRecursive = true,
			},
			layout = builtin.BoxLayout{
				orientation = builtin.type.Orientation.Vertical,
				children = {
					dataState and NotificationPopupContent(dataState, guiType, position) or nil
				},
			},
		},
	}}
end)

local NotificationInfo = react.RegisterRecipe("NotificationInfo", function(number, notificationId, notification, index,
		count)
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
					index = index,
					count = count,
				})
			},
		},
	} or builtin.BoxLayout{}
end)

-- Icons -------------------------------------------------------------------------------------------

local function icon(dataState, guiType)
	if dataState.progress ~= nil or (dataState.progresses ~= nil and #dataState.progresses > 0) then
		return notification_react_util.NotificationProgressIcon {
			icon = dataState.icon,
			status = dataState.status,
			type = guiType,
			percentage = dataState.progress and dataState.progress.percentage or dataState.progresses[1].percentage,
		}
	end
	return notification_react_util.NotificationSimpleIcon{
		icon = dataState.icon,
		status = dataState.status,
		type = guiType,
	}
end

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

local function on_member_unmount(notificationId)
	click_handlers[notificationId] = nil
	local data = sfx()
	play("resolve", data and data.Resolve)
end

-- One notification of a group: its data state (a hook, so one recipe per notification, keyed by
-- id), the base mount and unmount sounds, and the icon while it is the one the group shows.
local function render_member(params)
	local dataStateFn = util.useFn(params.notification.type .. "@useDataState")
	local dataState = dataStateFn and dataStateFn(params.notification.params, params.notification.simParams) or nil
	local guiType = notification_util.getGuiTypeFromNotificationType(params.notification.type)
	local id = params.notificationId

	react.onMount(safe("sound", function() on_member_mount(id, dataState) end))
	react.onUnmount(safe("sound", function() on_member_unmount(id) end))

	click_handlers[id] = dataState and dataState.onClick or false
	if not (params.current and dataState) then return empty() end
	return builtin.BoxLayout{ children = { icon(dataState, guiType) } }
end

local Member = react.RegisterRecipe("UioNotificationMember", function(params)
	local ok, node = pcall(render_member, params)
	if ok then return node end
	report("icon", node)
	return empty()
end)

-- The icon of a group. Registered as the base "NotificationIcon", which the base stylesheet sizes
-- and animates; the button stays the same node while the shown member changes.
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

local NotificationIcon = react.RegisterRecipe("NotificationIcon", function(params)
	local ok, node = pcall(render_tile, params)
	if ok then return node end
	report("icon group", node)
	return empty()
end)

-- Ridge -------------------------------------------------------------------------------------------

local function read_notifications()
	local notificationsStateNative = notification_util.externalGetNotificationsStateNative()
	if notificationsStateNative == nil then
		return {}
	end

	local guiNotifications = {}
	local history = notification_util.getHistoryFromNative(notificationsStateNative)

	local nativeNotifications = notificationsStateNative:find("notifications")
	for _i, id in ipairs(history) do
		local notificationEntryNative = nativeNotifications:find(id)
		if notificationEntryNative ~= nil and not notificationEntryNative:find("dismissed") then
			local entry = notification_util.getNotificationEntryFromNative(notificationsStateNative, id)
			guiNotifications[#guiNotifications + 1] = {
				entry = entry,
				id = id,
				type = notification_util.getGuiTypeFromNotificationType(entry.notification.type),
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

local function make_groups(guiNotifications)
	local items = {}
	for _i, guiNotification in ipairs(guiNotifications) do
		local entry = guiNotification.entry
		if entry.notification and not entry.dismissed then
			items[#items + 1] = { id = guiNotification.id, timestamp = entry.timestamp, notification = entry.notification }
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

local function render()
	local focusableState = react.useState(false)
	local gamepadFocusedState = react.useState(false)
	local hoveredListIndexState = react.useState(-1)
	local cursorState = react.useState({}) -- group key -> id of the notification the group shows
	local animatedRef = react.useRef(false)
	local enteredListIndexRef = react.useRef(-1)
	local listRef = react.useNodeRef(builtin.Component)
	local notificationIconRef = react.useNodeRef(builtin.Component)

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

	local groupList = make_groups(guiNotificationsState:old())
	local cursor = cursorState:old() or {}

	local function current_index(group)
		return groups.index(group, cursor[group.key])
	end

	local function dismiss(group)
		local newGuiNotificationsState = table_util.copy(guiNotificationsState:old())
		local ids = {}
		for _i, member in ipairs(group.members) do ids[member.id] = true end
		for _i, guiNotification in ipairs(newGuiNotificationsState) do
			if ids[guiNotification.id] then guiNotification.entry.dismissed = true end
		end
		local cmds = {}
		for i, member in ipairs(group.members) do
			cmds[i] = api.cmd.makeScriptingSendEventCmd("", "Notifications", "dismiss", { id = member.id })
		end
		-- Commands run in order: the committed one goes last, so the ridge reads the engine again only
		-- after all members are dismissed.
		for i = 2, #cmds do api.cmd.sendCommand(cmds[i]) end
		commit(newGuiNotificationsState, cmds[1])
	end

	local function advance(group, currentId)
		local newCursor = {}
		for key, id in pairs(cursorState:old() or {}) do newCursor[key] = id end
		newCursor[group.key] = groups.next_id(group, currentId)
		cursorState:set(newCursor)
	end

	local children = {}
	for k, group in ipairs(groupList) do
		local currentId = group.members[current_index(group)].id
		local tileParams = {
			meta = { localKey = group.key },
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

	react.onStep(function()
		played = {}
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

	if #children == 0 and focusableState:old() then
		focusableState:set(false)
	end

	local hovered = (hoveredListIndexState:old() and hoveredListIndexState:old() >= 0
			and (gamepadFocusedState:old() or isMouseInputState:old()))
		and groupList[hoveredListIndexState:old()]
		or nil
	local hoveredIndex = hovered and current_index(hovered) or nil
	local hoveredMember = hovered and hovered.members[hoveredIndex] or nil
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
						NotificationInfo(offsetState:old(), hoveredMember.id, hoveredMember.notification, hoveredIndex,
							#hovered.members),
					},
				}
			} or nil,
		}
	}
end

--- True once rendering failed; the base ridge is shown from then on.
notifications.failed = false

local Replacement = react.RegisterRecipe("NotificationPopups", function(...)
	if not notifications.failed then
		local ok, node = pcall(render)
		if ok then return node end
		notifications.failed = true
		debugPrint("[ui_overhaul] notification ridge failed, showing the base one: ", tostring(node))
	end
	return builtin.BoxLayout{ children = { react.CallOriginalRecipe(base_popups, ...) } }
end)

--- Called from the react-replacement-config before the UI starts.
function notifications.install(replacement_api)
	replacement_api.ReplaceRecipe(base_popups, Replacement)
end

return notifications
