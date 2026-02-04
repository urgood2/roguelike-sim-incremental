#!/usr/bin/env lua
--[[
================================================================================
INTEGRATION TEST: Idle Toast Queue System
================================================================================
Tests the toast queue system functionality including:
1. Auto-dismiss behavior after duration expires
2. Buffer cap enforcement (drops oldest when exceeded)
3. get_visible ordering (newest-first)

Run with: lua test_idle_toast_queue.lua
]]

--------------------------------------------------------------------------------
-- Setup (REQUIRED for tests to find modules)
--------------------------------------------------------------------------------

package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/?/init.lua"

-- Clear cached modules if re-running
package.loaded["idle_game.ui.toast_queue"] = nil
package.loaded["idle_game.ui.queue"] = nil

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

local t = require("tests.test_runner")

t.describe("Toast Queue System", function()

    t.it("auto-dismiss removes expired toasts", function()
        local queue = require("idle_game.ui.queue")

        -- Initialize queue with short durations for testing
        queue.init({
            max_visible = 5,
            default_duration = 0.5,  -- 0.5 second default
            max_buffer = 10
        })

        -- Add toasts with different durations
        local id1 = queue.push("Short message", {duration = 0.1})  -- 0.1 second
        local id2 = queue.push("Medium message", {duration = 0.3}) -- 0.3 second
        local id3 = queue.push("Long message", {duration = 1.0})   -- 1.0 second

        -- Verify all toasts are initially present
        t.expect(queue.get_count()).to_equal(3)
        local visible = queue.get_visible()
        t.expect(#visible).to_equal(3)

        -- Update with 0.15 seconds - should expire first toast
        queue.update(0.15)
        t.expect(queue.get_count()).to_equal(2)
        visible = queue.get_visible()
        t.expect(#visible).to_equal(2)

        -- Remaining toasts should be medium and long
        local texts = {}
        for _, toast in ipairs(visible) do
            table.insert(texts, toast.text)
        end
        t.expect(texts[1]).to_equal("Long message")    -- Newest first
        t.expect(texts[2]).to_equal("Medium message")

        -- Update with another 0.2 seconds (0.35 total) - should expire medium toast
        queue.update(0.2)
        t.expect(queue.get_count()).to_equal(1)
        visible = queue.get_visible()
        t.expect(#visible).to_equal(1)
        t.expect(visible[1].text).to_equal("Long message")

        -- Update with 0.7 more seconds (1.05 total) - should expire all
        queue.update(0.7)
        t.expect(queue.get_count()).to_equal(0)
        visible = queue.get_visible()
        t.expect(#visible).to_equal(0)

        print("✅ Auto-dismiss behavior works correctly")
    end)

    t.it("buffer cap drops oldest toasts when exceeded", function()
        local queue = require("idle_game.ui.queue")

        -- Initialize with small buffer for testing
        queue.init({
            max_visible = 10,
            default_duration = 5.0,  -- Long duration so toasts don't expire
            max_buffer = 3           -- Small buffer to test cap
        })

        -- Add toasts to fill buffer
        local id1 = queue.push("Toast 1")
        local id2 = queue.push("Toast 2")
        local id3 = queue.push("Toast 3")

        -- Verify buffer is full
        t.expect(queue.get_count()).to_equal(3)

        -- Add fourth toast - should drop oldest (Toast 1)
        local id4 = queue.push("Toast 4")
        t.expect(queue.get_count()).to_equal(3)  -- Still capped at 3

        -- Check remaining toasts are newest 3
        local visible = queue.get_visible()
        t.expect(#visible).to_equal(3)

        local texts = {}
        for _, toast in ipairs(visible) do
            table.insert(texts, toast.text)
        end

        -- Should have Toast 2, 3, 4 (oldest Toast 1 dropped)
        t.expect(texts[1]).to_equal("Toast 4")  -- Newest first
        t.expect(texts[2]).to_equal("Toast 3")
        t.expect(texts[3]).to_equal("Toast 2")

        -- Add fifth toast - should drop Toast 2
        local id5 = queue.push("Toast 5")
        t.expect(queue.get_count()).to_equal(3)

        visible = queue.get_visible()
        texts = {}
        for _, toast in ipairs(visible) do
            table.insert(texts, toast.text)
        end

        -- Should have Toast 3, 4, 5 (Toast 2 dropped)
        t.expect(texts[1]).to_equal("Toast 5")  -- Newest first
        t.expect(texts[2]).to_equal("Toast 4")
        t.expect(texts[3]).to_equal("Toast 3")

        print("✅ Buffer cap enforcement works correctly")
    end)

    t.it("get_visible returns newest-first ordering", function()
        local queue = require("idle_game.ui.queue")

        -- Initialize with sufficient capacity
        queue.init({
            max_visible = 5,
            default_duration = 5.0,
            max_buffer = 10
        })

        -- Add toasts in sequence
        local timestamps = {}

        local id1 = queue.push("First toast")
        table.insert(timestamps, os.time())

        -- Small delay to ensure different timestamps
        os.execute("sleep 0.01")

        local id2 = queue.push("Second toast")
        table.insert(timestamps, os.time())

        os.execute("sleep 0.01")

        local id3 = queue.push("Third toast")
        table.insert(timestamps, os.time())

        -- Get visible toasts
        local visible = queue.get_visible()
        t.expect(#visible).to_equal(3)

        -- Verify newest-first ordering
        t.expect(visible[1].text).to_equal("Third toast")   -- Newest (index 1)
        t.expect(visible[2].text).to_equal("Second toast")  -- Middle
        t.expect(visible[3].text).to_equal("First toast")   -- Oldest (index 3)

        -- Verify each toast has correct structure
        for i, toast in ipairs(visible) do
            t.expect(toast.id).to_be_truthy()
            t.expect(toast.text).to_be_truthy()
            t.expect(toast.duration).to_be_truthy()
            t.expect(toast.age >= 0).to_be_truthy()
            t.expect(toast.progress >= 0 and toast.progress <= 1).to_be_truthy()
        end

        print("✅ get_visible ordering (newest-first) works correctly")
    end)

    t.it("max_visible limits returned toasts correctly", function()
        local queue = require("idle_game.ui.queue")

        -- Initialize with max_visible = 2
        queue.init({
            max_visible = 2,
            default_duration = 5.0,
            max_buffer = 10
        })

        -- Add 5 toasts
        queue.push("Toast A")
        queue.push("Toast B")
        queue.push("Toast C")
        queue.push("Toast D")
        queue.push("Toast E")

        -- All should be in buffer
        t.expect(queue.get_count()).to_equal(5)

        -- Only newest 2 should be visible
        local visible = queue.get_visible()
        t.expect(#visible).to_equal(2)

        t.expect(visible[1].text).to_equal("Toast E")  -- Newest
        t.expect(visible[2].text).to_equal("Toast D")  -- Second newest

        print("✅ max_visible limit works correctly")
    end)

    t.it("progress calculation is accurate", function()
        local queue = require("idle_game.ui.queue")

        queue.init({
            max_visible = 5,
            default_duration = 2.0,
            max_buffer = 10
        })

        -- Add toast with known duration
        local id = queue.push("Progress test", {duration = 1.0})

        -- Check initial progress (should be near 0)
        local visible = queue.get_visible()
        t.expect(visible[1].progress < 0.1).to_be_truthy()

        -- Update halfway through duration
        queue.update(0.5)
        visible = queue.get_visible()
        t.expect(visible[1].progress >= 0.4 and visible[1].progress <= 0.6).to_be_truthy()

        -- Update to near end of duration
        queue.update(0.4)  -- Total 0.9 seconds
        visible = queue.get_visible()
        t.expect(visible[1].progress >= 0.8 and visible[1].progress <= 1.0).to_be_truthy()

        print("✅ Progress calculation is accurate")
    end)

    t.it("configuration parameters work correctly", function()
        local queue = require("idle_game.ui.queue")

        -- Test custom configuration
        queue.init({
            max_visible = 7,
            default_duration = 1.5,
            max_buffer = 5
        })

        -- Test default duration is applied
        local id1 = queue.push("Default duration test")
        local visible = queue.get_visible()
        t.expect(visible[1].duration).to_equal(1.5)

        -- Test custom duration overrides default
        local id2 = queue.push("Custom duration test", {duration = 3.0})
        visible = queue.get_visible()

        -- Find the custom duration toast (newest first)
        local custom_toast = visible[1]  -- Should be the newest
        t.expect(custom_toast.text).to_equal("Custom duration test")
        t.expect(custom_toast.duration).to_equal(3.0)

        print("✅ Configuration parameters work correctly")
    end)

    t.it("edge cases handle gracefully", function()
        local queue = require("idle_game.ui.queue")

        queue.init({
            max_visible = 3,
            default_duration = 1.0,
            max_buffer = 5
        })

        -- Test empty queue operations
        t.expect(queue.get_count()).to_equal(0)
        t.expect(#queue.get_visible()).to_equal(0)

        -- Update empty queue should not crash
        queue.update(1.0)
        t.expect(queue.get_count()).to_equal(0)

        -- Test zero duration toast
        local id = queue.push("Zero duration", {duration = 0.0})
        t.expect(queue.get_count()).to_equal(1)

        -- Should expire immediately on any update
        queue.update(0.001)
        t.expect(queue.get_count()).to_equal(0)

        -- Test very large duration
        local id2 = queue.push("Large duration", {duration = 999999})
        visible = queue.get_visible()
        t.expect(visible[1].duration).to_equal(999999)

        queue.update(1000)  -- 1000 seconds later, should still exist
        t.expect(queue.get_count()).to_equal(1)

        print("✅ Edge cases handled gracefully")
    end)

end)

--------------------------------------------------------------------------------
-- Run tests (REQUIRED - produces "All tests passed" output)
--------------------------------------------------------------------------------

t.run()