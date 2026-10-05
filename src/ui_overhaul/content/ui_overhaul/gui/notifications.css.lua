-- Notification ridge: the count badge of a group sits on the top right corner of its icon, partly
-- outside, like the gamepad hint the base puts on the bottom right corner (notifications.css.lua).
-- The badge itself is the base "bubble" (entity_window.css.lua). Members other than the shown one
-- render empty layouts next to it; no spacing, so the icon keeps the base size.
-- Notification icons (ridge, hover card, notification log): every type in a shade of the game's
-- colour with at least 7:1 contrast to the white symbol and ring (WCAG AAA), also on hover and while
-- pressed (darker shades: the game's hover shades are lighter and would drop below 7:1). The game's
-- yellow Caution had 1.6:1, its green Achievement 2.5:1, its red Problem and blue Info 5.4:1.
-- Subsidy icons (notifications.lua) get one such colour per state instead of the game's purple.
-- The timer ring of a subsidy is plain white (base: 75 %).
-- The icon colours apply in this mod's ridge and hover cards, where every icon lies in a component of
-- class uio-notification-icon (notifications.lua), and in windows (Line Manager, entity windows,
-- notification log) while the feature is shown, which carry its class then (styles.lua). Without it,
-- or once the ridge falls back to the base one, the icons are the game's.
local ssu = require("::/gui/main/stylesheetutil.lua")

-- where the colours apply: this mod's icons, and windows while the feature is shown
local SCOPES = { "R::Component!uio-notification-icon ", "Window!uio-on-notifications " } -- styles.on("notifications")

-- contrast to white: base / hover / pressed
---@type table<string, string[]>
local STATES = {
	["uio-subsidy-offer"] = { "#1453A6", "#11478D", "#0E3C78" }, -- available: blue, 7.5 / 9.1 / 10.9
	["uio-subsidy-active"] = { "#9C3700", "#852F00", "#702800" }, -- in progress: orange, 7.1 / 8.7 / 10.5
	["uio-subsidy-complete"] = { "#176024", "#14521F", "#11451A" }, -- effect active: green, 7.7 / 9.3 / 11.1
	["uio-subsidy-failed"] = { "#A8201A", "#8F1B16", "#791713" }, -- failed: red, 7.3 / 9.0 / 10.8
	["uio-subsidy-missed"] = { "#4D4D4D", "#414141", "#373737" }, -- offer missed: grey, 8.5 / 10.2 / 11.9
}

-- the game's notification types (notification_react_util.tl type2class), contrast to white:
-- base / hover / pressed; subsidies (type opportunity) are coloured by state above
---@type table<string, string[]>
local TYPES = {
	caution = { "#795000", "#674400", "#573A00" }, -- amber, 7.1 / 8.7 / 10.4 (game: #FFC40C, 1.6)
	problem = { "#B0151D", "#961219", "#7F0F15" }, -- red, 7.1 / 8.8 / 10.6 (game: #CE2029, 5.4)
	info = { "#2E50B8", "#27449C", "#213A84" }, -- blue, 7.1 / 8.8 / 10.5 (game: #2D68C4, 5.4)
	achievement = { "#28650C", "#22560A", "#1D4909" }, -- green, 7.1 / 8.7 / 10.5 (game: #4CBB17, 2.5)
	unknown = { "#4D4D4D", "#414141", "#373737" }, -- grey, 8.5 / 10.2 / 11.9 (game: the same base)
}

---@param hex string "#RRGGBB"
---@return number[]
local function rgb(hex)
	return { tonumber(hex:sub(2, 3), 16) / 255, tonumber(hex:sub(4, 5), 16) / 255, tonumber(hex:sub(6, 7), 16) / 255, 1 }
end

---@return table[]
function data()
	local result = {}
	local add = ssu.makeAdder(result)
	add("R::NotificationPopups R::NotificationIcon TextView!bubble!uio-notification-count", {
		gravity = { 1.0, 0.0 },
		anchorPoint = { 0.7, 0.3 },
	})
	add("R::NotificationPopups R::NotificationIcon BoxLayout!uio-notification-members", {
		innerSpacing = { 0, 0 },
	})

	-- the icon carries "icon-size" next to its type class: one class more than the base rules
	---@param type_class string
	---@param prefix string "" or a state such as "Button:hover ", inside a scope
	---@return string
	local function type_selectors(type_class, prefix)
		local list = {} ---@type string[]
		for _i, scope in ipairs(SCOPES) do
			list[#list + 1] = scope .. prefix .. "R::NotificationProgressIcon R::Component!icon-size!" .. type_class
			list[#list + 1] = scope .. prefix .. "R::NotificationSimpleIcon ImageView!icon-size!" .. type_class
			-- the hovered or pressed button around the scope (in the ridge the button is outside it)
			if prefix ~= "" then
				list[#list + 1] = prefix .. scope .. "R::NotificationProgressIcon R::Component!icon-size!" .. type_class
				list[#list + 1] = prefix .. scope .. "R::NotificationSimpleIcon ImageView!icon-size!" .. type_class
			end
		end
		return table.concat(list, ", ")
	end
	for type_class, shades in pairs(TYPES) do
		add(type_selectors(type_class, ""), { backgroundColor1 = rgb(shades[1]) })
		add(type_selectors(type_class, "Button:hover "), { backgroundColor1 = rgb(shades[2]) })
		add(type_selectors(type_class, "Button:active "), { backgroundColor1 = rgb(shades[3]) })
	end

	-- the colour table of default_colors.gres: name -> colour
	---@type table<string, game.gui.main.color_util.GResColor>
	local colorDefault = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/default_colors.gres")).data
	-- the base status classes (!pending, !failed) are listed too, so these rules outrank the base ones
	---@param class string
	---@param prefix string
	---@return string
	local function selectors(class, prefix)
		---@type string[]
		local list = {}
		for _i, status in ipairs({ "", "!pending", "!failed" }) do
			local state = prefix .. "R::Component!" .. class
			list[#list + 1] = state .. " R::NotificationProgressIcon R::Component!opportunity" .. status
			list[#list + 1] = state .. " R::NotificationSimpleIcon ImageView!opportunity" .. status
		end
		return table.concat(list, ", ")
	end
	for class, shades in pairs(STATES) do
		add(selectors(class, ""), { backgroundColor1 = rgb(shades[1]) })
		add(selectors(class, "Button:hover "), { backgroundColor1 = rgb(shades[2]) })
		add(selectors(class, "Button:active "), { backgroundColor1 = rgb(shades[3]) })
		add("R::Component!" .. class .. " R::NotificationProgressIcon ImageView!progress",
			{ color = colorDefault.NeutralLightest })
	end
	return result
end
