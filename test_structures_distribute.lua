#!/usr/bin/env lua
--[[
Test for structures distribute function validation.
Verifies that the distribute function correctly restores structures with proper validation.
]]

-- Setup package path
package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/?/init.lua"

local function create_terrain_mock()
    local structures = {}
    local next_id = 1
    local grid_width, grid_height = 10, 10
    local current_grid = {}

    -- Initialize grid
    for y = 0, grid_height - 1 do
        current_grid[y] = {}
        for x = 0, grid_width - 1 do
            current_grid[y][x] = "GRASS"
        end
    end

    return {
        get_structures = function() return structures end,
        clear_structures = function()
            local count = 0
            for _ in pairs(structures) do count = count + 1 end
            structures = {}
            next_id = 1
            if count > 0 then
                print(string.format("[TERRAIN] Cleared %d structures", count))
            end
        end,
        place_structure = function(x, y, structure_type)
            -- Validate coordinates
            if x < 0 or x >= grid_width or y < 0 or y >= grid_height then
                return false, "Out of bounds"
            end

            -- Validate structure type
            local valid_types = { farm = true, mine = true, house = true, workshop = true, storage = true }
            if not valid_types[structure_type] then
                return false, "Invalid structure type"
            end

            -- Check position not occupied
            for _, structure in pairs(structures) do
                if structure.x == x and structure.y == y then
                    return false, "Position occupied"
                end
            end

            -- Check terrain is grass
            if current_grid[y][x] ~= "GRASS" then
                return false, "Not walkable terrain"
            end

            -- Place structure
            local structure = {
                id = next_id,
                x = x,
                y = y,
                type = structure_type,
                created_at = os.time()
            }
            structures[next_id] = structure
            next_id = next_id + 1

            return true, structure.id
        end,
        set_terrain = function(x, y, terrain_type)
            if current_grid[y] then
                current_grid[y][x] = terrain_type
            end
        end
    }
end

local function create_save_manager_mock()
    local collectors = {}

    return {
        register = function(name, collector)
            collectors[name] = collector
        end,
        get_collector = function(name)
            return collectors[name]
        end
    }
end

local function test_structures_distribute()
    print("Testing structures distribute function with validation...")

    -- Set up mocks
    local terrain_mock = create_terrain_mock()
    local save_manager_mock = create_save_manager_mock()

    -- Mock global dependencies
    package.loaded["idle_game.terrain"] = terrain_mock
    package.loaded["core.save_manager"] = save_manager_mock

    local tests_passed = 0
    local tests_failed = 0

    -- Load terrain persistence module
    local terrain_persistence = require("idle_game.terrain_persistence")

    -- Get the collector
    local collector = save_manager_mock.get_collector("idle_structures")

    -- Test 1: Valid structures should be distributed successfully
    print("\nTest 1: Distribute valid structures")

    local valid_data = {
        { id = 1, x = 2, y = 3, type = "farm", created_at = 1234567890 },
        { id = 2, x = 5, y = 7, type = "house", created_at = 1234567891 },
        { id = 3, x = 8, y = 1, type = "storage", created_at = 1234567892 }
    }

    collector.distribute(valid_data)

    local structures = terrain_mock.get_structures()
    local structure_count = 0
    for _ in pairs(structures) do structure_count = structure_count + 1 end

    if structure_count == 3 then
        print("✅ PASS: All valid structures distributed correctly")
        tests_passed = tests_passed + 1
    else
        print("❌ FAIL: Expected 3 structures, got " .. structure_count)
        tests_failed = tests_failed + 1
    end

    -- Test 2: Invalid structures should be skipped
    print("\nTest 2: Invalid structures should be skipped")

    terrain_mock.clear_structures()

    local mixed_data = {
        { id = 1, x = 1, y = 1, type = "farm", created_at = 1234567890 },  -- Valid
        { id = 2, x = -1, y = 5, type = "house", created_at = 1234567891 }, -- Invalid: out of bounds
        { id = 3, x = 3, y = 4, type = "invalid_type", created_at = 1234567892 }, -- Invalid: bad type
        { id = 4, x = "not_number", y = 2, type = "workshop" }, -- Invalid: bad coordinates
        { id = 5, x = 6, y = 6, type = "mine", created_at = 1234567893 }   -- Valid
    }

    collector.distribute(mixed_data)

    structures = terrain_mock.get_structures()
    structure_count = 0
    for _ in pairs(structures) do structure_count = structure_count + 1 end

    if structure_count == 2 then
        print("✅ PASS: Only valid structures placed, invalid ones skipped")
        tests_passed = tests_passed + 1
    else
        print("❌ FAIL: Expected 2 valid structures, got " .. structure_count)
        tests_failed = tests_failed + 1
    end

    -- Test 3: Legacy format handling
    print("\nTest 3: Legacy format compatibility")

    terrain_mock.clear_structures()

    local legacy_data = {
        { tileX = 2, tileY = 2, sprite = "farm" },  -- Legacy format
        { x = 4, y = 4, type = "house" }            -- New format
    }

    collector.distribute(legacy_data)

    structures = terrain_mock.get_structures()
    structure_count = 0
    for _ in pairs(structures) do structure_count = structure_count + 1 end

    if structure_count == 2 then
        print("✅ PASS: Legacy and new formats both handled")
        tests_passed = tests_passed + 1
    else
        print("❌ FAIL: Legacy format not properly handled")
        tests_failed = tests_failed + 1
    end

    -- Test 4: Occupied position validation
    print("\nTest 4: Occupied position validation")

    terrain_mock.clear_structures()

    -- First place a structure
    collector.distribute({ { x = 3, y = 3, type = "farm" } })

    -- Try to place another at same position
    collector.distribute({ { x = 3, y = 3, type = "house" } })

    structures = terrain_mock.get_structures()
    structure_count = 0
    for _ in pairs(structures) do structure_count = structure_count + 1 end

    if structure_count == 1 then
        print("✅ PASS: Occupied position validation prevents double placement")
        tests_passed = tests_passed + 1
    else
        print("❌ FAIL: Occupied position not properly validated")
        tests_failed = tests_failed + 1
    end

    -- Test 5: Non-walkable terrain validation
    print("\nTest 5: Non-walkable terrain validation")

    terrain_mock.clear_structures()

    -- Set a position to rock (non-walkable)
    terrain_mock.set_terrain(5, 5, "ROCK")

    -- Try to place structure on rock
    collector.distribute({ { x = 5, y = 5, type = "farm" } })

    structures = terrain_mock.get_structures()
    structure_count = 0
    for _ in pairs(structures) do structure_count = structure_count + 1 end

    if structure_count == 0 then
        print("✅ PASS: Non-walkable terrain validation prevents placement")
        tests_passed = tests_passed + 1
    else
        print("❌ FAIL: Non-walkable terrain validation failed")
        tests_failed = tests_failed + 1
    end

    -- Test 6: Empty/nil data handling
    print("\nTest 6: Empty/nil data handling")

    terrain_mock.clear_structures()

    -- Test with nil
    collector.distribute(nil)
    structures = terrain_mock.get_structures()
    local count_after_nil = 0
    for _ in pairs(structures) do count_after_nil = count_after_nil + 1 end

    -- Test with empty table
    collector.distribute({})
    structures = terrain_mock.get_structures()
    local count_after_empty = 0
    for _ in pairs(structures) do count_after_empty = count_after_empty + 1 end

    if count_after_nil == 0 and count_after_empty == 0 then
        print("✅ PASS: Nil and empty data handled gracefully")
        tests_passed = tests_passed + 1
    else
        print("❌ FAIL: Nil/empty data not handled properly")
        tests_failed = tests_failed + 1
    end

    -- Summary
    print(string.format("\n🏁 Test Summary: %d passed, %d failed", tests_passed, tests_failed))

    if tests_failed == 0 then
        print("🎉 All tests passed! Structures distribute function works correctly:")
        print("  ✅ Valid structures are distributed and placed")
        print("  ✅ Invalid structures are skipped with validation")
        print("  ✅ Legacy format compatibility (tileX/tileY, sprite)")
        print("  ✅ Occupied position validation prevents conflicts")
        print("  ✅ Non-walkable terrain validation enforced")
        print("  ✅ Nil and empty data handled gracefully")
        print("  ✅ Comprehensive validation chain works correctly")
        return true
    else
        print("⚠️ Some tests failed - distribute function may have issues!")
        return false
    end
end

-- Run the test
return test_structures_distribute()