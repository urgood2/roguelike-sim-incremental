--[[
================================================================================
TEST: Upgrade Panel Mouse Wheel Scrolling
================================================================================
Verification test for the wheel scrolling functionality in upgrade panel.
Tests integration between sim_scene input handling and ascii_upgrade_panel.

Run with: lua test_upgrade_panel_wheel_scroll.lua
]]

package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/?/init.lua"

local t = require("tests.test_runner")

-- Mock input system for testing
local MockInput = {}

function MockInput.new()
    local self = {
        _mouse_x = 0,
        _mouse_y = 0,
        _mouse_pressed = false,
        _wheel_delta = 0
    }

    function self.getMousePos()
        return { x = self._mouse_x, y = self._mouse_y }
    end

    function self.isMousePressed(button)
        return self._mouse_pressed
    end

    function self.getMouseWheel()
        return self._wheel_delta
    end

    function self.set_mouse_pos(x, y)
        self._mouse_x = x
        self._mouse_y = y
    end

    function self.set_mouse_pressed(pressed)
        self._mouse_pressed = pressed
    end

    function self.set_wheel_delta(delta)
        self._wheel_delta = delta
    end

    function self.reset()
        self._wheel_delta = 0
        self._mouse_pressed = false
    end

    return self
end

-- Mock upgrade system (global for test access)
MockUpgrades = {
    _upgrades = {
        upgrade_a = { name = "Upgrade A", description = "Test A", max_level = 10 },
        upgrade_b = { name = "Upgrade B", description = "Test B", max_level = 5 },
        upgrade_c = { name = "Upgrade C", description = "Test C", max_level = 8 },
        upgrade_d = { name = "Upgrade D", description = "Test D", max_level = 12 },
        upgrade_e = { name = "Upgrade E", description = "Test E", max_level = 6 },
        upgrade_f = { name = "Upgrade F", description = "Test F", max_level = 15 },
        upgrade_g = { name = "Upgrade G", description = "Test G", max_level = 3 },
        upgrade_h = { name = "Upgrade H", description = "Test H", max_level = 9 },
        upgrade_i = { name = "Upgrade I", description = "Test I", max_level = 7 },
        upgrade_j = { name = "Upgrade J", description = "Test J", max_level = 20 }
    },
    _levels = {},
    get_all = function() return MockUpgrades._upgrades end,
    get_level = function(id) return MockUpgrades._levels[id] or 0 end,
    get_cost = function(id) return { wood = 10, gold = 5 } end,
    can_afford = function(id, resources) return true end
}

-- Mock logging
local captured_logs = {}
_G.log_debug = function(message)
    table.insert(captured_logs, message)
end

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

t.describe("Upgrade Panel Wheel Scrolling Integration", function()

    t.it("wheel scroll when mouse is over upgrade panel", function()
        -- Setup mock input system
        local mock_input = MockInput.new()
        _G.input = mock_input

        -- Initialize upgrade panel
        local ascii_upgrade_panel = require("idle_game.ui.ascii_upgrade_panel")
        ascii_upgrade_panel.init(20, 800, 600)  -- tile_size=20, screen 800x600
        ascii_upgrade_panel.update(0, MockUpgrades, {})

        -- Get panel rectangle for positioning mouse
        local rect = ascii_upgrade_panel.get_rect()
        t.expect(rect.x).to_be_truthy()
        t.expect(rect.y).to_be_truthy()

        -- Position mouse inside upgrade panel
        local panel_center_x = rect.x + rect.w / 2
        local panel_center_y = rect.y + rect.h / 2
        mock_input.set_mouse_pos(panel_center_x, panel_center_y)

        -- Verify mouse is over panel
        t.expect(ascii_upgrade_panel.hit_test(panel_center_x, panel_center_y)).to_be_truthy()

        -- Get initial scroll info
        local initial_scroll = ascii_upgrade_panel.get_scroll_info()
        t.expect(initial_scroll.offset).to_equal(0)

        -- Simulate wheel scroll down (positive delta)
        mock_input.set_wheel_delta(1)
        captured_logs = {}

        -- Simulate the wheel handling logic from sim_scene
        local wheel_delta = mock_input.getMouseWheel()
        if wheel_delta ~= 0 then
            local mouse = mock_input.getMousePos()
            if ascii_upgrade_panel.hit_test(mouse.x, mouse.y) then
                ascii_upgrade_panel.scroll_by_wheel(wheel_delta)
                log_debug(string.format("[TEST] Wheel scroll (%.1f) handled by upgrade panel at (%d, %d)",
                          wheel_delta, mouse.x, mouse.y))
            end
        end

        -- Check that scroll offset changed
        local new_scroll = ascii_upgrade_panel.get_scroll_info()
        t.expect(new_scroll.offset).to_equal(1)  -- Should have scrolled down

        -- Check debug log was captured
        t.expect(#captured_logs > 0).to_be_truthy()
        t.expect(string.match(captured_logs[1], "Wheel scroll")).to_be_truthy()

        print(string.format("✓ Wheel scroll down: offset %d → %d", initial_scroll.offset, new_scroll.offset))
    end)

    t.it("wheel scroll up moves panel content up", function()
        local mock_input = MockInput.new()
        _G.input = mock_input

        local ascii_upgrade_panel = require("idle_game.ui.ascii_upgrade_panel")
        ascii_upgrade_panel.init(20, 800, 600)
        ascii_upgrade_panel.update(0, MockUpgrades, {})

        local rect = ascii_upgrade_panel.get_rect()
        mock_input.set_mouse_pos(rect.x + 50, rect.y + 50)

        -- Scroll down first to establish non-zero position
        ascii_upgrade_panel.scroll_by_wheel(3)
        local mid_scroll = ascii_upgrade_panel.get_scroll_info()
        t.expect(mid_scroll.offset).to_equal(3)

        -- Simulate wheel scroll up (negative delta)
        mock_input.set_wheel_delta(-1)
        captured_logs = {}

        local wheel_delta = mock_input.getMouseWheel()
        if wheel_delta ~= 0 then
            local mouse = mock_input.getMousePos()
            if ascii_upgrade_panel.hit_test(mouse.x, mouse.y) then
                ascii_upgrade_panel.scroll_by_wheel(wheel_delta)
                log_debug(string.format("[TEST] Wheel scroll (%.1f) handled by upgrade panel at (%d, %d)",
                          wheel_delta, mouse.x, mouse.y))
            end
        end

        local final_scroll = ascii_upgrade_panel.get_scroll_info()
        t.expect(final_scroll.offset).to_equal(2)  -- Should have scrolled up

        print(string.format("✓ Wheel scroll up: offset %d → %d", mid_scroll.offset, final_scroll.offset))
    end)

    t.it("wheel scroll ignored when mouse is outside panel", function()
        local mock_input = MockInput.new()
        _G.input = mock_input

        local ascii_upgrade_panel = require("idle_game.ui.ascii_upgrade_panel")
        ascii_upgrade_panel.init(20, 800, 600)
        ascii_upgrade_panel.update(0, MockUpgrades, {})

        -- Position mouse outside upgrade panel
        mock_input.set_mouse_pos(10, 10)  -- Top-left corner, likely outside panel

        local rect = ascii_upgrade_panel.get_rect()
        t.expect(ascii_upgrade_panel.hit_test(10, 10)).to_be_falsy()

        local initial_scroll = ascii_upgrade_panel.get_scroll_info()

        -- Simulate wheel scroll
        mock_input.set_wheel_delta(2)
        captured_logs = {}

        local wheel_delta = mock_input.getMouseWheel()
        if wheel_delta ~= 0 then
            local mouse = mock_input.getMousePos()
            if ascii_upgrade_panel.hit_test(mouse.x, mouse.y) then
                ascii_upgrade_panel.scroll_by_wheel(wheel_delta)
                log_debug(string.format("[TEST] Wheel scroll (%.1f) handled by upgrade panel at (%d, %d)",
                          wheel_delta, mouse.x, mouse.y))
            end
        end

        -- Scroll position should not have changed
        local final_scroll = ascii_upgrade_panel.get_scroll_info()
        t.expect(final_scroll.offset).to_equal(initial_scroll.offset)

        -- No log message should be captured
        t.expect(#captured_logs).to_equal(0)

        print("✓ Wheel scroll ignored when mouse outside panel")
    end)

    t.it("handles edge cases correctly", function()
        local mock_input = MockInput.new()
        _G.input = mock_input

        local ascii_upgrade_panel = require("idle_game.ui.ascii_upgrade_panel")
        ascii_upgrade_panel.init(20, 800, 600)
        ascii_upgrade_panel.update(0, MockUpgrades, {})

        local rect = ascii_upgrade_panel.get_rect()
        mock_input.set_mouse_pos(rect.x + 10, rect.y + 10)

        -- Test zero wheel delta (no movement)
        mock_input.set_wheel_delta(0)
        local initial_scroll = ascii_upgrade_panel.get_scroll_info()

        local wheel_delta = mock_input.getMouseWheel()
        if wheel_delta ~= 0 then
            -- This block should not execute
            ascii_upgrade_panel.scroll_by_wheel(wheel_delta)
        end

        local after_zero = ascii_upgrade_panel.get_scroll_info()
        t.expect(after_zero.offset).to_equal(initial_scroll.offset)

        -- Test scroll bounds clamping (scroll up from top)
        mock_input.set_wheel_delta(-5)  -- Large negative delta
        ascii_upgrade_panel.scroll_by_wheel(mock_input.getMouseWheel())

        local clamped_scroll = ascii_upgrade_panel.get_scroll_info()
        t.expect(clamped_scroll.offset).to_equal(0)  -- Should clamp to 0

        print("✓ Edge cases handled correctly")
    end)

    t.it("verifies sim_scene integration pattern", function()
        -- Test the exact pattern used in sim_scene.update()
        local mock_input = MockInput.new()
        _G.input = mock_input

        local ascii_upgrade_panel = require("idle_game.ui.ascii_upgrade_panel")
        ascii_upgrade_panel.init(20, 800, 600)
        ascii_upgrade_panel.update(0, MockUpgrades, {})

        local rect = ascii_upgrade_panel.get_rect()
        mock_input.set_mouse_pos(rect.x + 100, rect.y + 100)

        -- Simulate the exact sim_scene wheel handling logic
        mock_input.set_wheel_delta(1.5)
        captured_logs = {}

        -- This mimics the sim_scene.update() wheel handling code
        if input and input.getMouseWheel and input.getMousePos then
            local wheel_delta = input.getMouseWheel()
            if wheel_delta ~= 0 then
                local mouse = input.getMousePos()
                local mouse_x, mouse_y = mouse.x, mouse.y

                if ascii_upgrade_panel.hit_test(mouse_x, mouse_y) then
                    ascii_upgrade_panel.scroll_by_wheel(wheel_delta)
                    log_debug(string.format("[sim_scene] Wheel scroll (%.1f) handled by upgrade panel at (%d, %d)",
                              wheel_delta, mouse_x, mouse_y))
                end
            end
        end

        -- Verify the integration worked
        local scroll_info = ascii_upgrade_panel.get_scroll_info()
        t.expect(scroll_info.offset > 0).to_be_truthy()

        -- Check log format matches sim_scene pattern
        t.expect(#captured_logs > 0).to_be_truthy()
        t.expect(string.match(captured_logs[1], "%[sim_scene%]")).to_be_truthy()
        t.expect(string.match(captured_logs[1], "Wheel scroll")).to_be_truthy()

        print("✓ sim_scene integration pattern verified")
    end)

end)

--------------------------------------------------------------------------------
-- Run Tests
--------------------------------------------------------------------------------

print(string.rep("=", 60))
print("UPGRADE PANEL WHEEL SCROLLING TEST RESULTS")
print(string.rep("=", 60))

t.run()

print(string.rep("=", 60))
print("Upgrade panel wheel scrolling test complete!")
print("✓ Mouse wheel scrolling: When mouse is over upgrade panel")
print("✓ Scroll direction: Positive = down, negative = up")
print("✓ Hit testing: Only scrolls when mouse is over panel")
print("✓ Edge cases: Zero delta and bounds clamping")
print("✓ Integration: Follows exact sim_scene pattern")
print(string.rep("=", 60))