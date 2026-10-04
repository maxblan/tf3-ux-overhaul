--- Subsidies say how much time they have, in the places the game already shows them:
--   * an offer gets a timer ring (the notification icon) and bar (its hover) for the time until the
--     offer ends, and its card names it: "Time limit: 2 years - Offer ends in 3 months" (base: the
--     offer just disappears as "Subsidy Missed", and the time limit is shown without a label)
--   * an active subsidy's card says "Time limit: 2 years" and its bar "1 year 3 months left"
--   * a completed subsidy's ring and bar show how long its effect lasts: "Effect ends in 4 years"
-- Patches the module function subvention_util.makeDefaultCardData, which all four subsidy scripts
-- call through the module table, in the GUI state only (the simulation has its own Lua state).
-- The ridge colours by state are in notifications.lua / notifications.css.lua.
-- @module ui_overhaul.gui.subsidies
local subvention_util = require("::/game_mechanics/subventions/subvention_util.tl")
local util = require("::/scripts/util.tl")
local lang_util = require("::/scripts/lang_util.tl")

local subsidies = {}

local function clamp01(v)
	if v ~= v then return 0 end -- NaN
	return math.max(0, math.min(1, v))
end

local function now()
	return api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME).gameTime
end

local function millis_per_day()
	return api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_SPEED).millisPerDay
end

local function duration(ms)
	return util.formatDurationWithCurrentCalenderSpeed(math.floor(math.max(ms, 0)), millis_per_day())
end

--- Adds the labels and rings to the base card data of `state` (in place).
function subsidies.extend(card, state)
	local data = state.data
	if card.status == "Proposed" then
		local time_limit = card.deadline and lang_util.format(_("Time limit: {duration}"), { duration = card.deadline.name })
		if (data.expireDurationProposed or -1) > -1 then
			local left = state.spawnTime + data.expireDurationProposed - now()
			local ends = lang_util.format(_("Offer ends in {duration}"), { duration = duration(left) })
			card.expireDuration = { value = clamp01(left / data.expireDurationProposed), name = ends }
			if card.deadline then card.deadline.name = time_limit .. " - " .. ends end
		elseif card.deadline then
			card.deadline.name = time_limit
		end
	elseif card.status == "Active" then
		if card.deadline then
			card.deadline.name = lang_util.format(_("Time limit: {duration}"), { duration = card.deadline.name })
		end
		local e = card.expireDuration
		if e and e.value >= 0 then
			e.name = lang_util.format(_("{duration} left"), { duration = e.name })
		end
	elseif card.status == "Complete" and state.completedTime and (data.effectDuration or 0) > 0 then
		local left = state.completedTime + data.effectDuration - now()
		card.expireDuration = {
			value = clamp01(left / data.effectDuration),
			name = lang_util.format(_("Effect ends in {duration}"), { duration = duration(left) }),
		}
	end
	return card
end

--- Called from the react-replacement-config before the UI starts.
function subsidies.install(_replacement_api)
	local original = subvention_util.makeDefaultCardData
	if type(original) ~= "function" then error("subvention_util.makeDefaultCardData not found") end
	subvention_util.makeDefaultCardData = function(state, icon, ...)
		local card = original(state, icon, ...)
		local ok, err = pcall(subsidies.extend, card, state)
		if not ok then debugPrint("[ui_overhaul] subsidy texts failed: ", tostring(err)) end
		return card
	end
	debugPrint("[ui_overhaul] subsidy texts installed")
end

return subsidies
