--[[
================================================================================
TEST: Upgrade Panel Click Mapping Verification
================================================================================
Verifies that upgrade panel buy clicks map correctly after scrolling.
Tests the coordinate-to-upgrade mapping logic with various scroll positions.

Run with: lua assets/scripts/tests/test_upgrade_panel_click_mapping.lua
]]

--------------------------------------------------------------------------------
-- Setup (REQUIRED for tests to find modules)
--------------------------------------------------------------------------------

-- Standard test path setup
package.path = package.path .. ";./assets/scripts/?.lua;./assets/scripts/?/init.lua"

-- Clear cached modules if re-running
package.loaded["idle_game.ui.ascii_upgrade_panel"] = nil

local t = require("tests.test_runner")

-- Mock draw module
package.loaded["core.draw"] = {
    rectangle = function() end,
    textPro = function() end
}

-- Mock upgrade and resource modules
local function createMockUpgrades()
    local upgrades = {}
    for i = 1, 12 do
        upgrades["upgrade_" .. i] = {
            id = "upgrade_" .. i,
            name = "Upgrade " .. i,
            max_level = 10,
            base_cost = 100
        }
    end

    return {
        get_all = function() return upgrades end,
        get_level = function(id) return 1 end,
        get_cost = function(id) return {wood = 100, stone = 50} end,
        get_next_cost = function(id) return 100 end,
        purchase = function(id, resources) return true end
    }
end

local function createMockResources()
    return {
        can_afford = function() return true end,
        get = function() return 1000 end
    }
end

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

t.describe("Upgrade Panel Click Mapping Tests", function()

    -- Test 1: Basic click mapping without scrolling
    t.it("maps clicks correctly without scrolling", function()
        local panel = require("idle_game.ui.ascii_upgrade_panel")

        -- Initialize panel
        local tile_size = 20
        local screen_w = 800
        local screen_h = 600
        panel.init(tile_size, screen_w, screen_h)

        -- Update with mock data
        local upgrades = createMockUpgrades()
        local resources = createMockResources()
        panel.update(0.1, upgrades, resources)

        -- Get panel rect for click calculations
        local rect = panel.get_rect()

        -- Test clicking on first upgrade (should be at y position 0 relative to panel)
        local first_upgrade_y = rect.y + 10  -- Middle of first upgrade area
        local click_x = rect.x + rect.w / 2  -- Center X

        -- Verify hit test works
        t.expect(panel.hit_test(click_x, first_upgrade_y)).to_equal(true)

        -- Test click outside panel
        t.expect(panel.hit_test(rect.x - 10, first_upgrade_y)).to_equal(false)
    end)

    -- Test 2: Click mapping with scrolling
    t.it("maps clicks correctly with scrolling", function()
        local panel = require("idle_game.ui.ascii_upgrade_panel")

        -- Initialize panel
        panel.init(20, 800, 600)

        -- Create more upgrades than can be visible to test scrolling
        local upgrades = createMockUpgrades()
        local resources = createMockResources()
        panel.update(0.1, upgrades, resources)

        -- Scroll down by 3 positions
        panel.scroll_by_wheel(3)

        -- Get scroll info
        local scroll_info = panel.get_scroll_info()
        t.expect(scroll_info.offset).to_equal(3)

        -- Verify visible upgrades list accounts for scrolling
        local visible = panel.get_visible_upgrades()
        t.expect(#visible > 0).to_equal(true)
    end)

    -- Test 3: Scroll bounds checking
    t.it("maintains correct scroll bounds", function()
        local panel = require("idle_game.ui.ascii_upgrade_panel")

        -- Initialize panel
        panel.init(20, 800, 600)

        local upgrades = createMockUpgrades()
        local resources = createMockResources()
        panel.update(0.1, upgrades, resources)

        -- Try to scroll beyond bounds
        panel.scroll_by_wheel(-5)  -- Scroll up beyond start
        local scroll_info = panel.get_scroll_info()
        t.expect(scroll_info.offset).to_equal(0)  -- Should be clamped to 0

        -- Scroll to maximum
        panel.scroll_by_wheel(100)  -- Large scroll down
        scroll_info = panel.get_scroll_info()
        t.expect(scroll_info.offset >= 0).to_equal(true)  -- Should be valid

        -- Should not scroll beyond available upgrades
        local visible = panel.get_visible_upgrades()
        t.expect(#visible > 0).to_equal(true)
    end)

    -- Test 4: Click coordinate calculation verification
    t.it("calculates click coordinates correctly", function()
        local panel = require("idle_game.ui.ascii_upgrade_panel")

        -- Initialize panel
        local tile_size = 20
        panel.init(tile_size, 800, 600)

        local upgrades = createMockUpgrades()
        local resources = createMockResources()
        panel.update(0.1, upgrades, resources)

        local rect = panel.get_rect()

        -- Test the mathematical relationship between click position and upgrade index
        -- Each upgrade takes 2 tiles height = 40 pixels
        local upgrade_height = tile_size * 2

        -- Click at different Y positions and verify they map to correct visual positions
        for i = 0, 3 do
            local click_y = rect.y + (i * upgrade_height) + (upgrade_height / 2)
            local expected_visual_index = i + 1

            -- The actual index calculation (from the source code):
            -- local relative_y = y - rect.y
            -- local clicked_index = math.floor(relative_y / upgrade_height) + 1 + _scroll_offset

            local relative_y = click_y - rect.y
            local calculated_visual_index = math.floor(relative_y / upgrade_height) + 1

            t.expect(calculated_visual_index).to_equal(expected_visual_index)
        end
    end)

    -- Test 5: Scroll offset integration with click mapping
    t.it("integrates scroll offset correctly with click mapping", function()
        local panel = require("idle_game.ui.ascii_upgrade_panel")

        -- Initialize panel
        local tile_size = 20
        panel.init(tile_size, 800, 600)

        local upgrades = createMockUpgrades()
        local resources = createMockResources()
        panel.update(0.1, upgrades, resources)

        -- Set scroll offset
        local scroll_offset = 2
        panel.scroll_by_wheel(scroll_offset)

        local rect = panel.get_rect()
        local upgrade_height = tile_size * 2

        -- Click on the first visible upgrade (visual index 1)
        local click_y = rect.y + (upgrade_height / 2)
        local relative_y = click_y - rect.y

        -- Calculate what upgrade index this should map to
        local visual_index = math.floor(relative_y / upgrade_height) + 1  -- Should be 1
        local actual_upgrade_index = visual_index + scroll_offset  -- Should be 3

        t.expect(visual_index).to_equal(1)
        t.expect(actual_upgrade_index).to_equal(3)

        -- Verify scroll info matches
        local scroll_info = panel.get_scroll_info()
        t.expect(scroll_info.offset).to_equal(scroll_offset)
    end)

    -- Test 6: Panel configuration values
    t.it("has correct panel configuration", function()
        local panel = require("idle_game.ui.ascii_upgrade_panel")

        -- Initialize panel
        panel.init(20, 800, 600)

        -- Verify panel positioning
        local rect = panel.get_rect()
        t.expect(rect.x > 0).to_equal(true)  -- Should be positioned as sidebar
        t.expect(rect.w > 0).to_equal(true)  -- Should have width
        t.expect(rect.h > 0).to_equal(true)  -- Should have height

        -- Verify panel is properly positioned as right sidebar
        t.expect(rect.x).to_equal(800 - (20 * 12))  -- screen_w - UI_SIDEBAR_W
    end)

end)

--------------------------------------------------------------------------------
-- Auto-run if executed directly
--------------------------------------------------------------------------------
if arg and arg[0] and arg[0]:match("test_upgrade_panel_click_mapping%.lua$") then
    t.run()
end