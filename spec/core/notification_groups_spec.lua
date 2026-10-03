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

local function keys_and_ids(result)
	local out = {}
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
			local seen, current = {}, nil
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
end)
