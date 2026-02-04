--[[
================================================================================
TEST: Idle Game Ground Items
================================================================================
Tests ground item drop, pickup, find_nearest, and grid clear functionality.

NOTE: This test file is created for future use when the ground items system
is implemented. Currently, the terrain.lua module has dependencies on the
forma library which is not available in headless test environment.

When the ground items system is refactored to be headless-safe, this test
will provide comprehensive coverage of:
- drop_item(x, y, kind, amount)
- pickup functionality
- find_nearest functionality
- grid clear functionality

Run with: lua assets/scripts/tests/test_idle_ground_items.lua
]]

--------------------------------------------------------------------------------
-- Setup (REQUIRED for tests to find modules)
--------------------------------------------------------------------------------

-- Standard test path setup
package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/?/init.lua"

local t = require("tests.test_runner")

--------------------------------------------------------------------------------
-- Mock Ground Items Implementation (for testing)
--------------------------------------------------------------------------------

-- Simple mock implementation for testing ground items functionality
local MockGroundItems = {}

function MockGroundItems.new()
    local self = {
        _ground_items = {},
        _next_item_id = 1,
        _current_grid = nil
    }

    -- Valid item kinds
    local VALID_ITEM_KINDS = {
        wood = true,
        stone = true,
        food = true,
        gold = true
    }

    function self.setCurrentGrid(grid)
        self._current_grid = grid
        self.clear_ground_items()
    end

    function self.drop_item(x, y, kind, amount)
        -- Validate parameters
        if not x or not y or not kind or not amount then
            error("drop_item: x, y, kind, amount required")
        end

        -- Validate coordinates
        if not self._current_grid then
            error("drop_item: no current grid set")
        end

        if x < 0 or x >= self._current_grid.width or y < 0 or y >= self._current_grid.height then
            return nil, "Invalid coordinates"
        end

        -- Validate item kind
        if not VALID_ITEM_KINDS[kind] then
            return nil, "Invalid item kind: " .. tostring(kind)
        end

        -- Validate amount
        amount = tonumber(amount)
        if not amount or amount <= 0 then
            return nil, "Invalid amount: must be positive number"
        end

        -- Create ground item with monotonic ID
        local item = {
            id = self._next_item_id,
            x = x,
            y = y,
            kind = kind,
            amount = amount,
            created_at = os.time()
        }

        -- Increment monotonic ID counter
        self._next_item_id = self._next_item_id + 1

        -- Add to ground items table
        self._ground_items[item.id] = item

        return item.id
    end

    function self.get_ground_items()
        return self._ground_items
    end

    function self.get_items_at(x, y)
        local items_at_position = {}

        for id, item in pairs(self._ground_items) do
            if item.x == x and item.y == y then
                table.insert(items_at_position, item)
            end
        end

        return items_at_position
    end

    function self.clear_ground_items()
        local count = 0
        for _ in pairs(self._ground_items) do
            count = count + 1
        end

        self._ground_items = {}
        self._next_item_id = 1

        return count
    end

    -- Future functions (placeholders)
    function self.pickup_item(item_id)
        local item = self._ground_items[item_id]
        if not item then
            return false, "Item not found"
        end

        self._ground_items[item_id] = nil
        return true, item
    end

    function self.find_nearest_item(x, y, kind)
        local nearest_item = nil
        local nearest_distance = math.huge

        for id, item in pairs(self._ground_items) do
            if not kind or item.kind == kind then
                local distance = math.sqrt((item.x - x)^2 + (item.y - y)^2)
                if distance < nearest_distance then
                    nearest_distance = distance
                    nearest_item = item
                end
            end
        end

        return nearest_item, nearest_distance
    end

    return self
end

--------------------------------------------------------------------------------
-- Helper Functions
--------------------------------------------------------------------------------

local function setup_test_grid()
    local terrain = MockGroundItems.new()

    -- Create a simple test grid (10x10)
    local test_grid = {
        width = 10,
        height = 10,
        tiles = {}
    }

    -- Initialize tiles array
    for y = 0, 9 do
        test_grid.tiles[y] = {}
        for x = 0, 9 do
            test_grid.tiles[y][x] = 1  -- GRASS tile
        end
    end

    terrain.setCurrentGrid(test_grid)
    return terrain
end

local function count_ground_items(terrain)
    local count = 0
    for _ in pairs(terrain.get_ground_items()) do
        count = count + 1
    end
    return count
end

local function find_item_by_id(terrain, item_id)
    local items = terrain.get_ground_items()
    return items[item_id]
end

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

t.describe("Ground Items - Core Functionality", function()

    t.it("drops items correctly with valid parameters", function()
        local terrain = setup_test_grid()

        -- Test dropping wood
        local wood_id = terrain.drop_item(5, 5, "wood", 10)
        t.expect(wood_id ~= nil).to_be_truthy("drop_item should return item ID")
        t.expect(type(wood_id) == "number").to_be_truthy("item ID should be a number")

        -- Verify item exists in ground items
        local wood_item = find_item_by_id(terrain, wood_id)
        t.expect(wood_item ~= nil).to_be_truthy("dropped item should exist in ground items")
        t.expect(wood_item.x == 5).to_be_truthy("item x coordinate should be correct")
        t.expect(wood_item.y == 5).to_be_truthy("item y coordinate should be correct")
        t.expect(wood_item.kind == "wood").to_be_truthy("item kind should be correct")
        t.expect(wood_item.amount == 10).to_be_truthy("item amount should be correct")
        t.expect(wood_item.id == wood_id).to_be_truthy("item ID should match returned ID")

        -- Test dropping different item types
        local stone_id = terrain.drop_item(3, 7, "stone", 5)
        local food_id = terrain.drop_item(1, 1, "food", 3)
        local gold_id = terrain.drop_item(9, 9, "gold", 1)

        -- Verify all items exist
        t.expect(find_item_by_id(terrain, stone_id) ~= nil).to_be_truthy("stone item should exist")
        t.expect(find_item_by_id(terrain, food_id) ~= nil).to_be_truthy("food item should exist")
        t.expect(find_item_by_id(terrain, gold_id) ~= nil).to_be_truthy("gold item should exist")

        -- Verify total count
        t.expect(count_ground_items(terrain) == 4).to_be_truthy("should have 4 total items")
    end)

    t.it("rejects invalid drop parameters", function()
        local terrain = setup_test_grid()

        -- Test invalid coordinates (outside grid bounds)
        local id1, err1 = terrain.drop_item(-1, 5, "wood", 10)
        t.expect(id1 == nil, "should reject negative x coordinate").to_be_truthy()
        t.expect(err1 ~= nil, "should return error message for negative x").to_be_truthy()

        local id2, err2 = terrain.drop_item(5, 15, "wood", 10)  -- y > grid height
        t.expect(id2 == nil, "should reject y coordinate beyond grid").to_be_truthy()
        t.expect(err2 ~= nil, "should return error message for large y").to_be_truthy()

        -- Test invalid item kind
        local id3, err3 = terrain.drop_item(5, 5, "invalid_item", 10)
        t.expect(id3 == nil, "should reject invalid item kind").to_be_truthy()
        t.expect(err3 ~= nil, "should return error message for invalid kind").to_be_truthy()

        -- Test invalid amounts
        local id4, err4 = terrain.drop_item(5, 5, "wood", 0)
        t.expect(id4 == nil, "should reject zero amount").to_be_truthy()
        t.expect(err4 ~= nil, "should return error message for zero amount").to_be_truthy()

        local id5, err5 = terrain.drop_item(5, 5, "wood", -5)
        t.expect(id5 == nil, "should reject negative amount").to_be_truthy()
        t.expect(err5 ~= nil, "should return error message for negative amount").to_be_truthy()
    end)

    t.it("generates unique monotonic IDs for items", function()
        local terrain = setup_test_grid()

        local id1 = terrain.drop_item(0, 0, "wood", 1)
        local id2 = terrain.drop_item(1, 1, "wood", 1)
        local id3 = terrain.drop_item(2, 2, "wood", 1)

        t.expect(id1 ~= id2, "consecutive items should have different IDs").to_be_truthy()
        t.expect(id2 ~= id3, "consecutive items should have different IDs").to_be_truthy()
        t.expect(id1 ~= id3, "non-consecutive items should have different IDs").to_be_truthy()

        -- IDs should be monotonically increasing
        t.expect(id2 > id1, "later items should have larger IDs").to_be_truthy()
        t.expect(id3 > id2, "later items should have larger IDs").to_be_truthy()
    end)

    t.it("retrieves items at specific locations", function()
        local terrain = setup_test_grid()

        -- Drop multiple items at the same location
        local wood_id = terrain.drop_item(5, 5, "wood", 10)
        local stone_id = terrain.drop_item(5, 5, "stone", 5)

        -- Drop item at different location
        local food_id = terrain.drop_item(3, 3, "food", 2)

        -- Test get_items_at for location with items
        local items_at_5_5 = terrain.get_items_at(5, 5)
        t.expect(#items_at_5_5 == 2, "should find 2 items at (5,5)").to_be_truthy()

        -- Verify the items are correct
        local found_wood = false
        local found_stone = false
        for _, item in ipairs(items_at_5_5) do
            if item.id == wood_id and item.kind == "wood" then
                found_wood = true
            elseif item.id == stone_id and item.kind == "stone" then
                found_stone = true
            end
        end
        t.expect(found_wood, "should find wood item at (5,5)").to_be_truthy()
        t.expect(found_stone, "should find stone item at (5,5)").to_be_truthy()

        -- Test get_items_at for location with one item
        local items_at_3_3 = terrain.get_items_at(3, 3)
        t.expect(#items_at_3_3 == 1, "should find 1 item at (3,3)").to_be_truthy()
        t.expect(items_at_3_3[1].id == food_id, "should find correct item at (3,3)").to_be_truthy()

        -- Test get_items_at for empty location
        local items_at_0_0 = terrain.get_items_at(0, 0)
        t.expect(#items_at_0_0 == 0, "should find no items at empty location").to_be_truthy()
    end)

    t.it("clears all ground items", function()
        local terrain = setup_test_grid()

        -- Drop several items
        terrain.drop_item(1, 1, "wood", 5)
        terrain.drop_item(2, 2, "stone", 3)
        terrain.drop_item(3, 3, "food", 1)

        -- Verify items exist
        t.expect(count_ground_items(terrain) == 3, "should have 3 items before clear").to_be_truthy()

        -- Clear all items
        terrain.clear_ground_items()

        -- Verify all items are gone
        t.expect(count_ground_items(terrain) == 0, "should have 0 items after clear").to_be_truthy()

        -- Verify get_items_at returns empty for all locations
        t.expect(#terrain.get_items_at(1, 1) == 0, "location (1,1) should be empty after clear").to_be_truthy()
        t.expect(#terrain.get_items_at(2, 2) == 0, "location (2,2) should be empty after clear").to_be_truthy()
        t.expect(#terrain.get_items_at(3, 3) == 0, "location (3,3) should be empty after clear").to_be_truthy()
    end)

    t.it("clears items when setting new grid", function()
        local terrain = setup_test_grid()

        -- Drop items
        terrain.drop_item(1, 1, "wood", 5)
        terrain.drop_item(2, 2, "stone", 3)

        t.expect(count_ground_items(terrain) == 2, "should have items before grid change").to_be_truthy()

        -- Set a new grid (should trigger clear)
        local new_grid = {
            width = 8,
            height = 8,
            tiles = {}
        }
        -- Initialize tiles array
        for y = 0, 7 do
            new_grid.tiles[y] = {}
            for x = 0, 7 do
                new_grid.tiles[y][x] = 1  -- GRASS tile
            end
        end
        terrain.setCurrentGrid(new_grid)

        -- Items should be cleared
        t.expect(count_ground_items(terrain) == 0, "should have no items after grid change").to_be_truthy()
    end)

    t.it("pickup functionality", function()
        local terrain = setup_test_grid()

        -- Drop item to test pickup
        local item_id = terrain.drop_item(5, 5, "wood", 10)

        -- Verify item exists before pickup
        t.expect(find_item_by_id(terrain, item_id) ~= nil, "item should exist before pickup").to_be_truthy()
        t.expect(count_ground_items(terrain) == 1, "should have 1 item before pickup").to_be_truthy()

        -- Test pickup
        local success, picked_item = terrain.pickup_item(item_id)
        t.expect(success, "pickup should succeed for valid item").to_be_truthy()
        t.expect(picked_item ~= nil, "pickup should return the item").to_be_truthy()
        t.expect(picked_item.id == item_id, "returned item should have correct ID").to_be_truthy()
        t.expect(picked_item.kind == "wood", "returned item should have correct kind").to_be_truthy()
        t.expect(picked_item.amount == 10, "returned item should have correct amount").to_be_truthy()

        -- Verify item is removed after pickup
        t.expect(find_item_by_id(terrain, item_id) == nil, "item should be removed after pickup").to_be_truthy()
        t.expect(count_ground_items(terrain) == 0, "should have 0 items after pickup").to_be_truthy()

        -- Test pickup of non-existent item
        local success2, err = terrain.pickup_item(999)
        t.expect(not success2, "pickup should fail for non-existent item").to_be_truthy()
        t.expect(err ~= nil, "pickup should return error message for non-existent item").to_be_truthy()
    end)

    t.it("find_nearest functionality", function()
        local terrain = setup_test_grid()

        -- Drop items at various locations
        local wood_id = terrain.drop_item(3, 3, "wood", 5)
        local stone_id = terrain.drop_item(7, 7, "stone", 3)
        local food_id = terrain.drop_item(1, 8, "food", 2)

        -- Test find nearest wood from (2, 2) - should find wood at (3, 3)
        local nearest_wood, distance = terrain.find_nearest_item(2, 2, "wood")
        t.expect(nearest_wood ~= nil, "should find nearest wood item").to_be_truthy()
        t.expect(nearest_wood.id == wood_id, "should find the correct nearest wood item").to_be_truthy()
        t.expect(math.abs(distance - math.sqrt(2)) < 0.001, "distance should be approximately sqrt(2)").to_be_truthy()

        -- Test find nearest stone from (6, 6) - should find stone at (7, 7)
        local nearest_stone, stone_distance = terrain.find_nearest_item(6, 6, "stone")
        t.expect(nearest_stone ~= nil, "should find nearest stone item").to_be_truthy()
        t.expect(nearest_stone.id == stone_id, "should find the correct nearest stone item").to_be_truthy()

        -- Test find nearest item of any type from (5, 5) - should find wood at (3, 3)
        local nearest_any, any_distance = terrain.find_nearest_item(5, 5)
        t.expect(nearest_any ~= nil, "should find nearest item of any type").to_be_truthy()
        t.expect(nearest_any.id == wood_id, "should find wood as nearest to (5,5)").to_be_truthy()

        -- Test find nearest when no items of specified type exist
        local nearest_gold, gold_distance = terrain.find_nearest_item(5, 5, "gold")
        t.expect(nearest_gold == nil, "should return nil when no items of type exist").to_be_truthy()
    end)

end)

t.describe("Ground Items - Edge Cases", function()

    t.it("handles empty grid correctly", function()
        local terrain = setup_test_grid()

        -- Test operations on empty grid
        t.expect(count_ground_items(terrain) == 0, "new grid should have no items").to_be_truthy()
        t.expect(#terrain.get_items_at(5, 5) == 0, "empty grid should return no items at any location").to_be_truthy()

        -- Clear should work on empty grid
        terrain.clear_ground_items()  -- Should not error
        t.expect(count_ground_items(terrain) == 0, "clearing empty grid should remain empty").to_be_truthy()

        -- Find nearest should return nil on empty grid
        local nearest, distance = terrain.find_nearest_item(5, 5)
        t.expect(nearest == nil, "find_nearest should return nil on empty grid").to_be_truthy()
    end)

    t.it("handles item timestamps correctly", function()
        local terrain = setup_test_grid()

        local time_before = os.time()
        local item_id = terrain.drop_item(5, 5, "wood", 10)
        local time_after = os.time()

        local item = find_item_by_id(terrain, item_id)
        t.expect(item.created_at >= time_before, "item timestamp should be at least time before creation").to_be_truthy()
        t.expect(item.created_at <= time_after, "item timestamp should be at most time after creation").to_be_truthy()
    end)

    t.it("handles multiple items with same type and location", function()
        local terrain = setup_test_grid()

        -- Drop multiple wood items at same location
        local wood1_id = terrain.drop_item(5, 5, "wood", 5)
        local wood2_id = terrain.drop_item(5, 5, "wood", 10)
        local wood3_id = terrain.drop_item(5, 5, "wood", 3)

        -- All should have unique IDs
        t.expect(wood1_id ~= wood2_id, "items should have unique IDs").to_be_truthy()
        t.expect(wood2_id ~= wood3_id, "items should have unique IDs").to_be_truthy()
        t.expect(wood1_id ~= wood3_id, "items should have unique IDs").to_be_truthy()

        -- All should be found at location
        local items_at_location = terrain.get_items_at(5, 5)
        t.expect(#items_at_location == 3, "should find all 3 items at location").to_be_truthy()

        -- Pickup one item should leave others
        local success = terrain.pickup_item(wood2_id)
        t.expect(success, "pickup should succeed").to_be_truthy()

        local remaining_items = terrain.get_items_at(5, 5)
        t.expect(#remaining_items == 2, "should have 2 items remaining after pickup").to_be_truthy()

        -- Verify correct items remain
        local found_wood1 = false
        local found_wood3 = false
        for _, item in ipairs(remaining_items) do
            if item.id == wood1_id then found_wood1 = true end
            if item.id == wood3_id then found_wood3 = true end
        end
        t.expect(found_wood1, "wood1 should remain after pickup").to_be_truthy()
        t.expect(found_wood3, "wood3 should remain after pickup").to_be_truthy()
    end)

end)

--------------------------------------------------------------------------------
-- Run Tests
--------------------------------------------------------------------------------

print("Running Ground Items Tests (Mock Implementation)...")
print("NOTE: These tests use a mock implementation. When terrain.lua becomes")
print("headless-safe, this test should be updated to use the real implementation.")
t.run_all()