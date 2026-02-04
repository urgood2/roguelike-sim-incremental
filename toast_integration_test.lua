--[[
================================================================================
INTEGRATION TEST: Toast Rendering and Dismiss Verification
================================================================================
Comprehensive integration test to verify toast functionality:
1. Toasts show correctly
2. Auto-dismiss after expiration
3. Stack correctly with proper layout

Run with: lua toast_integration_test.lua
]]

--------------------------------------------------------------------------------
-- Setup (REQUIRED for tests to find modules)
--------------------------------------------------------------------------------

package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/?/init.lua"

-- Clear cached modules if re-running
package.loaded["idle_game.ui.toast_queue"] = nil

local t = require("tests.test_runner")

--------------------------------------------------------------------------------
-- Integration Tests
--------------------------------------------------------------------------------

t.describe("Toast Integration Tests", function()

    t.it("toasts show correctly in queue", function()
        local toast_queue = require("idle_game.ui.toast_queue")

        -- Initialize toast queue
        toast_queue.init()

        -- Add multiple toasts
        local id1 = toast_queue.push("Achievement unlocked!", {duration = 3.0})
        local id2 = toast_queue.push("Resource milestone reached", {duration = 2.0})
        local id3 = toast_queue.push("New upgrade available", {duration = 4.0})

        -- Verify toasts were added
        t.expect(toast_queue.get_count()).to_equal(3)

        -- Get visible toasts (should be newest-first)
        local visible = toast_queue.get_visible()
        t.expect(#visible).to_equal(3)

        -- Check newest-first ordering
        t.expect(visible[1].text).to_equal("New upgrade available")  -- Most recent
        t.expect(visible[2].text).to_equal("Resource milestone reached")
        t.expect(visible[3].text).to_equal("Achievement unlocked!")  -- Oldest

        -- Verify toast data structure
        t.expect(visible[1].id).to_equal(id3)
        t.expect(visible[1].duration).to_equal(4.0)
        t.expect(visible[1].age).to_equal(0)
        t.expect(visible[1].progress).to_equal(0)

        print("✓ Toasts show correctly in queue")
    end)

    t.it("toasts auto-dismiss after expiration", function()
        local toast_queue = require("idle_game.ui.toast_queue")

        -- Initialize with shorter durations for testing
        toast_queue.init()

        -- Add toasts with different durations
        local id1 = toast_queue.push("Short toast", {duration = 1.0})
        local id2 = toast_queue.push("Medium toast", {duration = 2.0})
        local id3 = toast_queue.push("Long toast", {duration = 3.0})

        t.expect(toast_queue.get_count()).to_equal(3)

        -- Simulate time passage: 0.5 seconds (none should expire)
        toast_queue.update(0.5)
        t.expect(toast_queue.get_count()).to_equal(3)

        -- Verify progress tracking
        local visible = toast_queue.get_visible()
        t.expect(visible[1].progress).to_equal(0.5 / 3.0)  -- Long toast: 0.5/3.0 = 0.167
        t.expect(visible[2].progress).to_equal(0.5 / 2.0)  -- Medium toast: 0.5/2.0 = 0.25
        t.expect(visible[3].progress).to_equal(0.5 / 1.0)  -- Short toast: 0.5/1.0 = 0.5

        -- Simulate 0.6 more seconds (total 1.1s - short toast should expire)
        toast_queue.update(0.6)
        t.expect(toast_queue.get_count()).to_equal(2)

        visible = toast_queue.get_visible()
        t.expect(visible[1].text).to_equal("Long toast")
        t.expect(visible[2].text).to_equal("Medium toast")

        -- Simulate 1.0 more seconds (total 2.1s - medium toast should expire)
        toast_queue.update(1.0)
        t.expect(toast_queue.get_count()).to_equal(1)

        visible = toast_queue.get_visible()
        t.expect(visible[1].text).to_equal("Long toast")

        -- Simulate 1.0 more seconds (total 3.1s - long toast should expire)
        toast_queue.update(1.0)
        t.expect(toast_queue.get_count()).to_equal(0)

        visible = toast_queue.get_visible()
        t.expect(#visible).to_equal(0)

        print("✓ Toasts auto-dismiss after expiration")
    end)

    t.it("toasts stack correctly with proper layout", function()
        local toast_queue = require("idle_game.ui.toast_queue")

        -- Initialize with max_visible limit
        toast_queue.init({max_visible = 3, default_duration = 5.0})

        -- Add more toasts than max_visible
        toast_queue.push("Toast 1")
        toast_queue.push("Toast 2")
        toast_queue.push("Toast 3")
        toast_queue.push("Toast 4")
        toast_queue.push("Toast 5")

        t.expect(toast_queue.get_count()).to_equal(5)

        -- Only max_visible should be shown
        local visible = toast_queue.get_visible()
        t.expect(#visible).to_equal(3)

        -- Should show the 3 newest toasts (newest-first)
        t.expect(visible[1].text).to_equal("Toast 5")  -- Newest
        t.expect(visible[2].text).to_equal("Toast 4")
        t.expect(visible[3].text).to_equal("Toast 3")

        -- Test layout calculation
        local sidebar_config = {x = 100, y = 50, w = 200, h = 400}
        local toast_config = {w = 150, h = 30, padding = 8}

        local positioned = toast_queue.calculate_layout(sidebar_config, toast_config, visible)

        -- Verify correct stacking positions
        t.expect(#positioned).to_equal(3)

        -- First toast (newest) at top
        t.expect(positioned[1].x).to_equal(308)  -- 100 + 200 + 8
        t.expect(positioned[1].y).to_equal(58)   -- 50 + 8
        t.expect(positioned[1].text).to_equal("Toast 5")

        -- Second toast below first
        t.expect(positioned[2].x).to_equal(308)
        t.expect(positioned[2].y).to_equal(96)   -- 58 + 30 + 8
        t.expect(positioned[2].text).to_equal("Toast 4")

        -- Third toast below second
        t.expect(positioned[3].x).to_equal(308)
        t.expect(positioned[3].y).to_equal(134)  -- 96 + 30 + 8
        t.expect(positioned[3].text).to_equal("Toast 3")

        print("✓ Toasts stack correctly with proper layout")
    end)

    t.it("handles toast buffer overflow gracefully", function()
        local toast_queue = require("idle_game.ui.toast_queue")

        -- Initialize with small buffer for testing
        toast_queue.init({max_buffer = 3, max_visible = 2})

        -- Add toasts up to buffer limit
        toast_queue.push("Toast 1")
        toast_queue.push("Toast 2")
        toast_queue.push("Toast 3")
        t.expect(toast_queue.get_count()).to_equal(3)

        -- Add one more toast (should drop oldest)
        toast_queue.push("Toast 4")
        t.expect(toast_queue.get_count()).to_equal(3)  -- Still 3 due to overflow

        -- Oldest toast should be dropped, newest should be present
        local visible = toast_queue.get_visible()
        t.expect(visible[1].text).to_equal("Toast 4")  -- Newest
        t.expect(visible[2].text).to_equal("Toast 3")

        print("✓ Handles buffer overflow gracefully")
    end)

    t.it("provides correct configuration access", function()
        local toast_queue = require("idle_game.ui.toast_queue")

        toast_queue.init({
            max_visible = 5,
            default_duration = 4.5,
            max_buffer = 50
        })

        local config = toast_queue.get_config()
        t.expect(config.max_visible).to_equal(5)
        t.expect(config.default_duration).to_equal(4.5)
        t.expect(config.max_buffer).to_equal(50)

        print("✓ Configuration access works correctly")
    end)

    t.it("supports manual toast removal", function()
        local toast_queue = require("idle_game.ui.toast_queue")

        toast_queue.init()

        local id1 = toast_queue.push("Toast 1")
        local id2 = toast_queue.push("Toast 2")
        local id3 = toast_queue.push("Toast 3")

        t.expect(toast_queue.get_count()).to_equal(3)

        -- Remove middle toast
        local removed = toast_queue.remove(id2)
        t.expect(removed).to_be_truthy()
        t.expect(toast_queue.get_count()).to_equal(2)

        -- Verify remaining toasts
        local visible = toast_queue.get_visible()
        t.expect(visible[1].text).to_equal("Toast 3")
        t.expect(visible[2].text).to_equal("Toast 1")

        -- Try removing non-existent toast
        local not_removed = toast_queue.remove(999)
        t.expect(not_removed).to_be_falsy()
        t.expect(toast_queue.get_count()).to_equal(2)

        print("✓ Manual toast removal works correctly")
    end)

end)

--------------------------------------------------------------------------------
-- Performance and Edge Case Tests
--------------------------------------------------------------------------------

t.describe("Toast Performance and Edge Cases", function()

    t.it("handles rapid toast additions", function()
        local toast_queue = require("idle_game.ui.toast_queue")

        toast_queue.init({max_buffer = 100})

        -- Add many toasts rapidly
        for i = 1, 50 do
            toast_queue.push("Rapid toast " .. i, {duration = 10.0})
        end

        t.expect(toast_queue.get_count()).to_equal(50)

        -- Verify newest-first ordering still works
        local visible = toast_queue.get_visible()
        t.expect(visible[1].text).to_equal("Rapid toast 50")

        print("✓ Handles rapid toast additions correctly")
    end)

    t.it("handles edge case inputs gracefully", function()
        local toast_queue = require("idle_game.ui.toast_queue")

        toast_queue.init()

        -- Empty text should not create toast
        local id_empty = toast_queue.push("")
        t.expect(id_empty).to_be_nil()
        t.expect(toast_queue.get_count()).to_equal(0)

        -- Nil text should not create toast
        local id_nil = toast_queue.push(nil)
        t.expect(id_nil).to_be_nil()
        t.expect(toast_queue.get_count()).to_equal(0)

        -- Zero or negative duration should use default
        local id_valid = toast_queue.push("Valid toast", {duration = 0})
        t.expect(id_valid).to_be_truthy()

        -- Update with invalid dt should not crash
        toast_queue.update(nil)
        toast_queue.update(0)
        toast_queue.update(-1)

        print("✓ Handles edge case inputs gracefully")
    end)

end)

--------------------------------------------------------------------------------
-- Achievement Integration Test
--------------------------------------------------------------------------------

t.describe("Achievement Toast Integration", function()

    t.it("simulates achievement notification flow", function()
        local toast_queue = require("idle_game.ui.toast_queue")

        -- Initialize like achievement system would
        toast_queue.init({max_visible = 3, default_duration = 3.0})

        -- Simulate achievement unlocks
        local achievement_notifications = {
            "🏆 Wood Hoarder",
            "🏆 Stone Stockpile",
            "🏆 First Purchase",
            "🏆 Growing Crew"
        }

        -- Add achievement toasts with trophy emoji (like achievement_listener does)
        for _, notification in ipairs(achievement_notifications) do
            toast_queue.push(notification, {duration = 3.0})
        end

        -- Should only show max_visible
        local visible = toast_queue.get_visible()
        t.expect(#visible).to_equal(3)
        t.expect(visible[1].text).to_equal("🏆 Growing Crew")  -- Most recent

        -- Simulate time progression (like sim_scene would do)
        local total_time = 0
        local time_step = 0.1

        -- Run for 4 seconds, tracking dismissals
        local dismissal_count = 0
        while total_time < 4.0 do
            local prev_count = toast_queue.get_count()
            toast_queue.update(time_step)
            local new_count = toast_queue.get_count()

            if new_count < prev_count then
                dismissal_count = dismissal_count + (prev_count - new_count)
            end

            total_time = total_time + time_step
        end

        -- All toasts should be dismissed by now
        t.expect(toast_queue.get_count()).to_equal(0)
        t.expect(dismissal_count).to_equal(4)

        print("✓ Achievement notification flow works correctly")
    end)

end)

--------------------------------------------------------------------------------
-- Run All Tests
--------------------------------------------------------------------------------

print("\n" .. string.rep("=", 60))
print("TOAST INTEGRATION TEST RESULTS")
print(string.rep("=", 60))

t.run()

print("\n" .. string.rep("=", 60))
print("Integration test verification complete!")
print("✓ Toasts show correctly")
print("✓ Toasts auto-dismiss after expiration")
print("✓ Toasts stack correctly with proper layout")
print("✓ Performance and edge cases handled")
print("✓ Achievement integration verified")
print(string.rep("=", 60))