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
local priority = require("ui_overhaul_1::/ui_overhaul/gui/priority.lua")

---`subvention_util.makeDefaultCardData`; a wrapper passes any further arguments on unchanged.
---@alias uo.gui.subsidies.MakeCardData fun(
---	state: game.game_mechanics.subventions.subvention.ISubvention, icon: string, ...: any):
---	game.game_mechanics.subventions.subvention.SubventionCardData

---@class uo.gui.subsidies
local subsidies = {}

---@param v number
---@return number
local function clamp01(v)
	if v ~= v then return 0 end -- NaN
	return math.max(0, math.min(1, v))
end

---@return integer
local function now()
	return api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME).gameTime
end

---@return integer
local function millis_per_day()
	return api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_SPEED).millisPerDay
end

---@param ms number
---@return string
local function duration(ms)
	return util.formatDurationWithCurrentCalenderSpeed(math.floor(math.max(ms, 0)), millis_per_day())
end

--- Adds the labels and rings to the base card data of `state` (in place).
---@param card game.game_mechanics.subventions.subvention.SubventionCardData
---@param state game.game_mechanics.subventions.subvention.ISubvention
---@return game.game_mechanics.subventions.subvention.SubventionCardData
function subsidies.extend(card, state)
	local data = state.data
	if card.status == "Proposed" then
		---@type string?
		local ends
		if (data.expireDurationProposed or -1) > -1 then
			local left = state.spawnTime + data.expireDurationProposed - now()
			ends = lang_util.format(_("Offer ends in {duration}"), { duration = duration(left) })
			card.expireDuration = { value = clamp01(left / data.expireDurationProposed), name = ends }
		end
		local deadline = card.deadline
		if deadline then
			local time_limit = lang_util.format(_("Time limit: {duration}"), { duration = deadline.name })
			deadline.name = ends and time_limit .. " - " .. ends or time_limit
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

--- Called by installer.lua before the UI starts.
---@param _replacement_api react.ReplacementApi
function subsidies.install(_replacement_api)
	-- the previous function in the chain (the game's, or another mod's wrapper around it), called with
	-- whatever the wrapper got
	if type(subvention_util.makeDefaultCardData) ~= "function" then
		error("subvention_util.makeDefaultCardData not found")
	end
	priority.chain(subvention_util, "makeDefaultCardData",
	---@param original uo.gui.subsidies.MakeCardData
	---@return uo.gui.subsidies.MakeCardData
	function(original)
		---@type uo.gui.subsidies.MakeCardData
		return function(state, icon, ...)
			local card = original(state, icon, ...)
			local ok, err = pcall(subsidies.extend, card, state)
			if not ok then debugPrint("[ui_overhaul] subsidy texts failed: ", tostring(err)) end
			return card
		end
	end)
	debugPrint("[ui_overhaul] subsidy texts installed")
end

return subsidies
