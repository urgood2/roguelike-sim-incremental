--[[
================================================================================
TEST: Toast Layout Calculation
================================================================================
Tests toast positioning calculation anchored in sidebar with padding.

Run with: lua assets/scripts/tests/test_toast_layout.lua
]]

--------------------------------------------------------------------------------
-- Setup (REQUIRED for tests to find modules)
--------------------------------------------------------------------------------

package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/?/init.lua"

-- Clear cached module if re-running
package.loaded["idle_game.ui.toast_queue"] = nil

local t = require("tests.test_runner")

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

t.describe("Toast Layout Calculation", function()

    t.it("calculates positions anchored in sidebar with padding", function()
        local toast_queue = require("idle_game.ui.toast_queue")

        local sidebar_config = { x = 100, y = 50, w = 200, h = 400 }
        local toast_config = { w = 150, h = 30, padding = 8 }
        local visible_toasts = {
            { id = 1, text = "First", age = 0, duration = 3, progress = 0 },
            { id = 2, text = "Second", age = 1, duration = 3, progress = 0.33 },
            { id = 3, text = "Third", age = 2, duration = 3, progress = 0.67 }
        }

        local positioned = toast_queue.calculate_layout(sidebar_config, toast_config, visible_toasts)

        -- Check first toast position (anchor point)
        t.expect(positioned[1].x).to_equal(308)  -- 100 + 200 + 8
        t.expect(positioned[1].y).to_equal(58)   -- 50 + 8
        t.expect(positioned[1].w).to_equal(150)
        t.expect(positioned[1].h).to_equal(30)

        -- Check second toast position (spaced downward)
        t.expect(positioned[2].x).to_equal(308)
        t.expect(positioned[2].y).to_equal(96)   -- 58 + 30 + 8

        -- Check third toast position (further spaced)
        t.expect(positioned[3].x).to_equal(308)
        t.expect(positioned[3].y).to_equal(134)  -- 96 + 30 + 8

        -- Check toast data preservation
        t.expect(positioned[1].text).to_equal("First")
        t.expect(positioned[2].text).to_equal("Second")
        t.expect(positioned[3].text).to_equal("Third")
    end)

    t.it("handles empty visible toasts", function()
        local toast_queue = require("idle_game.ui.toast_queue")

        local sidebar_config = { x = 0, y = 0, w = 100, h = 200 }
        local toast_config = { w = 80, h = 25 }
        local visible_toasts = {}

        local positioned = toast_queue.calculate_layout(sidebar_config, toast_config, visible_toasts)

        t.expect(#positioned).to_equal(0)
    end)

    t.it("validates required configuration parameters", function()
        local toast_queue = require("idle_game.ui.toast_queue")

        -- Missing sidebar parameters should error
        t.expect(function()
            toast_queue.calculate_layout({}, { w = 50, h = 20 }, {})
        end).to_error()

        -- Missing toast parameters should error
        t.expect(function()
            toast_queue.calculate_layout({ x = 0, y = 0, w = 100, h = 200 }, {}, {})
        end).to_error()
    end)

end)

--------------------------------------------------------------------------------
-- Run tests (REQUIRED - produces "All tests passed" output)
--------------------------------------------------------------------------------

t.run()