local groups = require("/ui_overhaul/core/notification_groups.lua")

local RATING = "::/game_mechanics/notifications/types/town_rating_warning_nonperistent.script"
local LINE = "::/game_mechanics/notifications/types/line_warning.script"
local VEHICLE = "::/game_mechanics/notifications/types/vehicle_warning.script"
local SUBVENTION = "::/game_mechanics/notifications/types/subvention_notification.script"
local AVAILABILITY = "::/game_mechanics/notifications/types/availability.script"

local function item(id, timestamp, kind, params)
	return { id = id, timestamp = timestamp, notification = { type = kind, params = params } }
end

local function rating(id, timestamp, key)
	return item(id, timestamp, RATING, { entities = { { 100 + id, 1 } }, param = { key = key } })
end

---@param result uo.core.notification_groups.Group[]
---@return string[]
local function keys_and_ids(result)
	local out = {} ---@type string[]
	for i, group in ipairs(result) do
		out[i] = table.concat(groups.ids(group), ",")
	end
	return out
end

describe("notification_groups", function()
	describe("key", function()
		it("groups town rating warnings by rating key, not by town", function()
			local a = rating(1, 0, "noise").notification
			local b = rating(2, 0, "noise").notification
			local c = rating(3, 0, "pollution").notification
			assert.are.equal(groups.key(a, 1), groups.key(b, 2))
			assert.is_true(groups.key(a, 1) ~= groups.key(c, 3))
		end)

		it("groups line problems by problem", function()
			local late = { lineProblem = 4, okModes = {} }
			local a = item(1, 0, LINE, { entities = { { 7, 1 } }, param = late }).notification
			local b = item(2, 0, LINE, { entities = { { 8, 1 } }, param = { lineProblem = 4 } }).notification
			local c = item(3, 0, LINE, { entities = { { 9, 1 } }, param = { lineProblem = 2 } }).notification
			assert.are.equal(groups.key(a, 1), groups.key(b, 2))
			assert.is_true(groups.key(a, 1) ~= groups.key(c, 3))
		end)

		it("groups number and string params by value", function()
			local a = item(1, 0, VEHICLE, { entities = {}, param = 3 }).notification
			local b = item(2, 0, VEHICLE, { entities = {}, param = 3 }).notification
			local c = item(3, 0, VEHICLE, { entities = {}, param = 5 }).notification
			assert.are.equal(groups.key(a, 1), groups.key(b, 2))
			assert.is_true(groups.key(a, 1) ~= groups.key(c, 3))
		end)

		it("keeps statuses apart", function()
			local a = item(1, 0, SUBVENTION, { id = "x", status = 1 }).notification
			local b = item(2, 0, SUBVENTION, { id = "y", status = 1 }).notification
			local c = item(3, 0, SUBVENTION, { id = "z", status = 2 }).notification
			assert.are.equal(groups.key(a, 1), groups.key(b, 2))
			assert.is_true(groups.key(a, 1) ~= groups.key(c, 3))
		end)

		it("groups types without a param by type", function()
			local a = item(1, 0, AVAILABILITY, { models = { "a" } }).notification
			local b = item(2, 0, AVAILABILITY, { models = { "b" } }).notification
			assert.are.equal(groups.key(a, 1), groups.key(b, 2))
			assert.is_true(groups.key(a, 1) ~= groups.key(rating(3, 0, "noise").notification, 3))
		end)

		it("does not group params of an unknown shape", function()
			local a = item(1, 0, LINE, { param = { something = 1 } }).notification
			local b = item(2, 0, LINE, { param = { something = 1 } }).notification
			assert.is_true(groups.key(a, 1) ~= groups.key(b, 2))
			local c = item(3, 0, LINE, { param = 1, status = {} }).notification
			local d = item(4, 0, LINE, { param = 1, status = {} }).notification
			assert.is_true(groups.key(c, 3) ~= groups.key(d, 4))
		end)

		it("survives missing data", function()
			assert.are.equal("string", type(groups.key(nil, 1)))
			assert.are.equal("string", type(groups.key({ type = RATING }, 2)))
			assert.are.equal("string", type(groups.key({ type = RATING, params = 5 }, 3)))
		end)
	end)

	describe("build", function()
		it("orders groups by their oldest member and members newest first", function()
			local result = groups.build({
				rating(5, 50, "noise"),
				rating(1, 10, "noise"),
				rating(2, 20, "pollution"),
				rating(3, 30, "noise"),
				rating(4, 40, "pollution"),
			})
			assert.are.same({ "5,3,1", "4,2" }, keys_and_ids(result))
			assert.are.equal(10, result[1].oldest)
		end)

		it("breaks timestamp ties by id", function()
			local result = groups.build({ rating(2, 10, "noise"), rating(1, 10, "noise"), rating(3, 10, "x") })
			assert.are.same({ "2,1", "3" }, keys_and_ids(result))
		end)

		it("leaves a single notification alone", function()
			local result = groups.build({ rating(1, 10, "noise") })
			assert.are.equal(1, #result)
			assert.are.equal(1, #result[1].members)
		end)

		it("returns no groups for no items", function()
			assert.are.same({}, groups.build({}))
			assert.are.same({}, groups.build(nil))
		end)

		it("does not change the input", function()
			local items = { rating(2, 20, "noise"), rating(1, 10, "noise") }
			groups.build(items)
			assert.are.equal(2, items[1].id)
		end)
	end)

	describe("cursor", function()
		local group = groups.build({ rating(1, 10, "noise"), rating(2, 20, "noise"), rating(3, 30, "noise") })[1]

		it("starts at the newest member", function()
			assert.are.equal(1, groups.index(group, nil))
			assert.are.equal(3, group.members[groups.index(group, nil)].id)
		end)

		it("falls back to the newest member when the current one is gone", function()
			assert.are.equal(1, groups.index(group, 99))
		end)

		it("visits every member and wraps", function()
			local seen, current = {}, nil ---@type integer[], integer?
			for i = 1, 4 do
				current = groups.next_id(group, current)
				seen[i] = current
			end
			assert.are.same({ 2, 1, 3, 2 }, seen)
		end)

		it("stays on a single member", function()
			local single = groups.build({ rating(7, 10, "noise") })[1]
			assert.are.equal(7, groups.next_id(single, 7))
		end)
	end)

	describe("place", function()
		local function subsidy(id, timestamp, status)
			return item(id, timestamp, SUBVENTION, { uid = id, id = "x", status = status })
		end

		---@param items uo.core.notification_groups.Item[]
		---@param previous? uo.core.notification_groups.Tiles
		---@return uo.core.notification_groups.Group[], uo.core.notification_groups.Tiles
		local function place(items, previous)
			return groups.place(groups.build(items), previous)
		end

		---@param placed uo.core.notification_groups.Group[]
		---@return string[]
		local function tiles(placed)
			local out = {} ---@type string[]
			for i, group in ipairs(placed) do out[i] = group.tile .. "=" .. table.concat(groups.ids(group), ",") end
			return out
		end

		it("keeps the icon and its place when a member's status changes", function()
			local before, state = place({ subsidy(1, 10, 1), rating(2, 20, "noise"), subsidy(3, 30, 2) })
			assert.are.same({ "t1=1", "t2=2", "t3=3" }, tiles(before))
			local after = place({ subsidy(1, 10, 2), rating(2, 20, "noise"), subsidy(3, 30, 2) }, state)
			-- 1 joins the icon of 3 by status; the icon of the older member 1 stays where it was
			assert.are.same({ "t1=3,1", "t2=2" }, tiles(after))
		end)

		it("resolves nothing on a status change", function()
			local _placed, state = place({ subsidy(1, 10, 1), subsidy(2, 20, 1) })
			local after
			after, state = place({ subsidy(1, 10, 2), subsidy(2, 20, 1) }, state)
			-- the group splits: one icon each, both notifications still shown
			assert.are.same({ "t1=1", "t2=2" }, tiles(after))
			assert.is_true(groups.shown(state, 1))
			assert.is_true(groups.shown(state, 2))
		end)

		it("resolves a notification that leaves the ridge", function()
			local _placed, state = place({ subsidy(1, 10, 1), subsidy(2, 20, 1) })
			local after
			after, state = place({ subsidy(2, 20, 1) }, state)
			assert.are.same({ "t1=2" }, tiles(after))
			assert.is_false(groups.shown(state, 1))
			assert.is_true(groups.shown(state, 2))
			assert.is_false(groups.shown(nil, 2))
		end)

		it("gives a replaced notification a new icon at the end, as the base does", function()
			-- the game replaces a subsidy whose status changes: the old id goes, a new one comes
			local _placed, state = place({ subsidy(1, 10, 1), rating(2, 20, "noise") })
			local after
			after, state = place({ rating(2, 20, "noise"), subsidy(5, 50, 2) }, state)
			assert.are.same({ "t2=2", "t3=5" }, tiles(after))
			assert.is_false(groups.shown(state, 1))
		end)

		it("keeps an icon in place when its oldest member goes", function()
			local items = { rating(1, 10, "noise"), rating(2, 20, "pollution"), rating(3, 30, "noise") }
			local before, state = place(items)
			assert.are.same({ "t1=3,1", "t2=2" }, tiles(before))
			local after = place({ items[2], items[3] }, state)
			assert.are.same({ "t1=3", "t2=2" }, tiles(after))
		end)

		it("never reuses an icon key", function()
			local _placed, state = place({ rating(1, 10, "noise") })
			state = select(2, place({}, state))
			local after = place({ rating(2, 5, "noise"), rating(3, 20, "pollution") }, state)
			assert.are.same({ "t2=2", "t3=3" }, tiles(after))
		end)

		it("is stable when placed again", function()
			local items = { rating(1, 10, "noise"), rating(2, 20, "pollution"), rating(3, 30, "noise") }
			local first, state = place(items)
			local second = place(items, state)
			assert.are.same(tiles(first), tiles(second))
		end)
	end)
end)
