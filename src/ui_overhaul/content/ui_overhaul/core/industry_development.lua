--- Whether and how fast an industry grows, as the game's industries script decides it
-- (game_mechanics/industries/industries.script.tl), from plain facts the GUI reads. Pure Lua.
--
-- Every half year (industries_config: extendTimeSpanYears = 0.5) an industry below its maximum
-- level, not owned by the player, not developed by hand, producing something and not counting down
-- to closure, expands with the chance
--     clamp((rating - 0.25) / 0.5, 0, 1),  rating = production rating x min(1, shipped / output)
-- unless something stands where the next level would go.
-- @module ui_overhaul.core.industry_development
local industry_development = {}

--- Chance (0..1) per check of expanding, from the production rating (0..1), the cargo shipped and
-- the output per year.
function industry_development.chance(production_rating, shipped, output)
	if not output or output <= 0 then return 0 end
	local rating = (production_rating or 0) * math.min(1, (shipped or 0) / output)
	return math.max(0, math.min(1, (rating - 0.25) / 0.5)), rating
end

--- Why the industry does not expand, as a list of keys (the GUI words them), first the one that
-- decides. `f` = { level, maxLevel, manual, playerOwned, output, closing, blocked, chance }.
-- Keys: "max_level", "manual", "player_owned", "closing", "no_output", "blocked", "not_shipped".
function industry_development.blockers(f)
	local result = {}
	if f.level >= f.maxLevel then result[#result + 1] = "max_level" return result end
	if f.manual then result[#result + 1] = "manual" end
	if f.playerOwned then result[#result + 1] = "player_owned" end
	if f.closing then result[#result + 1] = "closing" end
	if (f.output or 0) <= 0 then result[#result + 1] = "no_output" end
	if f.blocked then result[#result + 1] = "blocked" end
	if #result == 0 and (f.chance or 0) <= 0 then result[#result + 1] = "not_shipped" end
	return result
end

return industry_development
