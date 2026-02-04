#!/usr/bin/env lua
--[[
Test upgrade panel click mapping after scrolling.
Verifies that buy clicks map to the correct upgrades when the panel is scrolled.
]]

-- Setup package path
package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/?/init.lua"

local function create_upgrade_module_mock()
    local upgrade_ids = {
        "click_wood", "click_stone", "max_creatures", "tree_regrowth", "rock_regrowth",
        "passive_gold", "upgrades_cost_reduction", "survival_boost", "work_efficiency",
        "reproduction_rate", "harvest_multiplier", "movement_speed"
    }

    local upgrades = {}
    for _, id in ipairs(upgrade_ids) do
        upgrades[id] = {
            name = id,
            description = id .. " desc",
            max_level = 10
        }
    end

    return {
        get_all = function() return upgrades end,
        get_level = function(upgrade_id) return 0 end,
        get_cost = function(upgrade_id) return { wood = 50, stone = 25 } end,
        can_afford = function(upgrade_id, resources) return true end,
        purchase = function(upgrade_id)
            print("PURCHASED:", upgrade_id)
            return true
        end
    }
end

local function sorted_upgrade_ids(upgrades_module)
    local ids = {}
    for id, _ in pairs(upgrades_module.get_all()) do
        table.insert(ids, id)
    end
    table.sort(ids)
    return ids
end

local function create_resources_module_mock()
    return {
        can_afford = function(costs) return true end
    }
end

local function test_click_mapping_after_scroll()
    print("Testing upgrade panel click mapping after scrolling...")

    -- Mock draw dependency
    local draw_mock = {
        rectangle = function(layer, rect) end,
        textPro = function(layer, config) end
    }
    package.loaded["core.draw"] = draw_mock

    -- Mock global layer
    _G.layers = { ui = {} }

    -- Load the upgrade panel module
    local ascii_upgrade_panel = require("idle_game.ui.ascii_upgrade_panel")

    -- Initialize panel
    local TILE_SIZE = 20
    ascii_upgrade_panel.init(TILE_SIZE, 800, 600)

    local upgrades_module = create_upgrade_module_mock()
    local resources_module = create_resources_module_mock()

    -- Update to populate upgrade list
    ascii_upgrade_panel.update(0.1, upgrades_module, resources_module)
    local ids_sorted = sorted_upgrade_ids(upgrades_module)

    local tests_passed = 0
    local tests_failed = 0

    -- Get panel dimensions
    local rect = ascii_upgrade_panel.get_rect()
    local upgrade_height = TILE_SIZE * 2  -- Each upgrade is 2 tiles tall

    print(string.format("Panel rect: x=%d, y=%d, w=%d, h=%d", rect.x, rect.y, rect.w, rect.h))
    print(string.format("Upgrade height: %d pixels", upgrade_height))

    -- Test 1: Click mapping without scrolling
    print("\nTest 1: Click mapping without scrolling (offset=0)")

    -- Reset scroll to 0
    ascii_upgrade_panel.scroll_by_wheel(-999)  -- Scroll to top

    local test_y = rect.y + upgrade_height * 0.5  -- Click middle of first upgrade
    local test_x = rect.x + rect.w - 1  -- Click inside buy region

    print(string.format("Clicking at (%d, %d) - should select upgrade 1", test_x, test_y))

    -- Capture the purchase call to see which upgrade was selected
    local purchased_upgrade = nil
    local old_purchase = upgrades_module.purchase
    upgrades_module.purchase = function(upgrade_id)
        purchased_upgrade = upgrade_id
        return true
    end

    local handled = ascii_upgrade_panel.handle_click(test_x, test_y, upgrades_module, resources_module)

    upgrades_module.purchase = old_purchase

    local expected_first = ids_sorted[1]
    if handled and purchased_upgrade == expected_first then
        print("✅ PASS: Correctly clicked first upgrade (" .. tostring(expected_first) .. ")")
        tests_passed = tests_passed + 1
    else
        print("❌ FAIL: Expected", expected_first, "got:", purchased_upgrade)
        tests_failed = tests_failed + 1
    end

    -- Test 2: Click mapping after scrolling down
    print("\nTest 2: Click mapping after scrolling (offset=3)")

    -- Scroll down by 3 positions
    ascii_upgrade_panel.scroll_by_wheel(3)

    -- Click same relative position (first visible upgrade)
    print(string.format("Clicking at (%d, %d) - should select upgrade 4 (after scroll)", test_x, test_y))

    purchased_upgrade = nil
    upgrades_module.purchase = function(upgrade_id)
        purchased_upgrade = upgrade_id
        return true
    end

    handled = ascii_upgrade_panel.handle_click(test_x, test_y, upgrades_module, resources_module)

    upgrades_module.purchase = old_purchase

    local expected_fourth = ids_sorted[4]
    if handled and purchased_upgrade == expected_fourth then
        print("✅ PASS: Correctly clicked fourth upgrade (" .. tostring(expected_fourth) .. ") after scrolling")
        tests_passed = tests_passed + 1
    else
        print("❌ FAIL: Expected", expected_fourth, "got:", purchased_upgrade)
        tests_failed = tests_failed + 1
    end

    -- Test 3: Click mapping for bottom visible upgrade after scrolling
    print("\nTest 3: Click bottom visible upgrade after scrolling")

    -- Click bottom of visible area (should be upgrade 4 + some visible count)
    local bottom_y = rect.y + upgrade_height * 2.5  -- Third visible upgrade
    print(string.format("Clicking at (%d, %d) - should select upgrade 6", test_x, bottom_y))

    purchased_upgrade = nil
    upgrades_module.purchase = function(upgrade_id)
        purchased_upgrade = upgrade_id
        return true
    end

    handled = ascii_upgrade_panel.handle_click(test_x, bottom_y, upgrades_module, resources_module)

    upgrades_module.purchase = old_purchase

    local expected_sixth = ids_sorted[6]
    if handled and purchased_upgrade == expected_sixth then
        print("✅ PASS: Correctly clicked sixth upgrade (" .. tostring(expected_sixth) .. ")")
        tests_passed = tests_passed + 1
    else
        print("❌ FAIL: Expected", expected_sixth, "got:", purchased_upgrade)
        tests_failed = tests_failed + 1
    end

    -- Test 4: Verify scroll bounds
    print("\nTest 4: Scroll bounds handling")

    -- Try to scroll way up (should clamp to 0)
    ascii_upgrade_panel.scroll_by_wheel(-999)
    local scroll_info = ascii_upgrade_panel.get_scroll_info()

    if scroll_info.offset == 0 then
        print("✅ PASS: Scroll up clamped to 0")
        tests_passed = tests_passed + 1
    else
        print("❌ FAIL: Scroll not clamped, offset:", scroll_info.offset)
        tests_failed = tests_failed + 1
    end

    -- Try to scroll way down (should clamp to max)
    ascii_upgrade_panel.scroll_by_wheel(999)
    scroll_info = ascii_upgrade_panel.get_scroll_info()
    local expected_max = math.max(0, 12 - 8)  -- 12 upgrades - 8 visible = 4

    if scroll_info.offset == expected_max then
        print("✅ PASS: Scroll down clamped to max (" .. expected_max .. ")")
        tests_passed = tests_passed + 1
    else
        print("❌ FAIL: Scroll not clamped to max, offset:", scroll_info.offset, "expected:", expected_max)
        tests_failed = tests_failed + 1
    end

    -- Test 5: Click outside panel bounds
    print("\nTest 5: Click outside panel")

    local outside_y = rect.y - 10  -- Above panel
    handled = ascii_upgrade_panel.handle_click(test_x, outside_y, upgrades_module, resources_module)

    if not handled then
        print("✅ PASS: Click outside panel correctly ignored")
        tests_passed = tests_passed + 1
    else
        print("❌ FAIL: Click outside panel was handled")
        tests_failed = tests_failed + 1
    end

    -- Summary
    print(string.format("\n🏁 Test Summary: %d passed, %d failed", tests_passed, tests_failed))

    if tests_failed == 0 then
        print("🎉 All tests passed! Upgrade panel click mapping works correctly:")
        print("  ✅ Clicks map to correct upgrades without scrolling")
        print("  ✅ Clicks map to correct upgrades after scrolling")
        print("  ✅ Click calculation accounts for scroll offset properly")
        print("  ✅ Scroll bounds are enforced (no over-scrolling)")
        print("  ✅ Clicks outside panel are ignored")
        print("  ✅ Buy clicks work correctly after scrolling")
        return true
    else
        print("⚠️ Some tests failed - click mapping may have issues!")
        return false
    end
end

-- Run the test
return test_click_mapping_after_scroll()
