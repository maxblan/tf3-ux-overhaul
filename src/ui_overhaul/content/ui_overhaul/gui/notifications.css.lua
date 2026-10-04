-- Notification ridge: the count badge of a group sits on the top right corner of its icon, partly
-- outside, like the gamepad hint the base puts on the bottom right corner (notifications.css.lua).
-- The badge itself is the base "bubble" (entity_window.css.lua). Members other than the shown one
-- render empty layouts next to it; no spacing, so the icon keeps the base size.
-- Subsidy icons (notifications.lua): one colour per state, each with at least 7:1 contrast to the
-- white symbol and ring (WCAG AAA), also on hover and while pressed (darker shades: the game's
-- hover shades are lighter and would drop below 7:1). The timer ring is plain white (base: 75 %).
local ssu = require("::/gui/main/stylesheetutil.lua")

-- contrast to white: base / hover / pressed
---@type table<string, string[]>
local STATES = {
	["uio-subsidy-offer"] = { "#1453A6", "#11478D", "#0E3C78" }, -- available: blue, 7.5 / 9.1 / 10.9
	["uio-subsidy-active"] = { "#9C3700", "#852F00", "#702800" }, -- in progress: orange, 7.1 / 8.7 / 10.5
	["uio-subsidy-complete"] = { "#176024", "#14521F", "#11451A" }, -- effect active: green, 7.7 / 9.3 / 11.1
	["uio-subsidy-failed"] = { "#A8201A", "#8F1B16", "#791713" }, -- failed: red, 7.3 / 9.0 / 10.8
	["uio-subsidy-missed"] = { "#4D4D4D", "#414141", "#373737" }, -- offer missed: grey, 8.5 / 10.2 / 11.9
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
