#!/usr/bin/env lua
--[[
Simple test to verify structures collect function implementation.
Checks the terrain_persistence.lua file for proper collect function.
]]

local function test_collect_function_exists()
    print("Testing structures collect function implementation...")

    -- Read the terrain_persistence.lua file
    local file = io.open("assets/scripts/idle_game/terrain_persistence.lua", "r")
    if not file then
        print("❌ FAIL: Could not read terrain_persistence.lua")
        return false
    end

    local content = file:read("*all")
    file:close()

    local tests_passed = 0
    local tests_failed = 0

    -- Test 1: Check for collect function definition
    print("\nTest 1: Collect function exists")
    if content:find("local function collect%(") then
        print("✅ PASS: collect function definition found")
        tests_passed = tests_passed + 1
    else
        print("❌ FAIL: collect function definition not found")
        tests_failed = tests_failed + 1
    end

    -- Test 2: Check for terrain.get_structures() call
    print("\nTest 2: Uses terrain.get_structures()")
    if content:find("terrain%.get_structures%(") then
        print("✅ PASS: terrain.get_structures() call found")
        tests_passed = tests_passed + 1
    else
        print("❌ FAIL: terrain.get_structures() call not found")
        tests_failed = tests_failed + 1
    end

    -- Test 3: Check for serializable structure creation
    print("\nTest 3: Creates serializable structures")
    if content:find("serializable_structures") then
        print("✅ PASS: serializable_structures variable found")
        tests_passed = tests_passed + 1
    else
        print("❌ FAIL: serializable_structures variable not found")
        tests_failed = tests_failed + 1
    end

    -- Test 4: Check for structure field serialization
    print("\nTest 4: Serializes structure fields")
    local required_fields = {"id", "x", "y", "type", "created_at"}
    local fields_found = 0
    for _, field in ipairs(required_fields) do
        if content:find(field .. " = structure%." .. field) then
            fields_found = fields_found + 1
        end
    end

    if fields_found == #required_fields then
        print("✅ PASS: All required fields serialized (id, x, y, type, created_at)")
        tests_passed = tests_passed + 1
    else
        print("❌ FAIL: Missing required fields, found " .. fields_found .. "/" .. #required_fields)
        tests_failed = tests_failed + 1
    end

    -- Test 5: Check for SaveManager registration with collect function
    print("\nTest 5: SaveManager registration")
    if content:find("SaveManager%.register") and content:find("collect = collect") then
        print("✅ PASS: SaveManager.register with collect function found")
        tests_passed = tests_passed + 1
    else
        print("❌ FAIL: SaveManager registration with collect function not found")
        tests_failed = tests_failed + 1
    end

    -- Test 6: Check for proper return statement
    print("\nTest 6: Returns serializable structures")
    if content:find("return serializable_structures") then
        print("✅ PASS: Returns serializable_structures")
        tests_passed = tests_passed + 1
    else
        print("❌ FAIL: Does not return serializable_structures")
        tests_failed = tests_failed + 1
    end

    -- Test 7: Check for stable ordering (table.insert)
    print("\nTest 7: Stable ordering implementation")
    if content:find("table%.insert%(serializable_structures") then
        print("✅ PASS: Uses table.insert for stable ordering")
        tests_passed = tests_passed + 1
    else
        print("❌ FAIL: Does not use table.insert for stable ordering")
        tests_failed = tests_failed + 1
    end

    -- Summary
    print(string.format("\n🏁 Test Summary: %d passed, %d failed", tests_passed, tests_failed))

    if tests_failed == 0 then
        print("🎉 All tests passed! Structures collect function is properly implemented:")
        print("  ✅ Function definition exists")
        print("  ✅ Gets structures from terrain module")
        print("  ✅ Creates serializable structure format")
        print("  ✅ Serializes all required fields (id, x, y, type, created_at)")
        print("  ✅ Registered with SaveManager")
        print("  ✅ Returns serializable structure list")
        print("  ✅ Implements stable ordering with table.insert")
        return true
    else
        print("⚠️ Some tests failed!")
        return false
    end
end

-- Run the test
return test_collect_function_exists()