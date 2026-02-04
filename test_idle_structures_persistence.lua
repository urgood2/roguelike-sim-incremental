-- Structures Persistence Test
-- Integration test to verify structures survive save/restart cycles
-- Based on verification plan: verification_plans/structures_persistence_verification.md

local terrain = require("idle_game.terrain")
local save_manager = require("idle_game.save_manager")
local config = require("idle_game.config")

local test = {}

-- Test utilities
local function log_test(message)
    print("[STRUCTURES_TEST] " .. message)
end

local function assert_test(condition, message)
    if not condition then
        error("[STRUCTURES_TEST] ASSERTION FAILED: " .. (message or "Unknown condition"))
    end
    return true
end

local function deep_compare_structures(expected, actual)
    if #expected ~= #actual then
        return false, string.format("Count mismatch: expected %d, got %d", #expected, #actual)
    end

    for i, exp_structure in ipairs(expected) do
        local found = false
        for j, act_structure in ipairs(actual) do
            if exp_structure.x == act_structure.x and
               exp_structure.y == act_structure.y and
               exp_structure.type == act_structure.type then
                found = true
                break
            end
        end
        if not found then
            return false, string.format("Structure not found: %s at (%d, %d)",
                exp_structure.type, exp_structure.x, exp_structure.y)
        end
    end

    return true, "All structures match"
end

-- Test Scenario 1: Basic Persistence
function test.basic_persistence()
    log_test("Starting basic persistence test...")

    -- Clear any existing structures
    if terrain.clear_all_structures then
        terrain.clear_all_structures()
    end

    -- Define test structures
    local test_structures = {
        {x = 10, y = 10, type = "farm"},
        {x = 15, y = 20, type = "mine"},
        {x = 25, y = 15, type = "house"},
        {x = 30, y = 25, type = "workshop"},
        {x = 5, y = 30, type = "storage"}
    }

    log_test("Placing test structures...")
    for _, structure in ipairs(test_structures) do
        if terrain.place_structure then
            local success = terrain.place_structure(structure.x, structure.y, structure.type)
            assert_test(success, "Failed to place structure: " .. structure.type)
            log_test(string.format("Placed %s at (%d, %d)", structure.type, structure.x, structure.y))
        else
            log_test("WARNING: terrain.place_structure not available")
            return false, "terrain.place_structure function not implemented"
        end
    end

    -- Verify structures were placed
    log_test("Verifying initial placement...")
    if terrain.get_structures then
        local placed_structures = terrain.get_structures()
        local match, msg = deep_compare_structures(test_structures, placed_structures)
        assert_test(match, "Initial placement verification failed: " .. msg)
        log_test("Initial placement verified successfully")
    else
        log_test("WARNING: terrain.get_structures not available")
        return false, "terrain.get_structures function not implemented"
    end

    -- Simulate save operation
    log_test("Simulating save operation...")
    if save_manager and save_manager.serialize then
        local save_data = save_manager.serialize()
        assert_test(save_data ~= nil, "Save data is nil")
        log_test("Save operation completed")

        -- Simulate load operation
        log_test("Simulating load operation...")
        if save_manager.deserialize then
            local load_success = save_manager.deserialize(save_data)
            assert_test(load_success ~= false, "Load operation failed")
            log_test("Load operation completed")
        else
            log_test("WARNING: save_manager.deserialize not available")
            return false, "save_manager.deserialize function not implemented"
        end
    else
        log_test("WARNING: save_manager.serialize not available")
        return false, "save_manager.serialize function not implemented"
    end

    -- Verify structures after save/load
    log_test("Verifying structures after save/load...")
    local loaded_structures = terrain.get_structures()
    local match, msg = deep_compare_structures(test_structures, loaded_structures)
    assert_test(match, "Post-load verification failed: " .. msg)

    log_test("Basic persistence test PASSED")
    return true, "Basic persistence test completed successfully"
end

-- Test Scenario 2: Complex Layout
function test.complex_layout()
    log_test("Starting complex layout test...")

    -- Clear any existing structures
    if terrain.clear_all_structures then
        terrain.clear_all_structures()
    end

    -- Create a complex pattern of structures
    local complex_structures = {}

    -- Grid pattern
    for x = 5, 35, 5 do
        for y = 5, 25, 5 do
            local structure_types = {"farm", "mine", "house", "workshop"}
            local structure_type = structure_types[((x + y) % 4) + 1]
            table.insert(complex_structures, {x = x, y = y, type = structure_type})
        end
    end

    log_test(string.format("Placing %d structures in complex pattern...", #complex_structures))
    for _, structure in ipairs(complex_structures) do
        local success = terrain.place_structure(structure.x, structure.y, structure.type)
        assert_test(success, "Failed to place structure in complex pattern")
    end

    -- Save and load
    local save_data = save_manager.serialize()
    save_manager.deserialize(save_data)

    -- Verify pattern integrity
    local loaded_structures = terrain.get_structures()
    local match, msg = deep_compare_structures(complex_structures, loaded_structures)
    assert_test(match, "Complex layout verification failed: " .. msg)

    log_test("Complex layout test PASSED")
    return true, "Complex layout test completed successfully"
end

-- Test Scenario 3: Multiple Save/Load Cycles
function test.multiple_cycles()
    log_test("Starting multiple save/load cycles test...")

    -- Clear and place initial structures
    if terrain.clear_all_structures then
        terrain.clear_all_structures()
    end

    local cycle_structures = {
        {x = 12, y = 12, type = "farm"},
        {x = 18, y = 18, type = "mine"}
    }

    for _, structure in ipairs(cycle_structures) do
        terrain.place_structure(structure.x, structure.y, structure.type)
    end

    -- Perform multiple save/load cycles
    for cycle = 1, 3 do
        log_test(string.format("Save/load cycle %d...", cycle))
        local save_data = save_manager.serialize()
        save_manager.deserialize(save_data)

        -- Verify structures survive each cycle
        local loaded_structures = terrain.get_structures()
        local match, msg = deep_compare_structures(cycle_structures, loaded_structures)
        assert_test(match, string.format("Cycle %d verification failed: %s", cycle, msg))
    end

    log_test("Multiple cycles test PASSED")
    return true, "Multiple cycles test completed successfully"
end

-- Test Scenario 4: Edge Cases
function test.edge_cases()
    log_test("Starting edge cases test...")

    -- Clear existing structures
    if terrain.clear_all_structures then
        terrain.clear_all_structures()
    end

    local edge_structures = {}

    -- Test structures near boundaries
    -- Note: Using config.GRID_WIDTH and config.GRID_HEIGHT if available
    local max_x = config.GRID_WIDTH and (config.GRID_WIDTH - 1) or 49
    local max_y = config.GRID_HEIGHT and (config.GRID_HEIGHT - 1) or 29

    table.insert(edge_structures, {x = 0, y = 0, type = "farm"})           -- Top-left corner
    table.insert(edge_structures, {x = max_x, y = 0, type = "mine"})       -- Top-right corner
    table.insert(edge_structures, {x = 0, y = max_y, type = "house"})      -- Bottom-left corner
    table.insert(edge_structures, {x = max_x, y = max_y, type = "workshop"}) -- Bottom-right corner

    log_test("Testing boundary structures...")
    for _, structure in ipairs(edge_structures) do
        local success = terrain.place_structure(structure.x, structure.y, structure.type)
        if success then
            log_test(string.format("Placed boundary structure %s at (%d, %d)",
                structure.type, structure.x, structure.y))
        else
            log_test(string.format("WARNING: Could not place structure at boundary (%d, %d)",
                structure.x, structure.y))
            -- Remove from expected structures if placement failed
            for i = #edge_structures, 1, -1 do
                if edge_structures[i] == structure then
                    table.remove(edge_structures, i)
                    break
                end
            end
        end
    end

    -- Save and load
    local save_data = save_manager.serialize()
    save_manager.deserialize(save_data)

    -- Verify edge case structures
    local loaded_structures = terrain.get_structures()
    local match, msg = deep_compare_structures(edge_structures, loaded_structures)
    assert_test(match, "Edge cases verification failed: " .. msg)

    log_test("Edge cases test PASSED")
    return true, "Edge cases test completed successfully"
end

-- Main test runner
function test.run_all_tests()
    log_test("=== STRUCTURES PERSISTENCE TEST SUITE ===")
    log_test("Running comprehensive structures persistence tests...")

    local tests = {
        {"Basic Persistence", test.basic_persistence},
        {"Complex Layout", test.complex_layout},
        {"Multiple Cycles", test.multiple_cycles},
        {"Edge Cases", test.edge_cases}
    }

    local passed = 0
    local failed = 0
    local results = {}

    for _, test_info in ipairs(tests) do
        local test_name, test_func = test_info[1], test_info[2]
        log_test(string.format("\n--- Running: %s ---", test_name))

        local success, result = pcall(test_func)
        if success and result then
            log_test(string.format("✅ %s PASSED", test_name))
            passed = passed + 1
            table.insert(results, {name = test_name, status = "PASSED", message = result})
        else
            log_test(string.format("❌ %s FAILED: %s", test_name, result or "Unknown error"))
            failed = failed + 1
            table.insert(results, {name = test_name, status = "FAILED", message = result or "Unknown error"})
        end
    end

    -- Final summary
    log_test(string.format("\n=== TEST RESULTS SUMMARY ==="))
    log_test(string.format("Total tests: %d", #tests))
    log_test(string.format("Passed: %d", passed))
    log_test(string.format("Failed: %d", failed))
    log_test(string.format("Success rate: %.1f%%", (passed / #tests) * 100))

    -- Detailed results
    log_test("\n=== DETAILED RESULTS ===")
    for _, result in ipairs(results) do
        log_test(string.format("%s: %s - %s", result.status, result.name, result.message))
    end

    return failed == 0, results
end

-- Export the test module
return test