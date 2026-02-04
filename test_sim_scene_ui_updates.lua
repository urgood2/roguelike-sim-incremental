#!/usr/bin/env lua
--[[
Test to verify sim_scene.update includes all required UI state updates.
Checks that resource panel, upgrade panel, toast queue, and achievement listener updates are called.
]]

-- Setup package path
package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/?/init.lua"

local function run_ui_update_test()
    print("Testing sim_scene.update UI state updates...")

    -- Read the sim_scene.lua file and parse for update calls
    local file = io.open("assets/scripts/idle_game/scenes/sim_scene.lua", "r")
    if not file then
        print("❌ FAIL: Could not read sim_scene.lua")
        return false
    end

    local content = file:read("*all")
    file:close()

    local tests_passed = 0
    local tests_failed = 0

    -- Test 1: Check for resource panel update
    print("\nTest 1: Resource panel update")
    if content:find("ascii_resource_panel%.update%(dt") then
        print("✅ PASS: ascii_resource_panel.update(dt, ...) found")
        tests_passed = tests_passed + 1
    else
        print("❌ FAIL: ascii_resource_panel.update not found")
        tests_failed = tests_failed + 1
    end

    -- Test 2: Check for upgrade panel update
    print("\nTest 2: Upgrade panel update")
    if content:find("ascii_upgrade_panel%.update%(dt") then
        print("✅ PASS: ascii_upgrade_panel.update(dt, ...) found")
        tests_passed = tests_passed + 1
    else
        print("❌ FAIL: ascii_upgrade_panel.update not found")
        tests_failed = tests_failed + 1
    end

    -- Test 3: Check for toast queue update
    print("\nTest 3: Toast queue update")
    if content:find("toast_queue%.update%(dt") then
        print("✅ PASS: toast_queue.update(dt) found")
        tests_passed = tests_passed + 1
    else
        print("❌ FAIL: toast_queue.update not found")
        tests_failed = tests_failed + 1
    end

    -- Test 4: Check for achievement listener update
    print("\nTest 4: Achievement listener update")
    if content:find("achievement_listener%.update%(dt") then
        print("✅ PASS: achievement_listener.update(dt) found")
        tests_passed = tests_passed + 1
    else
        print("❌ FAIL: achievement_listener.update not found")
        tests_failed = tests_failed + 1
    end

    -- Test 5: Check for wheel scrolling on upgrade panel
    print("\nTest 5: Upgrade panel wheel scrolling")
    if content:find("ascii_upgrade_panel%.scroll_by_wheel") then
        print("✅ PASS: ascii_upgrade_panel.scroll_by_wheel found")
        tests_passed = tests_passed + 1
    else
        print("❌ FAIL: ascii_upgrade_panel.scroll_by_wheel not found")
        tests_failed = tests_failed + 1
    end

    -- Test 6: Check that achievements.update is not duplicated
    print("\nTest 6: No duplicate achievements.update calls")
    local achievements_update_count = 0
    for match in content:gmatch("achievements%.update%(dt") do
        achievements_update_count = achievements_update_count + 1
    end

    if achievements_update_count == 0 then
        print("✅ PASS: No direct achievements.update calls (handled by achievement_listener)")
        tests_passed = tests_passed + 1
    else
        print("❌ FAIL: Found " .. achievements_update_count .. " direct achievements.update calls (should be 0)")
        tests_failed = tests_failed + 1
    end

    -- Test 7: Check achievement_listener.update is called only once
    print("\nTest 7: Single achievement_listener.update call")
    local listener_update_count = 0
    for match in content:gmatch("achievement_listener%.update%(dt") do
        listener_update_count = listener_update_count + 1
    end

    if listener_update_count == 1 then
        print("✅ PASS: achievement_listener.update called exactly once")
        tests_passed = tests_passed + 1
    else
        print("❌ FAIL: Found " .. listener_update_count .. " achievement_listener.update calls (should be 1)")
        tests_failed = tests_failed + 1
    end

    -- Summary
    print(string.format("\n🏁 Test Summary: %d passed, %d failed", tests_passed, tests_failed))

    if tests_failed == 0 then
        print("🎉 All tests passed! sim_scene.update includes all required UI state updates:")
        print("  ✅ Resource panel update")
        print("  ✅ Upgrade panel update with hover/scroll support")
        print("  ✅ Toast queue update (auto-dismiss)")
        print("  ✅ Achievement listener update (achievement evaluation)")
        print("  ✅ No duplicate achievement update calls")
        return true
    else
        print("⚠️ Some tests failed!")
        return false
    end
end

-- Run the test
return run_ui_update_test()